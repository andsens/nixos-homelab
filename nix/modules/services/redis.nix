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
    services.restic.backups.default.paths = [
      "${ccfg.dataPath}/redis/dump.rdb"
    ];
    kubetree.resources.redis = {
      config = {
        apiVersion = "v1";
        kind = "ConfigMap";
        metadata.namespace = "redis";
        metadata.name = "config";
        data."redis.conf" = ''
          dir "${ccfg.dataPath}/redis"
        '';
      };
      service-macro = {
        apiVersion = "cluster.local";
        kind = "ServiceMacro";
        metadata.name = "redis";
        spec = {
          podSpec = {
            addDataMount = true;
            mainContainer = {
              image = "redis:8.4";
              args = [ "/etc/redis/redis.conf" ];
              portsByName.redis = 6379;
              livenessProbe.tcpSocket.port = "redis";
              readinessProbe.tcpSocket.port = "redis";
              volumeMountsByPath."/etc/redis" = "config";
            };
            volumesByName."config".configMap.name = "config";
          };
        };
      };
    };
  };
}
