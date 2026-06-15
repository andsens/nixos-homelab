{ self, ... }:
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
    copyToRoot =
      with pkgs;
      [
        prowlarr
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
      groupadd -r -g ${toString config.kubetree.service-macros.securityContext.runAsUser} prowlarr
      useradd -r -u ${toString config.kubetree.service-macros.securityContext.runAsGroup} -g prowlarr -d /data prowlarr
    '';
    config.Entrypoint = [ (pkgs.lib.getExe pkgs.prowlarr) ];
  };
in
{
  options.homelab.services.prowlarr = {
    enable = lib.mkEnableOption "prowlarr";
    debug = lib.mkEnableOption "debug mode";
  };
  config = lib.mkIf cfg.enable {
    setup-secrets.sources.PROWLARR_API_KEY = {
      description = "Prowlarr API Key";
      cmd = self.lib.setup-secrets.mkScript pkgs ''kubectl exec -n prowlarr -c prowlarr deploy/prowlarr -- xq -q 'Config>ApiKey' "/data/config.xml"'';
    };
    homelab.cluster.backup.volumes.prowlarr.prowlarr = [ "/Backups" ];
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
        dataPath = "/data";
        servicePodSpec = {
          mainContainer = {
            image = "${image.buildArgs.name}:${image.imageTag}";
            imagePullPolicy = "Never";
            args = [ "-data=/data" ];
            workingDir = "/data";
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
