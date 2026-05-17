{ self, ... }:
{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.homelab.services.ghostfolio;
in
{
  options.homelab.services.ghostfolio = {
    enable = lib.mkEnableOption "Ghostfolio";
  };
  # TODO: Add tini
  config = lib.mkIf cfg.enable {
    homelab.services = {
      postgresql.enable = true;
      postgresql.databases.ghostfolio.backup.enable = true;
      redis.enable = true;
    };
    setup-secrets = {
      sources.GHOSTFOLIO_TOKEN = {
        description = "Ghostfolio Token";
        cmd = self.lib.setup-secrets.mkScript pkgs "getKubeSecret ghostfolio ghostfolio-token GHOSTFOLIO_TOKEN";
      };
      sources.GHOSTFOLIO_ACCESS_TOKEN_SALT = {
        description = "Ghostfolio Access Token Salt";
        cmd = self.lib.setup-secrets.mkScript pkgs ''
          getKubeSecret ghostfolio ghostfolio-secrets ACCESS_TOKEN_SALT || \
          tr -dc A-Za-z0-9 </dev/urandom | head -c 64; echo
        '';
      };
      sources.GHOSTFOLIO_JWT_SECRET_KEY = {
        description = "Ghostfolio JWT Secret Key";
        cmd = self.lib.setup-secrets.mkScript pkgs ''
          getKubeSecret ghostfolio ghostfolio-secrets JWT_SECRET_KEY || \
          tr -dc A-Za-z0-9 </dev/urandom | head -c 64; echo
        '';
      };
      destinations = [
        {
          logPrefix = "Ghostfolio (ACCESS_TOKEN_SALT & JWT_SECRET_KEY)";
          requires = [
            "GHOSTFOLIO_ACCESS_TOKEN_SALT"
            "GHOSTFOLIO_JWT_SECRET_KEY"
          ];
          cmd = self.lib.setup-secrets.mkScript pkgs ''
            kubectl create secret generic -n ghostfolio --dry-run=client ghostfolio-secrets -oyaml \
              --from-literal=ACCESS_TOKEN_SALT="$GHOSTFOLIO_ACCESS_TOKEN_SALT" \
              --from-literal=JWT_SECRET_KEY="$GHOSTFOLIO_JWT_SECRET_KEY" \
              | kubectl apply -f -
          '';
        }
      ];
    };
    kubetree.resources.ghostfolio = {
      service = {
        apiVersion = "cluster.local";
        kind = "ServiceMacro";
        metadata.name = "ghostfolio";
        spec = {
          allowEgress = [
            "internet"
            "postgresql"
            "redis"
          ];
          ingressPort = 3333;
          servicePodSpec.mainContainer = {
            image = "ghostfolio/ghostfolio:2.228.0";
            envByName."DATABASE_URL" =
              "postgresql://ghostfolio:ghostfolio@postgresql.postgresql:5432/ghostfolio";
            envByName."REDIS_HOST" = "redis.redis";
            portsByName.web = 3333;
            envFrom = [ { secretRef.name = "ghostfolio-secrets"; } ];
            livenessProbe.httpGet.port = "web";
            readinessProbe.httpGet.port = "web";
          };
        };
      };
    };
  };
}
