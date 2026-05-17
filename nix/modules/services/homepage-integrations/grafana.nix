{ ... }:
{
  lib,
  config,
  ...
}:
let
  ccfg = config.homelab.cluster;
  cfg = config.homelab.services.homepage.integrations.grafana;
in
{
  options.homelab.services.homepage.integrations.grafana = {
    enable = lib.mkOption {
      description = "integration of grafana with homepage";
      type = lib.types.bool;
      default = config.homelab.services.grafana.enable && config.homelab.services.homepage.enable;
    };
  };
  config = lib.mkIf cfg.enable {
    homelab.services.homepage = {
      allowEgress = [ "grafana" ];
      services.Monitoring.Grafana = {
        icon = "grafana.png";
        description = "Grafana";
        href = "https://grafana.${ccfg.domain}";
        widget = {
          type = "grafana";
          url = "http://grafana.grafana:3000";
          version = 2;
          fields = [
            "totalalerts"
            "alertstriggered"
          ];
          headers = {
            X-WEBAUTH-USER = "admin";
            X-WEBAUTH-ROLE = "Admin";
          };
        };
      };
    };
  };
}
