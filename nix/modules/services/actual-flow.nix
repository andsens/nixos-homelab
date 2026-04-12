{ self, ... }:
{
  pkgs,
  lib,
  config,
  ...
}:
let
  ccfg = config.homelab.cluster;
  cfg = config.homelab.services.actualbudget;
  flakePkgs = self.packages.${pkgs.stdenv.hostPlatform.system};
  nodejs = pkgs.nodejs_24;
  actual-flow = pkgs.buildNpmPackage rec {
    inherit nodejs;
    name = "@lunchflow/actual-flow";
    version = "0.0.14";
    src = pkgs.fetchzip {
      inherit name version;
      url = "https://registry.npmjs.org/${name}/-/actual-flow-${version}.tgz";
      extension = "tar.gz";
      hash = "sha256-fRpycTPusdHlC/a0h0lCS3RS8wgY5a6weS252zrfb0Y=";
      stripRoot = true;
    };
    postPatch = "cp ${./actual-flow.package-lock.json} ./package-lock.json";
    npmDeps = pkgs.fetchNpmDeps {
      inherit nodejs src postPatch;
      name = "${name}-rawdeps";
      hash = "sha256-9+ri/wRE29pevMipF3O/571dMliWUsTigAqYJMuPa2Y=";
    };
    dontNpmInstall = true;
    dontNpmBuild = true;
    dontNpmPrune = true;
    installPhase = ''
      runHook preInstall
      mkdir $out
      cp -a node_modules $src/dist $out
      runHook postInstall
    '';
  };
  actualFlowImage = pkgs.dockerTools.buildImage {
    name = "cluster.local/actual-flow";
    copyToRoot = [
      pkgs.cacert
      nodejs
      actual-flow
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
      useradd -r -u ${toString ccfg.defaultUser.uid} -g admin -d "${ccfg.dataPath}/actualbudget" actual-flow
    '';
    config.User = "${toString ccfg.defaultUser.uid}:${toString ccfg.defaultUser.gid}";
    config.Entrypoint = [
      (pkgs.lib.getExe nodejs)
      "/dist/index.js"
    ];
  };
in
{
  options.homelab.services.actualbudget = {
    importSchedule = lib.mkOption {
      description = "Cronjob notation of when the actual-flow import runs";
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "0 3 * * *";
    };
    importConfig = lib.mkOption {
      description = "actual-flow synchronization configuration";
      type = lib.types.submodule {
        options = {
          lunchFlowBaseUrl = lib.mkOption {
            description = "The lunchflow base url";
            type = lib.types.nullOr lib.types.str;
            default = "https://lunchflow.app/api/v1";
          };
          budgetSyncId = lib.mkOption {
            description = "The budget that actual-flow should sync (found in https://actualbudget.DOMAIN/settings -> Advanced Settings -> Sync ID)";
            type = lib.types.str;
            example = "1a3e9e7a-691c-46d0-b8ec-b27773270e27";
          };
          duplicateCheckingAcrossAccounts = lib.mkOption {
            description = "Check for duplicate transactions across all accounts before import";
            type = lib.types.bool;
            default = false;
          };
          accountMappings = lib.mkOption {
            description = "List of mappings between lunchflow & actual budget accounts";
            type = lib.types.listOf (
              lib.types.submodule {
                options = {
                  lunchFlowAccountId = lib.mkOption {
                    description = "ID of the lunchflow account to sync (as in https://www.lunchflow.app/accounts/<ID>)";
                    type = lib.types.int;
                    example = "1234";
                  };
                  lunchFlowAccountName = lib.mkOption {
                    description = "Name of the lunchflow account to sync";
                    type = lib.types.str;
                    example = "Budget";
                  };
                  actualBudgetAccountId = lib.mkOption {
                    description = "ID of the Actual budget account to sync (Navigate to AB account -> https://actualbudget.DOMAIN/accounts/bba4b622-c8d1-4bdb-84d0-a8ecfb240ca8)";
                    type = lib.types.str;
                    example = "bba4b622-c8d1-4bdb-84d0-a8ecfb240ca8";
                  };
                  actualBudgetAccountName = lib.mkOption {
                    description = "Name of the Actual budget account to sync";
                    type = lib.types.str;
                    example = "Budget";
                  };
                  syncStartDate = lib.mkOption {
                    description = "Date from when to sync";
                    type = lib.types.str;
                    example = "2026-01-10";
                  };
                };
              }
            );
          };
        };
      };
    };
  };
  config = lib.mkIf (cfg.enable && cfg.importSchedule != null) {
    homelab.cluster.secretsManager.importSecrets.lunchflow-api-key = {
      extractCommands.LUNCHFLOW_API_KEY = "source /etc/secrets.d/lunchflow-api-key.env; echo $LUNCHFLOW_API_KEY";
      destinations = [ "actualbudget" ];
    };
    services.k3s.images = [ actualFlowImage ];
    services.restic.backups.default.paths = [
      "${ccfg.dataPath}/actual-flow"
    ];
    kubetree.resources.actual-flow = {
      config = {
        apiVersion = "v1";
        kind = "ConfigMap";
        metadata.namespace = "actualbudget";
        metadata.name = "actual-flow";
        data."config.json" = builtins.toJSON {
          lunchFlow.baseUrl = cfg.importConfig.lunchFlowBaseUrl;
          actualBudget = {
            serverUrl = "http://actualbudget.actualbudget:5006";
            budgetSyncId = cfg.importConfig.budgetSyncId;
            password = "actual";
            encryptionPassword = "";
            duplicateCheckingAcrossAccounts = cfg.importConfig.duplicateCheckingAcrossAccounts;
          };
          accountMappings = cfg.importConfig.accountMappings;
        };
      };
      import-transactions = {
        apiVersion = "batch/v1";
        kind = "CronJob";
        metadata.namespace = "actualbudget";
        metadata.name = "import-transactions";
        metadata.labels."app.kubernetes.io/name" = "actual-flow";
        spec.schedule = cfg.importSchedule;
        spec.jobTemplate.spec.template = {
          metadata.labels = {
            "app.kubernetes.io/name" = "actual-flow";
            "cluster.local/internet-egress" = "allow";
            "cluster.local/actualbudget-egress" = "allow";
          };
          servicePodSpec = {
            name = "actual-flow";
            restartPolicy = "OnFailure";
            chownVolumes = [ "data" ];
            initContainersByName.setup-config = {
              image = "${flakePkgs.container-utils.buildArgs.name}:${flakePkgs.container-utils.imageTag}";
              imagePullPolicy = "Never";
              args = [
                ''
                  jq --arg key "$LUNCHFLOW_API_KEY" '.lunchFlow.apiKey = $key' /config/config.json >/config-tmp/config.json
                ''
              ];
              envByName.LUNCHFLOW_API_KEY.valueFrom.secretKeyRef = {
                name = "lunchflow-api-key";
                key = "LUNCHFLOW_API_KEY";
              };
              securityContext = {
                runAsUser = ccfg.defaultUser.uid;
                runAsGroup = ccfg.defaultUser.gid;
                allowPrivilegeEscalation = false;
                readOnlyRootFilesystem = true;
                capabilities.drop = [ "ALL" ];
              };
              volumeMountsByPath = {
                "/config" = "config";
                "/config-tmp" = "config-tmp";
              };
            };
            mainContainer = {
              image = "${actualFlowImage.buildArgs.name}:${actualFlowImage.imageTag}";
              imagePullPolicy = "Never";
              workingDir = "${ccfg.dataPath}/actual-flow";
              args = [ "import" ];
              volumeMountsByPath = {
                "${ccfg.dataPath}/actual-flow/config.json" = {
                  name = "config-tmp";
                  subPath = "config.json";
                };
                "${ccfg.dataPath}/actual-flow/actual-data" = "data";
              };
            };
            volumesByName.config.configMap.name = "actual-flow";
            volumesByName.config-tmp.emptyDir = { };
            volumesByName.data.hostPath.path = "${ccfg.dataPath}/actual-flow";
          };
        };
      };
    };
  };
}
