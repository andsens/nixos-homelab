{
  lib,
  config,
  ...
}:
let
  ccfg = config.homelab.cluster;
  cfg = config.homelab.services.postgresql;
  dbBackups = lib.filterAttrs (serviceName: spec: spec.backup.enable) cfg.databases;
in
{
  options.homelab.services.postgresql = {
    enable = lib.mkEnableOption "PostgreSQL";
    databases = lib.mkOption {
      description = "Databases to create and backup, indexed by serviceName";
      type = lib.types.attrsOf (
        lib.types.submodule (
          { name, ... }@module:
          {
            options = {
              namespace = lib.mkOption {
                description = "Namespace the creation and backup job should run in";
                type = lib.types.nullOr lib.types.str;
                defaultText = "`<serviceName>`";
                default = name;
              };
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
                destination = lib.mkOption {
                  description = "Destination of the database dump";
                  type = lib.types.nullOr lib.types.str;
                  defaultText = builtins.literalExpression "\${config.homelab.cluster.dataPath}/<serviceName>/<dbName>.pgdump";
                  default = "${config.homelab.cluster.dataPath}/${name}/${module.config.dbName}.pgdump";
                };
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
    services.restic.backups.default.paths = (
      lib.mapAttrsToList (serviceName: spec: spec.backup.destination) dbBackups
    );

    kubetree.resources.postgresql = {
      service-macro = {
        apiVersion = "cluster.local";
        kind = "ServiceMacro";
        metadata.name = "postgresql";
        spec = {
          podSpec = {
            chownVolumes = [ "run" ];
            addDataMount = true;
            mainContainer = {
              image = cfg.image;
              envByName.PGDATA = "${ccfg.dataPath}/postgresql";
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
            metadata.namespace = spec.namespace;
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
            metadata.namespace = spec.namespace;
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
                chownVolumes = [ "data" ];
                mainContainer = {
                  image = config.homelab.services.postgresql.image;
                  command = [ "pg_dump" ];
                  args = [
                    "--username=postgres"
                    "--dbname=${spec.dbName}"
                    "--blobs"
                    "--quote-all-identifiers"
                    "--format=custom"
                    "--file=${spec.backup.destination}"
                  ];
                  envByName = {
                    PGHOST = "postgresql.postgresql";
                    PGUSER = "postgres";
                    PGPASSWORD = "postgres";
                  };
                  hostMounts."${builtins.dirOf spec.backup.destination}" = {
                    name = "data";
                    type = "DirectoryOrCreate";
                  };
                };
              };
            };
          };
        }
      ) dbBackups);
  };
}
