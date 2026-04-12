{ ... }:
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
    copyToRoot = [
      pkgs.sonarr
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
      useradd -r -u ${toString ccfg.defaultUser.uid} -g admin -G users -d "${ccfg.dataPath}/sonarr" sonarr
    '';
    config.User = "${toString ccfg.defaultUser.uid}:${toString ccfg.defaultUser.gid}";
    config.Entrypoint = [
      (pkgs.lib.getExe pkgs.sonarr)
    ];
  };
in
{
  options.homelab.services.sonarr = {
    enable = lib.mkEnableOption "sonarr";
    mountPaths = lib.mkOption {
      description = "Paths from the host to mirror into the container";
      type = lib.types.listOf lib.types.path;
      default = [ ];
    };
  };
  config = lib.mkIf cfg.enable {
    homelab.services.homepage.services.Managers.Sonarr = {
      sort = 50;
      icon = "sonarr.png";
      description = "TV Show library manager";
      href = "https://sonarr.${ccfg.domain}";
      widget = {
        type = "sonarr";
        url = "http://sonarr.sonarr:8989";
        key = "{{HOMEPAGE_VAR_SONARR_API_KEY}}";
      };
    };
    homelab.cluster.secretsManager.importSecrets.sonarr-api-key = {
      extractCommands.SONARR_API_KEY = ''xq -q 'Config>ApiKey' "${ccfg.dataPath}/sonarr/config.xml"'';
      destinations = [ "homepage" ];
    };
    homelab.services.homepage.envByName.HOMEPAGE_VAR_SONARR_API_KEY.valueFrom.secretKeyRef = {
      name = "sonarr-api-key";
      key = "SONARR_API_KEY";
    };
    homelab.services.homepage.allowEgress = [ "sonarr" ];
    services.restic.backups.default.paths = [ "${ccfg.dataPath}/sonarr/Backups" ];
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
        podSpec = {
          addDataMount = true;
          mainContainer = {
            image = "${image.buildArgs.name}:${image.imageTag}";
            imagePullPolicy = "Never";
            args = [ "-data=${ccfg.dataPath}/sonarr" ];
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
