{ inputs, ... }:
{
  lib,
  config,
  ...
}:
let
  cfg = config.kubetree.service-macros;
  transform = inputs.kubetree.lib.transform;
  sm = import ./lib.nix { inherit lib; };
in
{
  options.kubetree.service-macros = {
    enable = lib.mkEnableOption "service macro transformers";
    domain = lib.mkOption {
      description = "Domain name to suffix hostnames with";
      type = lib.types.str;
      default = config.networking.domain;
      defaultText = builtins.literalExpression "config.networking.domain";
    };
    acmeProvider = lib.mkOption {
      description = "The ACME provider that Ingresses should use for obtaining TLS certs";
      type = lib.types.str;
    };
    securityContext = {
      runAsUser = lib.mkOption {
        description = "UID for pods to run as";
        type = lib.types.int;
        default = 1000;
      };
      runAsGroup = lib.mkOption {
        description = "GID for pods to run with, also sets securityContext.fsGroup";
        type = lib.types.int;
        default = 1000;
      };
      supplementalGroups = lib.mkOption {
        description = "Additional GIDs to apply to the pods";
        type = lib.types.listOf lib.types.int;
        default = [ 100 ];
      };
    };
  };
  config = {
    kubetree.transformers = lib.mkIf cfg.enable {
      v1.Pod._transformers = [
        sm.transformServicePod
      ];
      "cluster.local" = {
        ServiceMacro._transformers = [
          sm.transformServiceMacro
          transform.transformResource
          transform.flattenResourceList
        ];
        ServiceDeployment._transformers = [
          sm.transformServiceDeployment
          transform.transformResource
        ];
        ServiceService._transformers = [
          sm.transformServiceService
          transform.transformResource
        ];
        ServiceGateway._transformers = [
          sm.transformServiceGateway
          transform.transformResource
          transform.flattenResourceList
        ];
        ServiceNetpols._transformers = [
          sm.transformServiceNetpols
          transform.transformResource
          transform.flattenResourceList
        ];
      };
    };
  };
}
