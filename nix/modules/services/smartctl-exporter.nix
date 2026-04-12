{
  self,
  pkgs,
  lib,
  config,
  ...
}:
let
  ccfg = config.homeServer.cluster;
  cfg = config.homeServer.services.smartctl-exporter;
  smartctlExporter = pkgs.buildGo125Module rec {
    name = "smartctl_exporter";
    version = "0.14.0-1";
    meta.mainProgram = "smartctl_exporter";
    src = pkgs.fetchFromGitHub {
      owner = "andsens";
      repo = name;
      rev = "90ee59151c6909baca5f21de8b4a5e3508ff7919";
      hash = "sha256-0ZqD9qGpqiAliyC7ePM3tuOi8ScsGqPrhP0YKg8Cenk=";
    };
    proxyVendor = true;
    vendorHash = "sha256-wvmrLaGMZj2iSavKbSAGUfWtfNciHSoDR2sVUkzDxf4=";
  };
  image = pkgs.dockerTools.buildImage {
    name = "cluster.local/${smartctlExporter.name}";
    copyToRoot = [
      smartctlExporter
      pkgs.smartmontools
    ]
    ++ ccfg.debugTools;
    config.User = "0:0";
    config.Entrypoint = [
      (pkgs.lib.getExe smartctlExporter)
    ];
  };
in
{
  options.homeServer.services.smartctl-exporter = {
    enable = lib.mkEnableOption "smartctl-exporter";
  };
  config = lib.mkIf cfg.enable {
    services.k3s.images = [ image ];
    homeServer.services.alloy.allowEgress = [ "smartctl-exporter" ];
    kubetree.resources.smartctl-exporter = {
      namespace = (self.lib.k8s.createNamespace { namespace = "smartctl-exporter"; });
      service-monitor = {
        apiVersion = "monitoring.coreos.com/v1";
        kind = "ServiceMonitor";
        metadata = {
          namespace = "smartctl-exporter";
          name = "smartctl-exporter";
          labels."app.kubernetes.io/name" = "smartctl-exporter";
        };
        spec = {
          selector.matchLabels."app.kubernetes.io/name" = "smartctl-exporter";
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
                  regex = "^(.*):9633$";
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
          namespace = "smartctl-exporter";
          name = "smartctl-exporter";
          labels."app.kubernetes.io/name" = "smartctl-exporter";
        };
        spec = {
          selector.matchLabels."app.kubernetes.io/name" = "smartctl-exporter";
          template.metadata.labels."app.kubernetes.io/name" = "smartctl-exporter";
          template.servicePodSpec = {
            name = "smartctl-exporter";
            mainContainer = {
              image = "${image.buildArgs.name}:${image.imageTag}";
              imagePullPolicy = "Never";
              args = [ "--smartctl.path=${pkgs.lib.getExe pkgs.smartmontools}" ];
              addCapabilities = [ "SYS_RAWIO" ];
              portsByName.metrics = 9633;
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
        metadata.name = "smartctl-exporter";
        spec.portsByName.metrics = 9633;
      };
      netpols = {
        apiVersion = "cluster.local";
        kind = "ServiceNetpols";
        metadata.name = "smartctl-exporter";
        spec.toPortsFlattened = [ 9633 ];
      };
    };
  };
}
