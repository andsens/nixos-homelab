{ self, ... }:
{
  pkgs,
  lib,
  config,
  ...
}:
let
  ccfg = config.homelab.cluster;
  cfg = config.homelab.cluster.secretsManager;
  flakePkgs = self.packages.${pkgs.stdenv.hostPlatform.system};
  importSecrets = pkgs.writeShellScriptBin "import-secrets.sh" ''
    set -eo pipefail
    main() {
    local namespace args=() secret
    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (secretName: spec: ''
        args=()
        ${lib.concatStringsSep "\n" (
          lib.mapAttrsToList (fieldName: extractCommand: ''
            secret=$(${extractCommand})
            args+=("--from-literal=${fieldName}=$secret")'') spec.extractCommands
        )}
        for namespace in ${lib.concatStringsSep " " spec.destinations}; do
          kubectl create -n "$namespace" secret generic --dry-run=client -oyaml "${secretName}" "''${args[@]}" | \
            kubectl apply -f -
        done
      '') cfg.importSecrets
    )}
    }
    main "$@"
  '';
  refreshSecrets = pkgs.writeShellScriptBin "refresh-secrets.sh" ''
    set -eo pipefail
    main() {
    local namespace args=()
    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (secretName: spec: ''
        args=()
        ${lib.concatStringsSep "\n" (
          lib.mapAttrsToList (fieldName: extractCommand: ''
            secret=$(${extractCommand})
            args+=("--from-literal=${fieldName}=$secret")'') spec.extractCommands
        )}
        for namespace in ${lib.concatStringsSep " " spec.destinations}; do
          kubectl create -n "$namespace" secret generic --dry-run=client -oyaml "${secretName}" "''${args[@]}" | \
            kubectl apply -f -
        done
      '') (lib.filterAttrs (secretName: { refresh, ... }: refresh) cfg.importSecrets)
    )}
    }
    main "$@"
  '';
in
{
  options.homelab.cluster.secretsManager = {
    allowEgress = lib.mkOption {
      description = "Services the secret manager should be able to access";
      type = lib.types.listOf lib.types.str;
    };
    refreshSchedule = lib.mkOption {
      type = lib.types.str;
      description = "Cronjob notation of when secrets should be refreshed";
      example = "0 3 * * *";
      default = "10 * * * *";
    };
    importSecrets = lib.mkOption {
      description = "List of secrets. <name> becomes the secret name.";
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            extractCommands = lib.mkOption {
              description = "Bash commands to extract secrets from the source. <name> becomes the data field name.";
              type = lib.types.attrsOf lib.types.str;
            };
            destinations = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              description = "List of namespaces this secret should be created in";
              default = [ ];
            };
            refresh = lib.mkOption {
              type = lib.types.bool;
              description = "If the secret should be refreshed";
              default = false;
            };
          };
        }
      );
    };
  };
  config = {
    # services.restic.backups.default.paths = [ "/etc/secrets.d" ];
    services.k3s.manifests.secrets-manager-static.source = ./secrets-manager.yaml;
    kubetree.resources.secrets-manager = {
      cluster-role = {
        apiVersion = "rbac.authorization.k8s.io/v1";
        kind = "ClusterRole";
        metadata = {
          name = "secrets-manager";
          labels."app.kubernetes.io/name" = "secrets-manager";
        };
        rules = [
          {
            apiGroups = [ "" ];
            resources = [ "secrets" ];
            verbs = [ "create" ];
          }
          {
            apiGroups = [ "" ];
            resources = [ "secrets" ];
            resourceNames = builtins.attrNames cfg.importSecrets;
            verbs = [
              "get"
              "patch"
              "delete"
            ];
          }
        ];
      };
      script = {
        apiVersion = "v1";
        kind = "ConfigMap";
        metadata.namespace = "secrets-manager";
        metadata.name = "secrets-manager-scripts";
        data."import-secrets.sh" = builtins.readFile (lib.getExe importSecrets);
        data."refresh-secrets.sh" = builtins.readFile (lib.getExe refreshSecrets);
      };
      import-secrets = {
        apiVersion = "batch/v1";
        kind = "Job";
        metadata = {
          namespace = "secrets-manager";
          name = "import-secrets";
          labels."app.kubernetes.io/name" = "secrets-manager";
        };
        spec = {
          template.metadata.labels = {
            "app.kubernetes.io/name" = "secrets-manager";
          }
          // (lib.mergeAttrsList (
            map (service: { "cluster.local/${service}-egress" = "allow"; }) ([ "apiserver" ] ++ cfg.allowEgress)
          ));
          template.servicePodSpec = {
            name = "import-secrets";
            restartPolicy = "OnFailure";
            serviceAccountName = "secrets-manager";
            mainContainer =
              let
                # Calculate mountpath dynamically so the job re-runs on changes
                secretsMountPath = "/scripts/${
                  builtins.substring 0 8 (builtins.hashString "sha256" (lib.getExe importSecrets))
                }.sh";
              in
              {
                image = "${flakePkgs.container-utils.buildArgs.name}:${flakePkgs.container-utils.imageTag}";
                imagePullPolicy = "Never";
                command = [ (lib.getExe pkgs.bash) ];
                args = [ "${secretsMountPath}" ];
                securityContext = {
                  capabilities.add = [ "DAC_OVERRIDE" ];
                  runAsUser = 0;
                  runAsGroup = 0;
                };
                volumeMountsByPath = {
                  "${secretsMountPath}" = {
                    name = "scripts";
                    subPath = "import-secrets.sh";
                    readOnly = true;
                  };
                  ${ccfg.dataPath} = {
                    name = "data";
                    readOnly = true;
                  };
                  "/etc/secrets.d" = {
                    name = "secrets";
                    readOnly = true;
                  };
                };
              };
            volumesByName = {
              scripts.configMap.name = "secrets-manager-scripts";
              data = {
                hostPath.path = "/mnt/cluster/data";
                hostPath.type = "Directory";
              };
              secrets = {
                hostPath.path = "/etc/secrets.d";
                hostPath.type = "Directory";
              };
            };
          };
        };
      };

      refresh-secrets = {
        apiVersion = "batch/v1";
        kind = "CronJob";
        metadata = {
          namespace = "secrets-manager";
          name = "refresh-secrets";
          labels."app.kubernetes.io/name" = "secrets-manager";
        };
        spec.schedule = cfg.refreshSchedule;
        spec.jobTemplate.spec = {
          template.metadata.labels = {
            "app.kubernetes.io/name" = "secrets-manager";
          }
          // (lib.mergeAttrsList (
            map (service: { "cluster.local/${service}-egress" = "allow"; }) ([ "apiserver" ] ++ cfg.allowEgress)
          ));
          template.servicePodSpec = {
            name = "refresh-secrets";
            restartPolicy = "OnFailure";
            serviceAccountName = "secrets-manager";
            mainContainer =
              let
                # Calculate mountpath dynamically so the job re-runs on changes
                secretsMountPath = "/scripts/${
                  builtins.substring 0 8 (builtins.hashString "sha256" (lib.getExe refreshSecrets))
                }.sh";
              in
              {
                image = "${flakePkgs.container-utils.buildArgs.name}:${flakePkgs.container-utils.imageTag}";
                imagePullPolicy = "Never";
                command = [ (lib.getExe pkgs.bash) ];
                args = [ "${secretsMountPath}" ];
                securityContext = {
                  capabilities.add = [ "DAC_OVERRIDE" ];
                  runAsUser = 0;
                  runAsGroup = 0;
                };
                volumeMountsByPath = {
                  "${secretsMountPath}" = {
                    name = "scripts";
                    subPath = "refresh-secrets.sh";
                    readOnly = true;
                  };
                  ${ccfg.dataPath} = {
                    name = "data";
                    readOnly = true;
                  };
                  "/etc/secrets.d" = {
                    name = "secrets";
                    readOnly = true;
                  };
                };
              };
            volumesByName = {
              scripts.configMap.name = "secrets-manager-scripts";
              data = {
                hostPath.path = "/mnt/cluster/data";
                hostPath.type = "Directory";
              };
              secrets = {
                hostPath.path = "/etc/secrets.d";
                hostPath.type = "Directory";
              };
            };
          };
        };
      };
    };
  };
}
