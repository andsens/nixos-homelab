{ self, ... }:
{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.homelab.services.alloy;
in
{
  options.homelab.services.alloy = {
    enable = lib.mkEnableOption "alloy";
    allowEgress = lib.mkOption {
      description = "Which services llo should be allowed access to";
      type = lib.types.listOf lib.types.str;
    };
  };
  config = lib.mkIf cfg.enable {
    services.k3s.manifests = {
      alloy-static.source = ./alloy.yaml;
      prometheus-crds.source = pkgs.fetchurl {
        url = "https://github.com/prometheus-operator/prometheus-operator/releases/download/v0.86.2/stripped-down-crds.yaml";
        hash = "sha256-fJ1FUzOsXqeDfV8OTt2WZpjkTt15EIuv3YUI8tpQO1s=";
      };
    };
    kubetree.resources = {
      alloy-dynamic = {
        namespace = (self.lib.k8s.createNamespace { namespace = "alloy"; });
        config = {
          apiVersion = "v1";
          kind = "ConfigMap";
          metadata = {
            namespace = "alloy";
            name = "config";
            labels."app.kubernetes.io/name" = "alloy";
          };
          data."alloy-config.alloy" = builtins.readFile ./alloy-config.alloy;
        };
        data = {
          apiVersion = "v1";
          kind = "PersistentVolumeClaim";
          metadata.namespace = "alloy";
          metadata.name = "alloy";
          spec = {
            accessModes = [ "ReadWriteOnce" ];
            resources.requests.storage = "1Gi";
            volumeMode = "Filesystem";
          };
        };
        daemonset = {
          apiVersion = "apps/v1";
          kind = "DaemonSet";
          metadata = {
            namespace = "alloy";
            name = "alloy";
            labels."app.kubernetes.io/name" = "alloy";
          };
          spec = {
            minReadySeconds = 10;
            selector.matchLabels."app.kubernetes.io/name" = "alloy";
            template.metadata = {
              labels = {
                "app.kubernetes.io/name" = "alloy";
                "cluster.local/gateway-ingress" = "allow";
              }
              // (lib.mergeAttrsList (
                map (service: { "cluster.local/${service}-egress" = "allow"; }) ([ "apiserver" ] ++ cfg.allowEgress)
              ));
              annotations."kubectl.kubernetes.io/default-container" = "alloy";
            };
            template.servicePodSpec = {
              name = "alloy";
              mainContainer = {
                image = "docker.io/grafana/alloy:v1.11.3";
                args = [
                  "run"
                  "/etc/alloy/alloy-config.alloy"
                  "--storage.path=/data"
                  "--server.http.listen-addr=0.0.0.0:3000"
                ];
                envByName.HOSTNAME.valueFrom.fieldRef.fieldPath = "spec.nodeName";
                portsByName.web = 3000;
                readinessProbe = {
                  httpGet = {
                    path = "/-/ready";
                    port = "web";
                    scheme = "HTTP";
                  };
                  initialDelaySeconds = 10;
                  timeoutSeconds = 1;
                };
                volumeMountsByPath."/etc/alloy" = "config";
                volumeMountsByPath."/data" = "data";
              };
              containersByName.config-reloader = {
                image = "quay.io/prometheus-operator/prometheus-config-reloader:v0.81.0";
                args = [
                  "--watched-dir=/etc/alloy"
                  "--reload-url=http://localhost:3000/-/reload"
                ];
                volumeMountsByPath."/etc/alloy" = "config";
              };
              volumesByName.config.configMap.name = "config";
              volumesByName.data.persistentVolumeClaim.claimName = "alloy";
            };
          };
        };
        service = {
          apiVersion = "cluster.local";
          kind = "ServiceService";
          metadata.name = "alloy";
          spec.portsByName.web = 3000;
        };
        gateway = {
          apiVersion = "cluster.local";
          kind = "ServiceGateway";
          metadata.name = "alloy";
          spec.port = 3000;
        };
        netpols = {
          apiVersion = "cluster.local";
          kind = "ServiceNetpols";
          metadata.name = "alloy";
          spec.toPortsFlattened = [ 3000 ];
        };
      };
    };
  };
}
