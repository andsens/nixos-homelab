{ self, ... }:
{
  pkgs,
  lib,
  config,
  ...
}:
let
  ccfg = config.homelab.cluster;
  cfg = config.homelab.services.radarr;
  image = pkgs.dockerTools.buildImage {
    name = "cluster.local/radarr";
    copyToRoot =
      with pkgs;
      [
        radarr
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
      groupadd -r -g ${toString config.kubetree.service-macros.securityContext.runAsUser} radarr
      useradd -r -u ${toString config.kubetree.service-macros.securityContext.runAsGroup} -g radarr -d /data radarr
    '';
    config.Entrypoint = [ (pkgs.lib.getExe pkgs.radarr) ];
  };
in
{
  options.homelab.services.radarr = {
    enable = lib.mkEnableOption "radarr";
    debug = lib.mkEnableOption "debug mode";
    volumes = lib.mkOption {
      description = "Volumes to mount into the container expressed as a map of mountpath to volume source (as specificed on the pod spec). rtorrent & usenet download volumes are added automatically.";
      type = lib.types.attrsOf lib.types.anything;
      default = { };
    };
  };
  config = lib.mkIf cfg.enable {
    setup-secrets.sources.RADARR_API_KEY = {
      description = "Radarr API Key";
      cmd = self.lib.setup-secrets.mkScript pkgs ''kubectl exec -n radarr -c radarr deploy/radarr -- xq -q 'Config>ApiKey' "/data/config.xml"'';
    };
    homelab.cluster.backup.volumes.radarr.radarr = [ "/Backups" ];
    services.k3s.images = [ image ];
    kubetree.resources.radarr.content = {
      apiVersion = "cluster.local";
      kind = "ServiceMacro";
      metadata.name = "radarr";
      spec = {
        allowEgress = [
          "internet"
          "plex"
          "prowlarr"
          "flood"
          "sabnzbd"
        ];
        ingressPort = 7878;
        dataPath = "/data";
        servicePodSpec = {
          mainContainer = {
            image = "${image.buildArgs.name}:${image.imageTag}";
            imagePullPolicy = "Never";
            args = [ "-data=/data" ];
            workingDir = "/data";
            # securityContext.supplementalGroups = [ 100 ];
            addCapabilities = [ "CHOWN" ];
            envByName.RADARR__AUTH__ENABLED = "false";
            envByName.RADARR__AUTH__METHOD = "External";
            envByName.RADARR__APP__LAUNCHBROWSER = "false";
            envByName.RADARR__UPDATE__MECHANISM = "external";
            portsByName.web = 7878;
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
