{ ... }:
{
  pkgs,
  lib,
  config,
  ...
}:
let
  ccfg = config.homelab.cluster;
  cfg = config.homelab.services.ghostfolio;
  nodejs = pkgs.nodejs_24;
  ghostbudget = pkgs.buildNpmPackage rec {
    inherit nodejs;
    name = "ghostbudget";
    version = "0.0.14";
    src = pkgs.fetchFromGitHub {
      repo = name;
      owner = "andsens";
      rev = "783b1d33ce6781b733ac0fa513a0d4dc80de51a6";
      hash = "sha256-5KVzm0zmtX3bVmWHdT3VFFzPlB81aqNb2Lem5IuWC/Y=";
    };
    npmDeps = pkgs.fetchNpmDeps {
      inherit nodejs src;
      name = "${name}-rawdeps";
      hash = "sha256-4Z8tExCLer9SfKAHwgr5GhtqI1q2j35tAeV0DE17QbI=";
    };
    dontNpmInstall = true;
    dontNpmBuild = true;
    dontNpmPrune = true;
    installPhase = ''
      runHook preInstall
      mkdir $out
      cp -a node_modules $src/src $out
      runHook postInstall
    '';
  };
  ghostbudgetImage = pkgs.dockerTools.buildImage {
    name = "cluster.local/ghostbudget";
    copyToRoot = [
      pkgs.cacert
      nodejs
      ghostbudget
    ]
    ++ ccfg.debugTools;
    config.Env = [
      "CURL_CA_BUNDLE=/etc/ssl/certs/ca-bundle.crt"
      "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
    ];
    runAsRoot = ''
      #!${pkgs.runtimeShell}
      ${pkgs.dockerTools.shadowSetup}
      groupadd -r -g ${toString ccfg.defaultUser.gid} admin
      useradd -r -u ${toString ccfg.defaultUser.uid} -g admin ghostbudget
    '';
    config.User = "${toString ccfg.defaultUser.uid}:${toString ccfg.defaultUser.gid}";
    config.Entrypoint = [
      (pkgs.lib.getExe nodejs)
      "/src/index.js"
    ];
  };
in
{
  options.homelab.services.ghostfolio = {
    importSchedule = lib.mkOption {
      description = "Cronjob notation of when the ghostbudget sync runs";
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "5 3 * * *";
    };
    actualBudgetSyncId = lib.mkOption {
      description = "Actualbudget sync ID to use when running ghostbudget";
      type = lib.types.str;
      example = "bba4b622-c8d1-4bdb-84d0-a8ecfb240ca8";
    };
    actualBudgetSyncMap = lib.mkOption {
      description = "Map of Actual Budget account names to Ghostfolio account names, use an attrSet for extended options";
      example = ''
        {
          ActualBudgetAccountName = "GhostfolioAccountName";
          Cash = "Liquid Assets";
          Investments = {
            ghostfolioName = "Liquid Assets";
            factor = 7.45;
          };
        }
      '';
      type = lib.types.attrsOf (
        lib.types.either lib.types.str (
          lib.types.submodule {
            options = {
              ghostfolioName = lib.mkOption {
                description = "The Ghostfolio account name";
                type = lib.types.str;
              };
              factor = lib.mkOption {
                description = "The amount to multiply the Actual Budget account value with";
                type = lib.types.nullOr lib.types.float;
                default = null;
              };
            };
          }
        )
      );
    };
  };
  config =
    lib.mkIf (cfg.enable && cfg.importSchedule != null && config.homelab.services.actualbudget.enable)
      {
        services.k3s.images = [ ghostbudgetImage ];
        /**
          $ cat /etc/secrets.d/ghostfolio-token.env
          GHOSTFOLIO_TOKEN='0e3e75234abc68f4378a86b3f4b32a19...'
        */
        homelab.cluster.secretsManager.importSecrets.ghostfolio-token.destinations = [ "ghostfolio" ];
        kubetree.resources.ghostbudget = {
          config = {
            apiVersion = "v1";
            kind = "ConfigMap";
            metadata = {
              namespace = "ghostfolio";
              name = "ghostbudget";
              labels."app.kubernetes.io/name" = "ghostbudget";
            };
            data."config.json" = builtins.toJSON {
              accounts = lib.mapAttrsToList (
                actualBudgetName: config:
                {
                  actualBudgetName = actualBudgetName;
                }
                // (
                  if builtins.isAttrs config then
                    {
                      ghostfolioName = config.ghostfolioName;
                    }
                    // lib.optionalAttrs (config.factor != null) { inherit (config) factor; }
                  else
                    { ghostfolioName = config; }
                )
              ) cfg.actualBudgetSyncMap;
            };
          };
          volume = {
            apiVersion = "v1";
            kind = "PersistentVolumeClaim";
            metadata.namespace = "ghostfolio";
            metadata.name = "ghostbudget";
            spec = {
              accessModes = [ "ReadWriteOnce" ];
              resources.requests.storage = "1Gi";
              volumeMode = "Filesystem";
            };
          };
          sync-accounts = {
            apiVersion = "batch/v1";
            kind = "CronJob";
            metadata.namespace = "ghostfolio";
            metadata.name = "sync-accounts";
            metadata.labels."app.kubernetes.io/name" = "ghostbudget";
            spec.schedule = cfg.importSchedule;
            spec.jobTemplate.spec.template = {
              metadata.labels = {
                "app.kubernetes.io/name" = "ghostbudget";
                "cluster.local/ghostfolio-egress" = "allow";
                "cluster.local/actualbudget-egress" = "allow";
              };
              servicePodSpec = {
                name = "ghostbudget";
                restartPolicy = "OnFailure";
                securityContext.fsGroup = config.kubetree.service-macros.defaultUser.gid;
                mainContainer = {
                  image = "${ghostbudgetImage.buildArgs.name}:${ghostbudgetImage.imageTag}";
                  imagePullPolicy = "Never";
                  args = [ "import" ];
                  envByName.ACTUAL_BUDGET_URL = "http://actualbudget.actualbudget:5006";
                  envByName.ACTUAL_BUDGET_PASS = "actual";
                  envByName.ACTUAL_BUDGET_SYNC_ID = cfg.actualBudgetSyncId;
                  # Not the actual Actual Budget data dir, this is just for the api library
                  envByName.ACTUAL_BUDGET_DATA_DIR = "/data";
                  envByName.GHOSTFOLIO_URL = "http://ghostfolio.ghostfolio:3333";
                  envByName.GHOSTFOLIO_TOKEN.valueFrom.secretKeyRef = {
                    name = "ghostfolio-token";
                    key = "GHOSTFOLIO_TOKEN";
                  };
                  volumeMountsByPath = {
                    "/config.json" = {
                      name = "config";
                      subPath = "config.json";
                    };
                    "/data" = "data";
                    "/logs" = "log";
                  };
                };
                volumesByName.config.configMap.name = "ghostbudget";
                volumesByName.data.persistentVolumeClaim.claimName = "alloy";
                volumesByName.log.emptyDir = { };
              };
            };
          };
        };
      };
}
