{ self, inputs, ... }:
{
  lib,
  pkgs,
  config,
  ...
}:
let
  ccfg = config.homelab.cluster;
  flakePkgs = self.packages.${pkgs.stdenv.hostPlatform.system};
  ipv4 = self.lib.ip.v4;
  kubelib = inputs.kube-generators.lib { inherit pkgs; };
  k3sConfig = kubelib.toYAMLFile ({
    data-dir = ccfg.dataDir;
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
  # https://github.com/hercules-ci/flake-parts/pull/251
  key = "${toString __curPos.file}#modules.nixos.cluster";
  options.homelab.cluster = {
    enable = lib.mkEnableOption "the homelab cluster";
    containers.debug = lib.mkEnableOption "debugging tools in container images";
    enableIPv4 = lib.mkOption {
      description = "IPv4 support";
      type = lib.types.bool;
      default = true;
    };
    enableIPv6 = lib.mkEnableOption "IPv6 support";
    debugTools = lib.mkOption {
      description = "Tools to embed in all container images when \${config.homelab.containers.debug} == true";
      type = lib.types.listOf lib.types.package;
      defaultText = "When debug is on: bash, coreutils, netcat, curl, jq, dig, ping, ip, tcpdump";
      default = lib.optionals config.homelab.cluster.containers.debug [
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
    dataDir = lib.mkOption {
      description = "Path for services whose data should persist across cluster iterations (hostPath mount)";
      type = lib.types.str;
    };
    backup.hostPaths = lib.mkOption {
      description = "List of paths on the host that *should* be backed up, this option does not configure a backup, it is only meant for aggregation";
      type = lib.types.listOf lib.types.str;
      default = [ ];
    };
    backup.volumes = lib.mkOption {
      description = "A map of namespace -> PV claim name -> paths that *should* be backed up, this option does not configure a backup, it is only meant for aggregation";
      type = lib.types.attrsOf (lib.types.attrsOf (lib.types.listOf lib.types.str));
      default = { };
    };
  };
  imports = [
    inputs.kubetree.nixosModules.default
    self.nixosModules.kubetree-cilium
    self.nixosModules.kubetree-service-macros
  ];
  config = lib.mkIf ccfg.enable {
    systemd.services."setup-secrets".after = [ "k3s.service" ];
    services.k3s.enable = true;
    kubetree = {
      k3s.enable = true;
      cilium.enable = true;
      service-macros = {
        enable = true;
        domain = ccfg.domain;
      };
    };

    environment.systemPackages = [
      (pkgs.writeShellScriptBin "k9s" ''KUBECONFIG=/etc/rancher/k3s/k3s.yaml exec ${lib.getExe pkgs.k9s} "$@"'')
      (pkgs.writeShellScriptBin "cilium" ''KUBECONFIG=/etc/rancher/k3s/k3s.yaml exec ${lib.getExe pkgs.cilium-cli} "$@"'')
    ];
    homelab.cluster.backup.hostPaths = [
      "${ccfg.dataDir}/server/token"
      "${ccfg.dataDir}/server/db"
    ];
    systemd.tmpfiles.settings."50-k3s-data"."/var/lib/rancher/k3s"."L+" = {
      user = "root";
      group = "root";
      mode = "0755";
      argument = ccfg.dataDir;
    };
    systemd.globalEnvironment.KUBECONFIG = "/etc/rancher/k3s/k3s.yaml";
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
