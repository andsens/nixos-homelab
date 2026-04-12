{ ... }:
{ ... }:
{
  config = {
    services.restic.backups.default = {
      initialize = true;
      passwordFile = "/etc/secrets.d/restic-default-encryption.key";
    };
  };
}
