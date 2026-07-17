{ ... }:
{ lib, config, ... }:
let
  cfg = config.kubetree.cilium;
  cilium = import ./lib.nix { inherit lib; };
in
{
  key = "${toString __curPos.file}#modules.nixos.kubetree-cilium";
  options.kubetree.cilium = {
    enable = lib.mkEnableOption "Cilium CRD transformers";
  };
  config = {
    kubetree.transformers."cilium.io" = lib.mkIf cfg.enable {
      CiliumClusterwideNetworkPolicy.spec = {
        ingress."[]"._transformers = [ cilium.transformToPortsFlattened ];
        egress."[]"._transformers = [ cilium.transformToPortsFlattened ];
      };
      CiliumNetworkPolicy.spec = {
        ingress."[]"._transformers = [ cilium.transformToPortsFlattened ];
        egress."[]"._transformers = [ cilium.transformToPortsFlattened ];
      };
    };
  };
}
