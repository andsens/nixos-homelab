{
  lib,
  config,
  ...
}:
let
  ccfg = config.homeServer.cluster;
  cfg = config.homeServer.services.grafana;
in
{
  options.homeServer.services.grafana = {
    enable = lib.mkEnableOption "grafana";
    image = lib.mkOption {
      description = "Repo url of the Grafana image to run";
      type = lib.types.str;
      default = "grafana/grafana:12.2.1";
    };
  };
  config = lib.mkIf cfg.enable {
    homeServer.services = {
      postgresql.databases.grafana.backup.enable = true;
      homepage.allowEgress = [ "grafana" ];
      homepage.services.Monitoring.Grafana = {
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
    kubetree.resources.grafana = {
      config = {
        apiVersion = "v1";
        kind = "ConfigMap";
        metadata.namespace = "grafana";
        metadata.name = "config";
        data."grafana.ini" = builtins.readFile ./grafana.ini;
        data."datasources.yaml" = builtins.toJSON {
          apiVersion = 1;
          datasources = lib.optional config.homeServer.services.mimir.enable {
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
          deleteDatasources = lib.optional (!config.homeServer.services.mimir.enable) "mimir";
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
          chownVolumes = [ "data" ];
          podSpec = {
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
            volumesByName.config.configMap.name = "config";
            volumesByName.tmp.emptyDir = { };
            volumesByName.data = {
              hostPath.path = "${ccfg.dataPath}/grafana";
              hostPath.type = "DirectoryOrCreate";
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
