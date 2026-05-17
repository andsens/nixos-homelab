{ self, ... }:
{
  lib,
  pkgs,
  config,
  ...
}:
let
  ccfg = config.homelab.cluster;
  cfg = config.homelab.services.homepage.integrations.prowlarr;
in
{
  options.homelab.services.homepage.integrations.prowlarr = {
    enable = lib.mkOption {
      description = "integration of prowlarr with homepage";
      type = lib.types.bool;
      default = config.homelab.services.prowlarr.enable && config.homelab.services.homepage.enable;
    };
  };
  config = lib.mkIf cfg.enable {
    setup-secrets.destinations = [
      {
        logPrefix = "Homepage (PROWLARR_API_KEY)";
        requires = [ "PROWLARR_API_KEY" ];
        cmd = self.lib.setup-secrets.mkScript pkgs ''setKubeSecret homepage prowlarr-api-key PROWLARR_API_KEY "$PROWLARR_API_KEY"'';
      }
    ];
    homelab.services.homepage = {
      services.Managers.Prowlarr = {
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
      envByName.HOMEPAGE_VAR_PROWLARR_API_KEY.valueFrom.secretKeyRef = {
        name = "prowlarr-api-key";
        key = "PROWLARR_API_KEY";
      };
      allowEgress = [ "prowlarr" ];
    };
  };
}
