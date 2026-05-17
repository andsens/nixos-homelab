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
      pkgs.coreutils
      pkgs.gnugrep
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
      groupadd -r -g 900 sabnzbd
      useradd -r -u 900 -g sabnzbd -G users -d "/data" sabnzbd
    '';
    config.User = "900:900";
    config.Entrypoint = [
      (pkgs.lib.getExe pkgs.sabnzbd)
    ];
  };
in
{
  options.homelab.services.sabnzbd = {
    enable = lib.mkEnableOption "sabnzbd";
    downloadsVolume = lib.mkOption {
      description = "Volume source (as specificed on the pod spec) to place downloads in";
      type = lib.types.attrsOf lib.types.anything;
    };
  };
  config = lib.mkIf cfg.enable {
    setup-secrets.sources.SABNZBD_API_KEY = {
      description = "SABnzbd API Key";
      cmd = self.lib.setup-secrets.mkScript pkgs ''
        kubectl exec -n sabnzbd -c sabnzbd deploy/sabnzbd -- ${lib.getExe pkgs.gnugrep} '^api_key = ' "/data/sabnzbd.ini" | \
          cut -d ' ' -f3
      '';
    };
    # services.restic.backups.default.paths = [ "/data/backups" ];
    services.k3s.images = [ image ];
    kubetree.resources.sabnzbd = {
      data = {
        apiVersion = "v1";
        kind = "PersistentVolumeClaim";
        metadata.namespace = "sabnzbd";
        metadata.name = "sabnzbd";
        spec = {
          accessModes = [ "ReadWriteOnce" ];
          resources.requests.storage = "1Gi";
          volumeMode = "Filesystem";
        };
      };
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
            initContainersByName.setup-config = {
              image = "${flakePkgs.container-utils.buildArgs.name}:${flakePkgs.container-utils.imageTag}";
              imagePullPolicy = "Never";
              args = [
                ''
                  [[ -f "/data/sabnzbd.ini" ]] || cat >"/data/sabnzbd.ini" <<'EOF'
                  [misc]
                  host = 0.0.0.0
                  port = 8080
                  host_whitelist = sabnzbd.${ccfg.domain},sabnzbd.sabnzbd,
                  download_dir = /usenet/incomplete
                  complete_dir = /usenet/complete
                  schedlines = "1 0 21 7 create_backup ",
                  backup_dir = "/data/backups"
                  EOF
                ''
              ];
              securityContext.readOnlyRootFilesystem = true;
              volumeMountsByPath."/data" = "data";
            };
            mainContainer = {
              image = "${image.buildArgs.name}:${image.imageTag}";
              imagePullPolicy = "Never";
              args = [
                "--disable-file-log"
                "--console"
                "--config-file"
                "/data/sabnzbd.ini"
              ];
              portsByName.web = 8080;
              livenessProbe.httpGet.port = "web";
              readinessProbe.httpGet.port = "web";
              volumeMountsByPath = {
                "/data" = "data";
                "/usenet" = "downloads";
                "/tmp" = "tmp";
              };
            };
            volumesByName = {
              data.persistentVolumeClaim.claimName = "sabnzbd";
              downloads = cfg.downloadsVolume;
              tmp.emptyDir = { };
            };
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
