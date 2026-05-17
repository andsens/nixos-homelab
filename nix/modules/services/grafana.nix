{ ... }:
{
  lib,
  config,
  ...
}:
let
  cfg = config.homelab.services.grafana;
in
{
  options.homelab.services.grafana = {
    enable = lib.mkEnableOption "grafana";
    image = lib.mkOption {
      description = "Repo url of the Grafana image to run";
      type = lib.types.str;
      default = "grafana/grafana:12.2.1";
    };
  };
  config = lib.mkIf cfg.enable {
    homelab.services.postgresql.databases.grafana.backup.enable = true;
    kubetree.resources.grafana = {
      config = {
        apiVersion = "v1";
        kind = "ConfigMap";
        metadata.namespace = "grafana";
        metadata.name = "config";
        data."grafana.ini" = builtins.readFile ./grafana.ini;
        data."datasources.yaml" = builtins.toJSON {
          apiVersion = 1;
          datasources = lib.optional config.homelab.services.mimir.enable {
            name = "Mimir";
            uid = "mimir";
            type = "prometheus";
            isDefault = false;
            access = "proxy";
            typeLogoUrl = "/public/app/plugins/datasource/prometheus/img/mimir_logo.svg";
            url = "http://mimir.mimir:8080/prometheus";
            jsonData = {
              httpMethod = "POST";
              prometheusType = "Mimir";
              prometheusVersion = "2.16.0";
              queryTimeout = "120s";
              timeInterval = "30s";
            };
          };
          deleteDatasources = lib.optional (!config.homelab.services.mimir.enable) "mimir";
        };
      };
      service-macro = {
        apiVersion = "cluster.local";
        kind = "ServiceMacro";
        metadata.name = "grafana";
        spec = {
          allowEgress = [
            "internet"
            "mimir"
            "postgresql"
          ];
          allowIngress = [ "gateway" ];
          dataPath = "/var/lib/grafana";
          servicePodSpec = {
            mainContainer = {
              image = cfg.image;
              portsByName.web = 3000;
              livenessProbe.httpGet.port = "web";
              readinessProbe.httpGet.port = "web";
              volumeMountsByPath = {
                "/var/lib/grafana" = "data";
                "/etc/grafana/grafana.ini" = {
                  name = "config";
                  subPath = "grafana.ini";
                  readOnly = true;
                };
                "/etc/grafana/provisioning/datasources/all.yaml" = {
                  name = "config";
                  subPath = "datasources.yaml";
                  readOnly = true;
                };
                "/tmp" = "tmp";
              };
            };
            volumesByName = {
              config.configMap.name = "config";
              tmp.emptyDir = { };
            };
          };
        };
      };
      gateway = {
        apiVersion = "cluster.local";
        kind = "ServiceGateway";
        metadata.name = "grafana";
        spec.port = 3000;
        spec.requestHeaderModifier.add = [
          {
            name = "X-WEBAUTH-USER";
            value = "admin";
          }
          {
            name = "X-WEBAUTH-ROLE";
            value = "Admin";
          }
        ];
      };
    };
  };
}
