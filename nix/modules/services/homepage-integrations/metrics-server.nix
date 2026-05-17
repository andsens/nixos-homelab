{ ... }:
{
  lib,
  config,
  ...
}:
let
  cfg = config.homelab.services.homepage.integrations.metrics-server;
in
{
  options.homelab.services.homepage.integrations.metrics-server = {
    enable = lib.mkOption {
      description = "integration of metrics-server with homepage";
      type = lib.types.bool;
      default = config.homelab.services.metrics-server.enable && config.homelab.services.homepage.enable;
    };
  };
  config = lib.mkIf cfg.enable {
    homelab.services.homepage = {
      widgets.resources = {
        sort = lib.mkDefault 100;
        backend = "resources";
        expanded = true;
        cpu = true;
        memory = true;
        network = "default";
      };
      allowEgress = [ "metrics-server" ];
    };
  };
}
