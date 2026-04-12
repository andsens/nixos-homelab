{ self, ... }:
{
  pkgs,
  lib,
  config,
  ...
}:
let
  ccfg = config.homelab.cluster;
  cfg = config.homelab.services.sabnzbd;
  flakePkgs = self.packages.${pkgs.stdenv.hostPlatform.system};
  image = pkgs.dockerTools.buildImage {
    name = "cluster.local/sabnzbd";
    copyToRoot = [
      pkgs.sabnzbd
      pkgs.cacert
    ]
    ++ ccfg.debugTools;
    config.Env = [
      "CURL_CA_BUNDLE=/etc/ssl/certs/ca-bundle.crt"
      "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
    ];
    runAsRoot = ''
      #!${pkgs.runtimeShell}
      ${pkgs.dockerTools.shadowSetup}
      groupadd -r -g 100 users
      groupadd -r -g ${toString ccfg.defaultUser.gid} admin
      useradd -r -u ${toString ccfg.defaultUser.uid} -g admin -G users -d "${ccfg.dataPath}/sabnzbd" sabnzbd
    '';
    config.User = "${toString ccfg.defaultUser.uid}:${toString ccfg.defaultUser.gid}";
    config.Entrypoint = [
      (pkgs.lib.getExe pkgs.sabnzbd)
    ];
  };
in
{
  options.homelab.services.sabnzbd = {
    enable = lib.mkEnableOption "sabnzbd";
    downloadPath = lib.mkOption {
      description = "Download directory";
      type = lib.types.path;
    };
    mountPaths = lib.mkOption {
      description = "Paths from the host to mirror into the container";
      type = lib.types.listOf lib.types.path;
      default = [ ];
    };
  };
  config = lib.mkIf cfg.enable {
    homelab.services.homepage.services.Download.SABnzbd = {
      sort = 50;
      icon = "sabnzbd.png";
      description = "The automated Usenet download tool ";
      href = "https://sabnzbd.${ccfg.domain}";
      widget = {
        type = "sabnzbd";
        url = "http://sabnzbd.sabnzbd:8080";
        key = "{{HOMEPAGE_VAR_SABNZBD_API_KEY}}";
      };
    };
    homelab.cluster.secretsManager.importSecrets.sabnzbd-api-key = {
      extractCommands.SABNZBD_API_KEY = ''grep '^api_key = ' "${ccfg.dataPath}/sabnzbd/sabnzbd.ini" | cut -d ' ' -f3'';
      destinations = [ "homepage" ];
    };
    homelab.services.homepage.envByName.HOMEPAGE_VAR_SABNZBD_API_KEY.valueFrom.secretKeyRef = {
      name = "sabnzbd-api-key";
      key = "SABNZBD_API_KEY";
    };
    homelab.services.homepage.allowEgress = [ "sabnzbd" ];
    services.restic.backups.default.paths = [ "${ccfg.dataPath}/sabnzbd/backups" ];
    services.k3s.images = [ image ];
    kubetree.resources.sabnzbd = {
      deployment = {
        apiVersion = "cluster.local";
        kind = "ServiceDeployment";
        metadata.name = "sabnzbd";
        spec = {
          allowIngress = [ "gateway" ];
          allowEgress = [ "internet" ];
          template.metadata.labels = lib.optionalAttrs (config.homelab.privacyVPN.enable) {
            "cluster.local/egress-gateway" = "privacy-vpn";
          };
          template.servicePodSpec = {
            name = "sabnzbd";
            addDataMount = true;
            initContainersByName.setup-config = {
              image = "${flakePkgs.container-utils.buildArgs.name}:${flakePkgs.container-utils.imageTag}";
              imagePullPolicy = "Never";
              args = [
                ''
                  [[ -f "${ccfg.dataPath}/sabnzbd/sabnzbd.ini" ]] || cat >"${ccfg.dataPath}/sabnzbd/sabnzbd.ini" <<'EOF'
                  [misc]
                  host = 0.0.0.0
                  port = 8080
                  host_whitelist = sabnzbd.${ccfg.domain},sabnzbd.sabnzbd,
                  download_dir = ${cfg.downloadPath}/incomplete
                  complete_dir = ${cfg.downloadPath}/complete
                  schedlines = "1 0 21 7 create_backup ",
                  backup_dir = "${ccfg.dataPath}/sabnzbd/backups"
                  EOF
                ''
              ];
              securityContext.readOnlyRootFilesystem = true;
              volumeMountsByPath."${ccfg.dataPath}/sabnzbd" = "data";
            };
            mainContainer = {
              image = "${image.buildArgs.name}:${image.imageTag}";
              imagePullPolicy = "Never";
              args = [
                "--disable-file-log"
                "--console"
                "--config-file"
                "${ccfg.dataPath}/sabnzbd/sabnzbd.ini"
              ];
              portsByName.web = 8080;
              livenessProbe.httpGet.port = "web";
              readinessProbe.httpGet.port = "web";
              hostMounts."${cfg.downloadPath}" = {
                name = "nzb-downloads";
                hostPath.type = "DirectoryOrCreate";
              };
              volumeMountsByPath."/tmp" = "tmp";
            };
            volumesByName.tmp.emptyDir = { };
          };
        };
      };
      service = {
        apiVersion = "cluster.local";
        kind = "ServiceService";
        metadata.name = "sabnzbd";
        spec.portsByName.web = 8080;
      };
      gateway = {
        apiVersion = "cluster.local";
        kind = "ServiceGateway";
        metadata.name = "sabnzbd";
        spec.port = 8080;
      };
      netpols = {
        apiVersion = "cluster.local";
        kind = "ServiceNetpols";
        metadata.name = "sabnzbd";
        spec.toPortsFlattened = [ 8080 ];
      };
    };
  };
}
