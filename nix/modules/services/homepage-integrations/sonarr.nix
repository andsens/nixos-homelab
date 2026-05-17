{ self, ... }:
{
  lib,
  pkgs,
  config,
  ...
}:
let
  ccfg = config.homelab.cluster;
  cfg = config.homelab.services.homepage.integrations.sonarr;
in
{
  options.homelab.services.homepage.integrations.sonarr = {
    enable = lib.mkOption {
      description = "integration of sonarr with homepage";
      type = lib.types.bool;
      default = config.homelab.services.sonarr.enable && config.homelab.services.homepage.enable;
    };
  };
  config = lib.mkIf cfg.enable {
    setup-secrets.destinations = [
      {
        logPrefix = "Homepage (SONARR_API_KEY)";
        requires = [ "SONARR_API_KEY" ];
        cmd = self.lib.setup-secrets.mkScript pkgs ''setKubeSecret homepage sonarr-api-key SONARR_API_KEY "$SONARR_API_KEY"'';
      }
    ];
    homelab.services.homepage = {
      services.Managers.Sonarr = {
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
      envByName.HOMEPAGE_VAR_SONARR_API_KEY.valueFrom.secretKeyRef = {
        name = "sonarr-api-key";
        key = "SONARR_API_KEY";
      };
      allowEgress = [ "sonarr" ];
    };
  };
}
