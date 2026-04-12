{
  lib,
  config,
  ...
}:
let
  ccfg = config.homeServer.cluster;
  cfg = config.homeServer.services.mimir;
in
{
  options.homeServer.services.mimir = {
    enable = lib.mkEnableOption "Mimir";
    retention = lib.mkOption {
      description = "How long metrics should be kept";
      type = lib.types.str;
      default = "1y";
      example = "30d";
    };
  };
  config = lib.mkIf cfg.enable {
    homeServer.services.alloy.allowEgress = [ "mimir" ];
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
          activity_tracker.filepath = "${ccfg.dataPath}/mimir/metrics-activity.log";
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
            tsdb.dir = "${ccfg.dataPath}/mimir/tsdb";
            bucket_store.sync_dir = "${ccfg.dataPath}/mimir/tsdb-sync";
            filesystem.dir = "${ccfg.dataPath}/mimir/blocks";
          };
          compactor.data_dir = "${ccfg.dataPath}/mimir/compactor";
          ruler.rule_path = "${ccfg.dataPath}/mimir/data-ruler";
          ruler_storage = {
            backend = "local";
            local.directory = "${ccfg.dataPath}/mimir/rules";
          };
        };
      };
      service-macro = {
        apiVersion = "cluster.local";
        kind = "ServiceMacro";
        metadata.name = "mimir";
        spec = {
          ingressPort = 8080;
          podSpec.addDataMount = true;
          podSpec.mainContainer = {
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
          podSpec.volumesByName.config.configMap.name = "config";
        };
      };
    };
  };
}
