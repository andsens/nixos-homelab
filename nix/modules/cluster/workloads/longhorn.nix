{ inputs, self, ... }:
{
  config,
  pkgs,
  lib,
  ...
}:
let
  ccfg = config.homelab.cluster;
  kubelib = inputs.kube-generators.lib { inherit pkgs; };
  charts = inputs.nixhelm.charts { inherit pkgs; };
in
{
  config = {
    environment.systemPackages = [ pkgs.openiscsi ];
    services.openiscsi = {
      enable = true;
      name = "${config.networking.hostName}-initiatorhost";
    };
    systemd.services.iscsid.serviceConfig = {
      PrivateMounts = "yes";
      BindPaths = "/run/current-system/sw/bin:/bin";
    };
    systemd.tmpfiles.settings."50-longhorn"."/usr/bin/mount"."L+" = {
      user = "root";
      group = "root";
      mode = "0644";
      argument = "/run/current-system/sw/bin/mount";
    };
    kubetree.resources = {
      longhorn = {
        namespace = (self.lib.k8s.createNamespace { namespace = "longhorn"; });
        netpol = {
          apiVersion = "cilium.io/v2";
          kind = "CiliumNetworkPolicy";
          metadata = {
            namespace = "longhorn";
            name = "longhorn";
            labels."app.kubernetes.io/name" = "longhorn";
          };
          spec.endpointSelector.matchLabels = {
            "k8s:io.kubernetes.pod.namespace" = "longhorn";
          };
          spec.ingress = [
            {
              fromEndpoints = [
                {
                  matchLabels = {
                    "k8s:io.kubernetes.pod.namespace" = "longhorn";
                  };
                }
              ];
            }
          ];
          spec.egress = [
            { toEntities = [ "kube-apiserver" ]; }
            {
              toEndpoints = [
                {
                  matchLabels = {
                    "k8s:io.kubernetes.pod.namespace" = "longhorn";
                  };
                }
              ];
            }
          ];
        };
        ui-gateway = {
          apiVersion = "cluster.local";
          kind = "ServiceGateway";
          metadata.namespace = "longhorn";
          metadata.name = "longhorn-frontend";
          spec.subdomain = "longhorn";
          spec.port = 80;
        };
      };
    };
    services.k3s.manifests = {
      snapshot-crd.source = self.lib.k8s.buildKustomization { inherit pkgs; } {
        name = "snapshot-crd";
        src = pkgs.fetchFromGitHub {
          repo = "external-snapshotter";
          owner = "kubernetes-csi";
          tag = "v8.5.0";
          rootDir = "client/config/crd";
          hash = "sha256-Obrv9sziKP+k8KJeFVxrapsjmFu4lWZrovt5gzM0X+M=";
        };
      };
      longhorn-helm.source =
        self.lib.k8s.patchManifest { inherit pkgs; }
          (kubelib.buildHelmChart {
            name = "longhorn";
            namespace = "longhorn";
            chart = charts.longhorn.longhorn;
            values = {
              crds.enabled = true;
              persistence.defaultClassReplicaCount = 1;
              longhornUI.replicas = 1;
              csi = {
                attacherReplicaCount = 1;
                provisionerReplicaCount = 1;
                resizerReplicaCount = 1;
                snapshotterReplicaCount = 1;
              };
              defaultSettings = {
                defaultDataPath = "${ccfg.dataPath}/longhorn";
                defaultReplicaCount = 1;
              };
            };
          })
          (
            kubelib.toYAMLStreamFile [
              {
                apiVersion = "apps/v1";
                kind = "Deployment";
                metadata = {
                  namespace = "longhorn";
                  name = "longhorn-ui";
                };
                spec.template.metadata.labels."cluster.local/gateway-ingress" = "allow";
              }
              {
                apiVersion = "batch/v1";
                kind = "Job";
                metadata = {
                  namespace = "longhorn";
                  name = "longhorn-pre-upgrade";
                  annotations."config.kubernetes.io/local-config" = "true";
                };
              }
              {
                apiVersion = "batch/v1";
                kind = "Job";
                metadata = {
                  namespace = "longhorn";
                  name = "longhorn-post-upgrade";
                  annotations."config.kubernetes.io/local-config" = "true";
                };
              }
              {
                apiVersion = "batch/v1";
                kind = "Job";
                metadata = {
                  namespace = "longhorn";
                  name = "longhorn-uninstall";
                  annotations."config.kubernetes.io/local-config" = "true";
                };
              }
            ]
          );
    };
  };
}
