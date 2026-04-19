{ self, inputs, ... }:
{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.homelab.services.metrics-server;
  kubelib = inputs.kube-generators.lib { inherit pkgs; };
in
{
  options.homelab.services.metrics-server = {
    enable = lib.mkEnableOption "metrics-server";
  };
  config = lib.mkIf cfg.enable {
    homelab.services.homepage.widgets.resources = {
      sort = lib.mkDefault 100;
      backend = "resources";
      expanded = true;
      cpu = true;
      memory = true;
      network = "default";
    };
    homelab.services.homepage.allowEgress = [ "metrics-server" ];
    services.k3s.disable = [ "metrics-server" ];
    services.k3s.manifests.metrics-server-release.source =
      self.lib.k8s.patchManifest { inherit pkgs; }
        (pkgs.fetchurl {
          url = "https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.8.0/components.yaml";
          hash = "sha256-/2TRoTuaw7BjXw3ZhYFftEwj7tRwbATl2x2q32vAqDs=";
        })
        (
          kubelib.toYAMLFile {
            apiVersion = "apps/v1";
            kind = "Deployment";
            metadata.name = "metrics-server";
            metadata.namespace = "kube-system";
            spec.template.metadata = {
              name = "metrics-server";
              labels."cluster.local/apiserver-egress" = "allow";
            };
          }
        );
    kubetree.resources.metrics-server-dynamic = {
      netpol = {
        apiVersion = "cilium.io/v2";
        kind = "CiliumNetworkPolicy";
        metadata = {
          namespace = "kube-system";
          name = "metrics-server-to-node";
          labels."app.kubernetes.io/name" = "metrics-server";
        };
        spec = {
          endpointSelector.matchLabels."app.kubernetes.io/name" = "metrics-server";
          ingress = [
            {
              toPortsFlattened = [ 10250 ];
              fromEntities = [
                "host"
                "remote-node"
              ];
            }
          ];
          egress = [
            {
              toPortsFlattened = [ 10250 ];
              toEntities = [
                "host"
                "remote-node"
              ];
            }
          ];
        };
      };
      service = {
        apiVersion = "cluster.local";
        kind = "ServiceService";
        metadata.namespace = "kube-system";
        metadata.name = "metrics-server";
        spec.portsByName.metrics = {
          port = 443;
          targetPort = 10250;
        };
      };
      netpols = {
        apiVersion = "cluster.local";
        kind = "ServiceNetpols";
        metadata.namespace = "kube-system";
        metadata.name = "metrics-server";
        spec.toPortsFlattened = [ 10250 ];
      };
    };
  };
}
