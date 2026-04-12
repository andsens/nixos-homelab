{
  pkgs,
  lib,
  config,
  ...
}:
let
  ccfg = config.homelab.cluster;
  cfg = config.homelab.services.prowlarr;
  image = pkgs.dockerTools.buildImage {
    name = "cluster.local/prowlarr";
    copyToRoot = [
      pkgs.prowlarr
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
      useradd -r -u ${toString ccfg.defaultUser.uid} -g admin -G users -d "${ccfg.dataPath}/prowlarr" prowlarr
    '';
    config.User = "${toString ccfg.defaultUser.uid}:${toString ccfg.defaultUser.gid}";
    config.Entrypoint = [
      (pkgs.lib.getExe pkgs.prowlarr)
    ];
  };
in
{
  options.homelab.services.prowlarr = {
    enable = lib.mkEnableOption "prowlarr";
  };
  config = lib.mkIf cfg.enable {
    homelab.services.homepage.services.Managers.Prowlarr = {
      sort = 200;
      icon = "prowlarr.png";
      description = "Index scraper";
      href = "https://prowlarr.${ccfg.domain}";
      widget = {
        type = "prowlarr";
        url = "http://prowlarr.prowlarr:9696";
        key = "{{HOMEPAGE_VAR_PROWLARR_API_KEY}}";
      };
    };
    homelab.cluster.secretsManager.importSecrets.prowlarr-api-key = {
      extractCommands.PROWLARR_API_KEY = ''xq -q 'Config>ApiKey' "${ccfg.dataPath}/prowlarr/config.xml"'';
      destinations = [ "homepage" ];
    };
    homelab.services.homepage.envByName.HOMEPAGE_VAR_PROWLARR_API_KEY.valueFrom.secretKeyRef = {
      name = "prowlarr-api-key";
      key = "PROWLARR_API_KEY";
    };
    homelab.services.homepage.allowEgress = [ "prowlarr" ];
    services.restic.backups.default.paths = [ "${ccfg.dataPath}/prowlarr/Backups" ];
    services.k3s.images = [ image ];
    kubetree.resources.prowlarr.content = {
      apiVersion = "cluster.local";
      kind = "ServiceMacro";
      metadata.name = "prowlarr";
      spec = {
        allowEgress = [
          "internet"
          "sonarr"
          "radarr"
          "flood"
          "sabnzbd"
        ];
        ingressPort = 9696;
        podSpec = {
          addDataMount = true;
          mainContainer = {
            image = "${image.buildArgs.name}:${image.imageTag}";
            imagePullPolicy = "Never";
            args = [ "-data=${ccfg.dataPath}/prowlarr" ];
            envByName.PROWLARR__AUTH__ENABLED = "false";
            envByName.PROWLARR__AUTH__METHOD = "External";
            envByName.PROWLARR__APP__LAUNCHBROWSER = "false";
            envByName.PROWLARR__UPDATE__MECHANISM = "external";
            portsByName.web = 9696;
            livenessProbe.httpGet = {
              port = "web";
              path = "/ping";
            };
            readinessProbe.httpGet = {
              port = "web";
              path = "/ping";
            };
            volumeMountsByPath."/tmp" = "tmp";
          };
          volumesByName.tmp.emptyDir = { };
        };
      };
    };
  };
}
