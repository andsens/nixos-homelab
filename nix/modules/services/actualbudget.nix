{ ... }:
{
  lib,
  config,
  ...
}:
let
  cfg = config.homelab.services.actualbudget;
in
{
  options.homelab.services.actualbudget = {
    enable = lib.mkEnableOption "Actual Budget";
  };
  config = lib.mkIf cfg.enable {
    homelab.cluster.backup.volumes.actualbudget.actualbudget = [ "/" ];
    kubetree.resources.actualbudget = {
      service-macro = {
        apiVersion = "cluster.local";
        kind = "ServiceMacro";
        metadata.name = "actualbudget";
        spec = {
          allowEgress = [ "internet" ];
          allowIngress = [ "gateway" ];
          dataPath = "/data";
          servicePodSpec.mainContainer = {
            image = "actualbudget/actual-server:sha-25d0729-alpine";
            envByName.ACTUAL_LOGIN_METHOD = "header";
            envByName.ACTUAL_ALLOWED_LOGIN_METHODS = "header,password";
            envByName.ACTUAL_TRUSTED_AUTH_PROXIES = "::/0,0.0.0.0/0";
            envByName.ACTUAL_DATA_DIR = "/data";
            envByName.ACTUAL_UPLOAD_FILE_SYNC_SIZE_LIMIT_MB = "512";
            envByName.ACTUAL_UPLOAD_SYNC_ENCRYPTED_FILE_SYNC_SIZE_LIMIT_MB = "512";
            envByName.ACTUAL_UPLOAD_FILE_SIZE_LIMIT_MB = "512";
            portsByName.web = 5006;
            livenessProbe.httpGet.port = "web";
            readinessProbe.httpGet.port = "web";
          };
        };
      };
      service-gateway = {
        apiVersion = "cluster.local";
        kind = "ServiceGateway";
        metadata.name = "actualbudget";
        spec.port = 5006;
        spec.requestHeaderModifier.add = [
          {
            name = "X-ACTUAL-PASSWORD";
            value = "actual";
          }
        ];
      };
    };
  };
}
