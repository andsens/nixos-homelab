{
  self,
  pkgs,
  lib,
  config,
  ...
}:
let
  ccfg = config.homeServer.cluster;
  cfg = config.homeServer.services.zfs-exporter;
  image = pkgs.dockerTools.buildImage {
    name = "cluster.local/zfs-exporter";
    copyToRoot = [
      pkgs.prometheus-zfs-exporter
      pkgs.zfs
    ]
    ++ ccfg.debugTools;
    config.User = "0:0";
    config.Entrypoint = [
      (pkgs.lib.getExe pkgs.prometheus-zfs-exporter)
    ];
  };
in
{
  options.homeServer.services.zfs-exporter = {
    enable = lib.mkEnableOption "zfs-exporter";
  };
  config = lib.mkIf cfg.enable {
    services.k3s.images = [ image ];
    homeServer.services.alloy.allowEgress = [ "zfs-exporter" ];
    kubetree.resources.zfs-exporter = {
      namespace = (self.lib.k8s.createNamespace { namespace = "zfs-exporter"; });
      service-monitor = {
        apiVersion = "monitoring.coreos.com/v1";
        kind = "ServiceMonitor";
        metadata = {
          namespace = "zfs-exporter";
          name = "zfs-exporter";
          labels."app.kubernetes.io/name" = "zfs-exporter";
        };
        spec = {
          selector.matchLabels."app.kubernetes.io/name" = "zfs-exporter";
          endpoints = [
            {
              port = "metrics";
              metricRelabelings = [
                {
                  sourceLabels = [ "namespace" ];
                  targetLabel = "exporter_namespace";
                }
                {
                  sourceLabels = [ "pod" ];
                  targetLabel = "exporter_pod";
                }
                {
                  sourceLabels = [ "container" ];
                  targetLabel = "exporter_container";
                }
                {
                  sourceLabels = [ "instance" ];
                  targetLabel = "instance";
                  action = "replace";
                  regex = "^(.*):9134$";
                }
                {
                  regex = "^(namespace|pod|container)$";
                  action = "labeldrop";
                }
              ];
            }
          ];
        };
      };
      daemonset = {
        kind = "DaemonSet";
        apiVersion = "apps/v1";
        metadata = {
          namespace = "zfs-exporter";
          name = "zfs-exporter";
          labels."app.kubernetes.io/name" = "zfs-exporter";
        };
        spec = {
          selector.matchLabels."app.kubernetes.io/name" = "zfs-exporter";
          template.metadata.labels."app.kubernetes.io/name" = "zfs-exporter";
          template.servicePodSpec = {
            name = "zfs-exporter";
            mainContainer = {
              image = "${image.buildArgs.name}:${image.imageTag}";
              imagePullPolicy = "Never";
              addCapabilities = [ "SYS_RAWIO" ];
              portsByName.metrics = 9134;
              livenessProbe.httpGet.port = "metrics";
              readinessProbe.httpGet.port = "metrics";
              hostMounts."/dev" = "dev";
            };
          };
        };
      };
      service = {
        apiVersion = "cluster.local";
        kind = "ServiceService";
        metadata.name = "zfs-exporter";
        spec.portsByName.metrics = 9134;
      };
      netpols = {
        apiVersion = "cluster.local";
        kind = "ServiceNetpols";
        metadata.name = "zfs-exporter";
        spec.toPortsFlattened = [ 9134 ];
      };
    };
  };
}
