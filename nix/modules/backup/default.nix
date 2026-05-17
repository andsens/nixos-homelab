{ ... }:
{
  pkgs,
  lib,
  config,
  ...
}:
{
  config = {
    services.restic.backups.default = {
      initialize = true;
      passwordFile = "/etc/secrets.d/restic-default-encryption.key";
    };
    setup-secrets = {
      sources.RESTIC_DEFAULT_PASSWORD = {
        description = "Encryption password for the restic default backup";
        cmd = ''${lib.getExe' pkgs.coreutils "cat"} "${config.services.restic.backups.default.passwordFile}"'';
      };
      destinations = [
        {
          logPrefix = "Restic default backup encryption password";
          requires = [ "RESTIC_DEFAULT_PASSWORD" ];
          cmd = ''printf "%s" "$RESTIC_DEFAULT_PASSWORD" >"${config.services.restic.backups.default.passwordFile}"'';
        }
      ];
    };
  };
}
