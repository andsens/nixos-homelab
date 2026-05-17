{ self, ... }:
{
  lib,
  pkgs,
  config,
  ...
}:
let
  ccfg = config.homelab.cluster;
  cfg = config.homelab.services.homepage.integrations.radarr;
in
{
  options.homelab.services.homepage.integrations.radarr = {
    enable = lib.mkOption {
      description = "integration of radarr with homepage";
      type = lib.types.bool;
      default = config.homelab.services.radarr.enable && config.homelab.services.homepage.enable;
    };
  };
  config = lib.mkIf cfg.enable {
    setup-secrets.destinations = [
      {
        logPrefix = "Homepage (RADARR_API_KEY)";
        requires = [ "RADARR_API_KEY" ];
        cmd = self.lib.setup-secrets.mkScript pkgs ''setKubeSecret homepage radarr-api-key RADARR_API_KEY "$RADARR_API_KEY"'';
      }
    ];
    homelab.services.homepage = {
      services.Managers.Radarr = {
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
      envByName.HOMEPAGE_VAR_RADARR_API_KEY.valueFrom.secretKeyRef = {
        name = "radarr-api-key";
        key = "RADARR_API_KEY";
      };
      allowEgress = [ "radarr" ];
    };
  };
}
