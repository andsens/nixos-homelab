{ self, ... }:
{
  inputs,
  lib,
  pkgs,
  config,
  ...
}:
let
  ccfg = config.homeServer.cluster;
  flakePkgs = self.packages.${pkgs.stdenv.hostPlatform.system};
  ipv4 = self.lib.ip.v4;
  kubelib = inputs.kube-generators.lib { inherit pkgs; };
  k3sConfig = kubelib.toYAMLFile ({
    data-dir = "${ccfg.dataPath}/k3s";
    flannel-backend = "none";
    egress-selector-mode = "disabled";
    disable-network-policy = true;
    disable-kube-proxy = true;
    disable-helm-controller = true;
    embedded-registry = true;
    kube-apiserver-arg = [ "service-node-port-range=1024-32767" ];
    cluster-cidr =
      lib.optional ccfg.enableIPv4 ccfg.podCidr4 ++ lib.optional ccfg.enableIPv6 ccfg.podCidr6;
    service-cidr =
      lib.optional ccfg.enableIPv4 ccfg.svcCidr4 ++ lib.optional ccfg.enableIPv6 ccfg.svcCidr6;
    tls-san = "external.${ccfg.domain}";
    kube-controller-manager-arg = [
      "allocate-node-cidrs"
    ]
    ++ lib.optional ccfg.enableIPv4 "node-cidr-mask-size-ipv4=${builtins.toString (ipv4.fromString ccfg.podCidr4).prefixLength}"
    ++ lib.optional ccfg.enableIPv6 "node-cidr-mask-size-ipv6=96";
  });
in
{
  options.homeServer.cluster = {
    enable = lib.mkEnableOption "the homeServer cluster";
    containers.debug = lib.mkEnableOption "debugging tools in container images";
    enableIPv4 = lib.mkOption {
      description = "IPv4 support";
      type = lib.types.bool;
      default = true;
    };
    enableIPv6 = lib.mkEnableOption "IPv6 support";
    debugTools = lib.mkOption {
      description = "Tools to embed in all container images when \${config.homeServer.containers.debug} == true";
      type = lib.types.listOf lib.types.package;
      defaultText = "When debug is on: bash, coreutils, netcat, curl, jq, dig, ping, ip, tcpdump";
      default = lib.optionals config.homeServer.cluster.containers.debug [
        pkgs.bash
        pkgs.coreutils
        pkgs.netcat-gnu
        pkgs.curl
        pkgs.jq
        pkgs.dig
        pkgs.unixtools.ping
        pkgs.iproute2
        pkgs.tcpdump
      ];
    };
    podCidr4 = lib.mkOption {
      description = "IPv4 CIDR for the pods";
      type = lib.types.str;
      default = "10.42.0.0/16"; # k3s default: https://docs.k3s.io/cli/server?_highlight=cidr#networking
    };
    podCidr6 = lib.mkOption {
      description = "IPv6 CIDR for the pods";
      type = lib.types.str;
    };
    svcCidr4 = lib.mkOption {
      description = "IPv4 CIDR for the services";
      type = lib.types.str;
      default = "10.43.0.0/16"; # k3s default: https://docs.k3s.io/cli/server?_highlight=cidr#networking
    };
    svcCidr6 = lib.mkOption {
      description = "IPv6 CIDR for the services";
      type = lib.types.str;
    };
    domain = lib.mkOption {
      description = "Domain name of the cluster";
      type = lib.types.str;
      default = config.networking.domain;
      defaultText = builtins.literalExpression "config.networking.domain";
    };
    acmeProvider = lib.mkOption {
      description = "The ACME provider that Ingresses should use for obtaining TLS certs";
      type = lib.types.str;
    };
    dataPath = lib.mkOption {
      description = "Path for services whose data should persist across cluster iterations (hostPath mount)";
      type = lib.types.str;
    };
    defaultUser.uid = lib.mkOption {
      description = "Default user UID for workloads";
      type = lib.types.int;
      default = config.users.users.admin.uid;
      defaultText = "\${config.users.users.admin.uid}";
    };
    defaultUser.gid = lib.mkOption {
      description = "Default group GID for workloads";
      type = lib.types.int;
      default = config.users.groups.admin.gid;
      defaultText = "\${config.users.groups.admin.gid}";
    };
  };
  imports = [
    inputs.kubetree.nixosModules.default
    self.nixosModules.cilium
    self.nixosModules.service-macros
    ./workloads/cert-manager.nix
    ./workloads/cilium.nix
    ./workloads/external-dns.nix
    ./workloads/k8sss.nix
    ./workloads/netutils.nix
    ./workloads/networkpolicies.nix
    ./workloads/secrets-manager.nix
  ];
  config = lib.mkIf ccfg.enable {
    services.k3s.enable = true;
    kubetree = {
      k3s.enable = true;
      cilium.enable = true;
      service-macros = {
        enable = true;
        inherit (ccfg)
          domain
          acmeProvider
          dataPath
          defaultUser
          ;
        utilityImage = "${flakePkgs.container-utils.buildArgs.name}:${flakePkgs.container-utils.imageTag}";
      };
    };

    environment.systemPackages = [
      (pkgs.writeShellScriptBin "k9s" ''KUBECONFIG=/etc/rancher/k3s/k3s.yaml exec ${lib.getExe pkgs.k9s} "$@"'')
      (pkgs.writeShellScriptBin "cilium" ''KUBECONFIG=/etc/rancher/k3s/k3s.yaml exec ${lib.getExe pkgs.cilium-cli} "$@"'')
    ];
    services.restic.backups.default.paths = [
      "${ccfg.dataPath}/k3s/server/token"
      "${ccfg.dataPath}/k3s/server/db"
    ];
    systemd.tmpfiles.settings."50-k3s-data"."/var/lib/rancher/k3s"."L+" = {
      user = "root";
      group = "root";
      mode = "0755";
      argument = "${ccfg.dataPath}/k3s";
    };
    systemd.globalEnvironment.KUBECONFIG = "/etc/rancher/k3s/k3s.yaml";
    networking.tempAddresses = lib.mkIf ccfg.bgp.enable "disabled";
    networking.firewall.enable = !ccfg.firewall.enable;
    # https://github.com/cilium/cilium/issues/31565#issuecomment-3419710315
    networking.firewall.checkReversePath = false;
    networking.firewall.allowedTCPPorts = [ 6443 ];
    systemd.services.k3s.restartTriggers = [
      config.services.k3s.images
      k3sConfig
    ];
    services.k3s = {
      images = [ flakePkgs.container-utils ];
      configPath = k3sConfig;
      disable = [
        "runtimes"
        "local-storage"
      ];
    };
  };
}
