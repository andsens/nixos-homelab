{ ... }:
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
    copyToRoot = [
      pkgs.radarr
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
      useradd -r -u ${toString ccfg.defaultUser.uid} -g admin -G users -d "${ccfg.dataPath}/radarr" radarr
    '';
    config.User = "${toString ccfg.defaultUser.uid}:${toString ccfg.defaultUser.gid}";
    config.Entrypoint = [
      (pkgs.lib.getExe pkgs.radarr)
    ];
  };
in
{
  options.homelab.services.radarr = {
    enable = lib.mkEnableOption "radarr";
    mountPaths = lib.mkOption {
      description = "Paths from the host to mirror into the container";
      type = lib.types.listOf lib.types.path;
      default = [ ];
    };
  };
  config = lib.mkIf cfg.enable {
    homelab.services.homepage.services.Managers.Radarr = {
      sort = 70;
      icon = "radarr.png";
      description = "Movie library manager";
      href = "https://radarr.${ccfg.domain}";
      widget = {
        type = "radarr";
        url = "http://radarr.radarr:7878";
        key = "{{HOMEPAGE_VAR_RADARR_API_KEY}}";
      };
    };
    homelab.cluster.secretsManager.importSecrets.radarr-api-key = {
      extractCommands.RADARR_API_KEY = ''xq -q 'Config>ApiKey' "${ccfg.dataPath}/radarr/config.xml"'';
      destinations = [ "homepage" ];
    };
    homelab.services.homepage.envByName.HOMEPAGE_VAR_RADARR_API_KEY.valueFrom.secretKeyRef = {
      name = "radarr-api-key";
      key = "RADARR_API_KEY";
    };
    homelab.services.homepage.allowEgress = [ "radarr" ];
    services.restic.backups.default.paths = [ "${ccfg.dataPath}/radarr/Backups" ];
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
        podSpec = {
          addDataMount = true;
          mainContainer = {
            image = "${image.buildArgs.name}:${image.imageTag}";
            addCapabilities = [ "CHOWN" ];
            imagePullPolicy = "Never";
            args = [ "-data=${ccfg.dataPath}/radarr" ];
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
            hostMounts =
              (lib.mergeAttrsList (map (path: { "${path}" = { }; }) cfg.mountPaths))
              // (lib.optionalAttrs config.homelab.services.rtorrent.enable {
                "${config.homelab.services.rtorrent.downloadPath}".name = "bt-downloads";
              })
              // (lib.optionalAttrs config.homelab.services.sabnzbd.enable {
                "${config.homelab.services.sabnzbd.downloadPath}".name = "nzb-downloads";
              });
            volumeMountsByPath."/tmp" = "tmp";
          };
          volumesByName.tmp.emptyDir = { };
        };
      };
    };
  };
}
