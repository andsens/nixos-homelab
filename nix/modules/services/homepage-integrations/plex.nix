{ self, ... }:
{
  lib,
  pkgs,
  config,
  ...
}:
let
  ccfg = config.homelab.cluster;
  cfg = config.homelab.services.homepage.integrations.plex;
in
{
  options.homelab.services.homepage.integrations.plex = {
    enable = lib.mkOption {
      description = "integration of plex with homepage";
      type = lib.types.bool;
      default = config.homelab.services.plex.enable && config.homelab.services.homepage.enable;
    };
  };
  config = lib.mkIf cfg.enable {
    setup-secrets.destinations = [
      {
        logPrefix = "Homepage (PLEX_API_KEY)";
        requires = [ "PLEX_API_KEY" ];
        cmd = self.lib.setup-secrets.mkScript pkgs ''setKubeSecret homepage plex-api-key PLEX_API_KEY "$PLEX_API_KEY"'';
      }
    ];
    homelab.services.homepage = {
      services.Media.Plex = {
        icon = "plex.png";
        description = "Media center";
        href = "https://plex.${ccfg.domain}";
        widget = {
          type = "plex";
          url = "http://plex.plex:32400";
          fields = [
            "streams"
            "movies"
            "tv"
          ];
          key = "{{HOMEPAGE_VAR_PLEX_API_KEY}}";
        };
      };
      envByName.HOMEPAGE_VAR_PLEX_API_KEY.valueFrom.secretKeyRef = {
        name = "plex-api-key";
        key = "PLEX_API_KEY";
      };
      allowEgress = [ "plex" ];
    };
  };
}
