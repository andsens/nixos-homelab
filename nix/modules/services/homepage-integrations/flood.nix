{ ... }:
{
  lib,
  config,
  ...
}:
let
  ccfg = config.homelab.cluster;
  cfg = config.homelab.services.homepage.integrations.flood;
in
{
  options.homelab.services.homepage.integrations.flood = {
    enable = lib.mkOption {
      description = "integration of flood with homepage";
      type = lib.types.bool;
      default = config.homelab.services.flood.enable && config.homelab.services.homepage.enable;
    };
  };
  config = lib.mkIf cfg.enable {
    homelab.services.homepage = {
      services.Download.Flood = {
        icon = "flood.png";
        description = "rTorrent WebUI";
        href = "https://flood.${ccfg.domain}";
        widget = {
          type = "flood";
          url = "http://flood.flood:3000";
        };
      };
      allowEgress = [ "flood" ];
    };
  };
}
