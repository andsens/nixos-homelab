{ ... }:
{
  lib,
  config,
  ...
}:
let
  cfg = config.homelab.services.mimir;
in
{
  options.homelab.services.mimir = {
    enable = lib.mkEnableOption "Mimir";
    retention = lib.mkOption {
      description = "How long metrics should be kept";
      type = lib.types.str;
      default = "1y";
      example = "30d";
    };
  };
  config = lib.mkIf cfg.enable {
    homelab.services.alloy.allowEgress = [ "mimir" ];
    kubetree.resources.mimir = {
      config = {
        apiVersion = "v1";
        kind = "ConfigMap";
        metadata.namespace = "mimir";
        metadata.name = "config";
        data."mimir.yaml" = builtins.toJSON {
          multitenancy_enabled = false;
          target = lib.concatStringsSep "," [
            "distributor"
            "ingester"
            "querier"
            "query-frontend"
            "query-scheduler"
            "store-gateway"
            "compactor"
          ];
          usage_stats.enabled = false;
          activity_tracker.filepath = "/data/metrics-activity.log";
          limits.compactor_blocks_retention_period = cfg.retention;
          distributor = {
            ring.kvstore.store = "inmemory";
            pool.health_check_ingesters = true;
          };
          ingester.ring = {
            min_ready_duration = "0s";
            final_sleep = "0s";
            num_tokens = 512;
            kvstore.store = "inmemory";
            replication_factor = 1;
          };
          blocks_storage = {
            tsdb.dir = "/data/tsdb";
            bucket_store.sync_dir = "/data/tsdb-sync";
            filesystem.dir = "/data/blocks";
          };
          compactor.data_dir = "/data/compactor";
          ruler.rule_path = "/data/data-ruler";
          ruler_storage = {
            backend = "local";
            local.directory = "/data/rules";
          };
        };
      };
      service-macro = {
        apiVersion = "cluster.local";
        kind = "ServiceMacro";
        metadata.name = "mimir";
        spec = {
          ingressPort = 8080;
          dataPath = "/data";
          servicePodSpec.mainContainer = {
            image = "grafana/mimir:3.0.0";
            args = [ "-config.file=/etc/mimir/mimir.yaml" ];
            portsByName.web = 8080;
            volumeMountsByPath."/etc/mimir" = {
              name = "config";
              readOnly = true;
            };
            startupProbe = {
              httpGet.path = "/ready";
              httpGet.port = "web";
              failureThreshold = 120;
            };
            livenessProbe = {
              httpGet.path = "/ready";
              httpGet.port = "web";
            };
            readinessProbe = {
              httpGet.path = "/ready";
              httpGet.port = "web";
            };
          };
          servicePodSpec.volumesByName.config.configMap.name = "config";
        };
      };
    };
  };
}
