{ inputs, ... }:
{
  config,
  lib,
  ...
}:
let
  ccfg = config.homelab.cluster;
in
{
  options.homelab.k8sss = {
    enable = lib.mkEnableOption "k8sss";
  };
  imports = [ inputs.k8sss.nixosModules.default ];
  config = lib.mkIf config.homelab.k8sss.enable {
    k8sss.enable = true;
    k8sss.dnsNames = [ "${config.networking.hostName}.${ccfg.DOMAIN}" ];
    kubetree.resources.k8sss = lib.mkIf config.k8sss.enable {
      netpols = {
        apiVersion = "cluster.local";
        kind = "ServiceNetpols";
        metadata.name = "k8sss";
        spec.toPortsFlattened = [ config.k8sss.nodePort ];
      };
      netpol-world = {
        apiVersion = "cilium.io/v2";
        kind = "CiliumNetworkPolicy";
        metadata = {
          namespace = "k8sss";
          name = "k8sss";
          labels."app.kubernetes.io/name" = "k8sss";
        };
        spec.endpointSelector.matchLabels."app.kubernetes.io/name" = "k8sss";
        spec.ingress = [
          {
            fromEntities = [ "world" ];
            toPortsFlattened = [ config.k8sss.nodePort ];
          }
        ];
      };
    };
  };
}
