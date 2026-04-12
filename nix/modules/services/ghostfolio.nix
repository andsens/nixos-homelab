{ ... }:
{
  lib,
  config,
  ...
}:
let
  ccfg = config.homelab.cluster;
  cfg = config.homelab.services.ghostfolio;
in
{
  options.homelab.services.ghostfolio = {
    enable = lib.mkEnableOption "Ghostfolio";
  };
  # TODO: Add tini
  config = lib.mkIf cfg.enable {
    homelab.services.homepage.envByName.HOMEPAGE_VAR_GHOSTFOLIO_API_TOKEN.valueFrom.secretKeyRef = {
      name = "ghostfolio-api-token";
      key = "GHOSTFOLIO_API_TOKEN";
    };
    homelab.services = {
      postgresql.enable = true;
      postgresql.databases.ghostfolio.backup.enable = true;
      redis.enable = true;
      homepage.allowEgress = [ "ghostfolio" ];
      homepage.services.Finance.Ghostfolio = {
        icon = "ghostfolio.png";
        description = "Portfolio tracker";
        href = "https://ghostfolio.${ccfg.domain}";
        widget = {
          type = "ghostfolio";
          url = "http://ghostfolio.ghostfolio:3333";
          fields = [
            "gross_percent_today"
            "gross_percent_1y"
            "net_worth"
          ];
          key = "{{HOMEPAGE_VAR_GHOSTFOLIO_API_TOKEN}}";
        };
      };
    };
    homelab.cluster.secretsManager = {
      importSecrets.ghostfolio-token = {
        extractCommands.GHOSTFOLIO_TOKEN = "source /etc/secrets.d/ghostfolio-token.env; echo $GHOSTFOLIO_TOKEN";
      };
      allowEgress = [ "ghostfolio" ];
      importSecrets.ghostfolio-api-token = {
        refresh = true;
        # Shown when Ghostfolio is initialized
        extractCommands.GHOSTFOLIO_API_TOKEN = ''
          source /etc/secrets.d/ghostfolio-token.env
          curl -sX POST http://ghostfolio.ghostfolio:3333/api/v1/auth/anonymous -H 'Content-Type: application/json' -d "{ \"accessToken\": \"$GHOSTFOLIO_TOKEN\" }" | \
            jq -r .authToken
        '';
        destinations = [ "homepage" ];
      };
      importSecrets.ghostfolio-secrets = {
        # Generate both with `tr -dc A-Za-z0-9 </dev/urandom | head -c 64; echo`
        extractCommands.ACCESS_TOKEN_SALT = "source /etc/secrets.d/ghostfolio-secrets.env; echo $ACCESS_TOKEN_SALT";
        extractCommands.JWT_SECRET_KEY = "source /etc/secrets.d/ghostfolio-secrets.env; echo $JWT_SECRET_KEY";
        destinations = [ "ghostfolio" ];
      };
    };
    kubetree.resources.ghostfolio.content = {
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
        podSpec.mainContainer = {
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
}
