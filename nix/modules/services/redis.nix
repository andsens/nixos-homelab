{ ... }:
{
  lib,
  config,
  ...
}:
let
  ccfg = config.homelab.cluster;
  cfg = config.homelab.services.redis;
in
{
  options.homelab.services.redis = {
    enable = lib.mkEnableOption "Redis";
  };
  config = lib.mkIf cfg.enable {
    # services.restic.backups.default.paths = [
    #   "${ccfg.dataPath}/redis/dump.rdb"
    # ];
    kubetree.resources.redis = {
      service-macro = {
        apiVersion = "cluster.local";
        kind = "ServiceMacro";
        metadata.name = "redis";
        spec = {
          dataPath = "/data";
          servicePodSpec = {
            mainContainer = {
              image = "redis:8.4";
              portsByName.redis = 6379;
              livenessProbe.tcpSocket.port = "redis";
              readinessProbe.tcpSocket.port = "redis";
            };
          };
        };
      };
    };
  };
}
