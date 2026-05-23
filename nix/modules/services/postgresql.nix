{ ... }:
{
  lib,
  config,
  ...
}:
let
  cfg = config.homelab.services.postgresql;
  dbBackups = lib.filterAttrs (serviceName: spec: spec.backup.enable) cfg.databases;
in
{
  options.homelab.services.postgresql = {
    enable = lib.mkEnableOption "PostgreSQL";
    dumpsVolume = lib.mkOption {
      description = "Volume source (as specificed on the pod spec) to place database dumps in";
      type = lib.types.attrsOf lib.types.anything;
    };
    databases = lib.mkOption {
      description = "Databases to create and backup, indexed by serviceName";
      type = lib.types.attrsOf (
        lib.types.submodule (
          { name, ... }@module:
          {
            options = {
              dbName = lib.mkOption {
                description = "Name of the database";
                type = lib.types.nullOr lib.types.str;
                defaultText = "`<serviceName>`";
                default = name;
              };
              username = lib.mkOption {
                description = "Database username";
                type = lib.types.nullOr lib.types.str;
                defaultText = "`<dbName>`";
                default = module.config.dbName;
              };
              password = lib.mkOption {
                description = "Password for the user";
                type = lib.types.nullOr lib.types.str;
                defaultText = "`username`";
                default = module.config.username;
              };
              backup = {
                enable = lib.mkEnableOption "backup of the database";
                schedule = lib.mkOption {
                  description = "Cronjob notation of when the database should be dumped";
                  type = lib.types.nullOr lib.types.str;
                  default = "10 3 * * *";
                  example = "10 3 * * *";
                };
              };
            };
          }
        )
      );
    };
    image = lib.mkOption {
      description = "Repo url of the PostgreSQL image to run";
      type = lib.types.str;
      default = "postgres:18";
    };
  };
  config = lib.mkIf cfg.enable {
    homelab.cluster.backup.volumes.postgresql.database-dumps = lib.mapAttrsToList (
      serviceName: spec: "/dumps/${spec.dbName}.pgdump"
    ) dbBackups;

    kubetree.resources.postgresql = {
      service-macro = {
        apiVersion = "cluster.local";
        kind = "ServiceMacro";
        metadata.name = "postgresql";
        spec = {
          dataPath = "/var/lib/postgresql";
          servicePodSpec = {
            mainContainer = {
              image = cfg.image;
              envByName.POSTGRES_PASSWORD = "postgres";
              portsByName.postgresql = 5432;
              volumeMountsByPath = {
                "/var/run/postgresql" = "run";
                "/tmp" = "tmp";
              };
              livenessProbe.tcpSocket.port = "postgresql";
              readinessProbe.tcpSocket.port = "postgresql";
            };
            volumesByName = {
              run.emptyDir = { };
              tmp.emptyDir = { };
            };
          };
        };
      };
    };
    kubetree.resources.postgresql-databases =
      (lib.mapAttrs' (
        serviceName: spec:
        let
          jobName = "create-${spec.dbName}-db";
        in
        {
          name = jobName;
          value = {
            apiVersion = "batch/v1";
            kind = "Job";
            metadata.namespace = "postgresql";
            metadata.name = jobName;
            metadata.labels."app.kubernetes.io/name" = jobName;
            spec.template = {
              metadata.labels = {
                "app.kubernetes.io/name" = jobName;
                "cluster.local/postgresql-egress" = "allow";
              };
              servicePodSpec = {
                name = jobName;
                restartPolicy = "OnFailure";
                mainContainer = {
                  image = cfg.image;
                  command = [
                    "bash"
                    "-ec"
                  ];
                  args = [
                    (lib.join "\n" (
                      map (cmd: ''psql --no-psqlrc --set ON_ERROR_STOP=1 --pset pager=off -f <(printf "%s" "${cmd}")'') [
                        "SELECT E'CREATE USER ${spec.username} WITH PASSWORD \\'${spec.password}\\'' WHERE NOT EXISTS (SELECT FROM pg_user WHERE usename = '${spec.username}')\\gexec"
                        "SELECT 'CREATE DATABASE ${spec.dbName}' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${spec.dbName}')\\gexec"
                        "ALTER DATABASE ${spec.dbName} OWNER TO ${spec.username}"
                      ]
                    ))
                  ];
                  envByName = {
                    PGHOST = "postgresql.postgresql";
                    PGUSER = "postgres";
                    PGPASSWORD = "postgres";
                  };
                };
              };
            };
          };
        }
      ) cfg.databases)
      // (lib.mapAttrs' (
        serviceName: spec:
        let
          jobName = "backup-${spec.dbName}-db";
        in
        {
          name = jobName;
          value = {
            apiVersion = "batch/v1";
            kind = "CronJob";
            metadata.namespace = "postgresql";
            metadata.name = jobName;
            metadata.labels."app.kubernetes.io/name" = jobName;
            spec.schedule = spec.backup.schedule;
            spec.jobTemplate.spec.template = {
              metadata.labels = {
                "app.kubernetes.io/name" = jobName;
                "cluster.local/postgresql-egress" = "allow";
              };
              servicePodSpec = {
                name = jobName;
                restartPolicy = "OnFailure";
                mainContainer = {
                  image = config.homelab.services.postgresql.image;
                  command = [ "pg_dump" ];
                  args = [
                    "--username=postgres"
                    "--dbname=${spec.dbName}"
                    "--blobs"
                    "--quote-all-identifiers"
                    "--format=custom"
                    "--file=/dumps/${spec.dbName}.pgdump"
                  ];
                  envByName = {
                    PGHOST = "postgresql.postgresql";
                    PGUSER = "postgres";
                    PGPASSWORD = "postgres";
                  };
                  volumeMountsByPath."/dumps" = "data";
                };
                volumesByName.data.persistentVolumeClaim.claimName = "database-dumps";
              };
            };
          };
        }
      ) dbBackups)
      // {
        data = {
          apiVersion = "v1";
          kind = "PersistentVolumeClaim";
          metadata.namespace = "postgresql";
          metadata.name = "database-dumps";
          spec = {
            accessModes = [ "ReadWriteOnce" ];
            resources.requests.storage = "1Gi";
            volumeMode = "Filesystem";
          };
        };
      };
  };
}
