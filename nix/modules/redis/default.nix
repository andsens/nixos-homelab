{ ... }:
{
  lib,
  config,
  ...
}:
let
  cfg = config.homelab.services.redis;
in
{
  key = "${toString __curPos.file}#modules.nixos.redis";
  options.homelab.services.redis = {
    enable = lib.mkEnableOption "Redis";
    databases = lib.mkOption {
      description = "A map of symbolic names to redis db indices. Overlaps will cause an assertion failure.";
      type = lib.types.attrsOf lib.types.str;
    };
  };
  config = lib.mkIf cfg.enable {
    assertions = with builtins; [
      (
        let
          overlaps = lib.filterAttrs (idx: names: length names > 1) (
            lib.zipAttrs (lib.mapAttrsToList (name: value: { ${value} = name; }) cfg.databases)
          );
        in
        {
          assertion = length (attrNames overlaps) == 0;
          message = ''
            homelab.services.redis.databases has overlaps in db indices.
            ${lib.join "\n" (
              lib.mapAttrsToList (idx: names: "The index ${idx} is used by: ${lib.join ", " names}") overlaps
            )}
          '';
        }
      )
      (
        let
          nonInts = lib.filterAttrs (name: idx: toString (lib.toIntBase10 idx) != idx) cfg.databases;
        in
        {
          assertion = length (attrNames nonInts) == 0;
          message = ''
            homelab.services.redis.databases contains non-integer strings as db indices.
            ${lib.join "\n" (
              lib.mapAttrsToList (name: idx: ''The index "${idx}" used by "${name}" is not valid.'') nonInts
            )}
          '';
        }
      )
    ];
    homelab.cluster.backup.volumes.redis.redis = [ "/dump.rdb" ];
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
