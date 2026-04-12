{
  self,
  lib,
  config,
  ...
}:
let
  cfg = config.homeServer.services.node-exporter;
in
{
  options.homeServer.services.node-exporter = {
    enable = lib.mkEnableOption "node-exporter";
  };
  config = lib.mkIf cfg.enable {
    networking.firewall.allowedTCPPorts = lib.optional config.networking.firewall.enable 9100;
    homeServer.services.alloy.allowEgress = [ "node-exporter" ];
    services.k3s.manifests.node-exporter-static.source = ./node-exporter.yaml;
    kubetree.resources.node-exporter-dynamic = {
      namespace = (self.lib.k8s.createNamespace { namespace = "node-exporter"; });
      service = {
        apiVersion = "cluster.local";
        kind = "ServiceService";
        metadata.name = "node-exporter";
        spec.portsByName.metrics = 9100;
      };
      netpols = {
        apiVersion = "cluster.local";
        kind = "ServiceNetpols";
        metadata.name = "node-exporter";
        spec.toPortsFlattened = [ 9100 ];
      };
    };
  };
}
