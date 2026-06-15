{ self, ... }:
{
  pkgs,
  lib,
  config,
  ...
}:
let
  ccfg = config.homelab.cluster;
  cfg = config.homelab.services.sonarr;
  image = pkgs.dockerTools.buildImage {
    name = "cluster.local/sonarr";
    copyToRoot =
      with pkgs;
      [
        sonarr
        cacert
        xq-xml # for extracting the API token
      ]
      ++ lib.optionals cfg.debug ccfg.debugTools;
    config.Env = [
      "CURL_CA_BUNDLE=/etc/ssl/certs/ca-bundle.crt"
      "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
    ];
    runAsRoot = ''
      #!${pkgs.runtimeShell}
      ${pkgs.dockerTools.shadowSetup}
      groupadd -r -g ${toString config.kubetree.service-macros.securityContext.runAsUser} sonarr
      useradd -r -u ${toString config.kubetree.service-macros.securityContext.runAsGroup} -g sonarr -d /data sonarr
    '';
    config.Entrypoint = [ (pkgs.lib.getExe pkgs.sonarr) ];
  };
in
{
  options.homelab.services.sonarr = {
    enable = lib.mkEnableOption "sonarr";
    debug = lib.mkEnableOption "debug mode";
    mountPaths = lib.mkOption {
      description = "Paths from the host to mirror into the container";
      type = lib.types.listOf lib.types.path;
      default = [ ];
    };
    volumes = lib.mkOption {
      description = "Volumes to mount into the container expressed as a map of mountpath to volume source (as specificed on the pod spec). rtorrent & usenet download volumes are added automatically.";
      type = lib.types.attrsOf lib.types.anything;
      default = { };
    };
  };
  config = lib.mkIf cfg.enable {
    setup-secrets.sources.SONARR_API_KEY = {
      description = "Sonarr API Key";
      cmd = self.lib.setup-secrets.mkScript pkgs ''kubectl exec -n sonarr -c sonarr deploy/sonarr -- xq -q 'Config>ApiKey' "/data/config.xml"'';
    };
    homelab.cluster.backup.volumes.sonarr.sonarr = [ "/Backups" ];
    services.k3s.images = [ image ];
    kubetree.resources.sonarr.content = {
      apiVersion = "cluster.local";
      kind = "ServiceMacro";
      metadata.name = "sonarr";
      spec = {
        allowEgress = [
          "internet"
          "plex"
          "prowlarr"
          "flood"
          "sabnzbd"
        ];
        ingressPort = 8989;
        dataPath = "/data";
        servicePodSpec = {
          mainContainer = {
            image = "${image.buildArgs.name}:${image.imageTag}";
            imagePullPolicy = "Never";
            args = [ "-data=/data" ];
            workingDir = "/data";
            addCapabilities = [ "CHOWN" ];
            envByName.SONARR__AUTH__ENABLED = "false";
            envByName.SONARR__AUTH__METHOD = "External";
            envByName.SONARR__APP__LAUNCHBROWSER = "false";
            envByName.SONARR__UPDATE__MECHANISM = "external";
            portsByName.web = 8989;
            livenessProbe.httpGet = {
              port = "web";
              path = "/ping";
            };
            readinessProbe.httpGet = {
              port = "web";
              path = "/ping";
            };
            volumeMountsByPath = {
              "/tmp" = "tmp";
            }
            // lib.mapAttrs' (key: value: lib.nameValuePair key (self.lib.k8s.pathToMountName key)) cfg.volumes
            // lib.optionalAttrs config.homelab.services.rtorrent.enable {
              "/torrents" = "torrents";
            }
            // lib.optionalAttrs config.homelab.services.sabnzbd.enable {
              "/usenet" = "usenet";
            };
          };
          volumesByName = {
            tmp.emptyDir = { };
          }
          // lib.mapAttrs' (
            key: value: lib.nameValuePair (self.lib.k8s.pathToMountName key) value
          ) cfg.volumes
          // lib.optionalAttrs config.homelab.services.rtorrent.enable {
            torrents = config.homelab.services.rtorrent.downloadsVolume;
          }
          // lib.optionalAttrs config.homelab.services.sabnzbd.enable {
            usenet = config.homelab.services.sabnzbd.downloadsVolume;
          };
        };
      };
    };
  };
}
