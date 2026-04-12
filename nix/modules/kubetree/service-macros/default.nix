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
    dataPath = lib.mkOption {
      description = "Path for services whose data should persist across cluster iterations (hostPath mount)";
      type = lib.types.str;
    };
    defaultUser.uid = lib.mkOption {
      description = "Default user UID for pods";
      type = lib.types.int;
      default = 1000;
    };
    defaultUser.gid = lib.mkOption {
      description = "Default group GID for pods";
      type = lib.types.int;
      default = 1000;
    };
    utilityImage = lib.mkOption {
      description = "Tag of a utility image that can be used for ancillary tasks such as chowning new volumes";
      type = lib.types.str;
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
