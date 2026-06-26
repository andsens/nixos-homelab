{ ... }:
{
  lib,
  config,
  pkgs,
  ...
}:
let
  users = lib.filterAttrs (user: spec: spec.enable && spec.isNormalUser) config.users.users;
in
{
  config = {
    services.samba = {
      openFirewall = true;
      nmbd.enable = false;
      settings = {
        global = {
          "passwd program" = "";
          "passdb backend" = "tdbsam";

          "printing" = "bsd";
          "printcap name" = "/dev/null";
          "load printers" = "no";
          "disable spoolss" = "yes";

          "server min protocol" = "SMB3_11";
          "server smb encrypt" = "required";
          "server smb3 encryption algorithms" = "AES-256-GCM";
          "server smb3 signing algorithms" = "AES-128-GMAC";

          "client smb encrypt" = "required";
        };
      };
    };
    services.samba-wsdd = {
      enable = config.services.samba.enable;
      openFirewall = true;
    };
    setup-secrets = {
      sources = lib.mapAttrs' (
        user: spec: lib.nameValuePair "SMB_PW_${user}" { description = "SMB Password for ${user}"; }
      ) users;
      destinations = lib.mapAttrsToList (user: spec: {
        logPrefix = "SMB Password for ${user}";
        requires = [ "SMB_PW_${user}" ];
        cmd = lib.getExe (
          pkgs.writeShellScriptBin "set-smbpw.sh" ''
            printf "%s\n%s\n" "$SMB_PW_${user}" "$SMB_PW_${user}" | smbpasswd -Las "${user}"
          ''
        );
      }) users;
    };
  };
}
