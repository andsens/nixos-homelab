{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.homeServer.zfs;
  zfs-encrypt-key-tpm2 = pkgs.writeShellScriptBin "zfs-encrypt-key-tpm2" ''
    fatal() { printf "%s\n" "$1" >&2; exit 1; }
    main() {
      [[ $# = 1 ]] || fatal "Usage: zfs-encrypt-key-tpm2 POOLNAME"
      [[ $(id -u) = 0 ]] || fatal "Must run as root"
      local pool=$1 keyfile
      keyfile=$(mktemp --suffix zfs-key)
      trap "rm -f \"$keyfile\"" EXIT
      ${lib.getExe' pkgs.systemd "systemd-ask-password"} "Enter the key used to unlock '$pool'" >"$keyfile"
      local encdest=/etc/secrets.d/$pool.zfs-key
      ${lib.getExe' pkgs.systemd "systemd-creds"} encrypt --tpm2-device=auto --tpm2-pcrs=0+2+7+15 "$keyfile" "$encdest"
      chmod go-r "$encdest"
    }
    main "$@"
  '';
  zfs = lib.getExe' pkgs.zfs "zfs";
in
{
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ zfs-encrypt-key-tpm2 ];

    systemd.services."zfs-load-key-tpm2@" = {
      description = "Load the ZFS encryption key for pool '%I'";
      unitConfig.DefaultDependencies = false;
      after = [ "zfs-import.target" ];
      serviceConfig = {
        Type = "oneshot";
        # Generate with `zfs-encrypt-key-tpm2 POOLNAME`
        LoadCredentialEncrypted = "%I.zfs-key:/etc/secrets.d/%I.zfs-key";
        ExecStart = ''${zfs} load-key -L "file://%d/%I.zfs-key" "%I"'';
      };
    };
    # While we could just drop in the credential loading here and set the keylocation= property
    # that decrypted key would be mounted and accessible for as long as the pool itself is mounted.
    systemd.services."zfs-load-key@" = rec {
      overrideStrategy = "asDropin";
      wants = [ "zfs-load-key-tpm2@%i.service" ];
      after = wants;
    };
  };
}
