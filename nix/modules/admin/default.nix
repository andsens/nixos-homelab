{ ... }:
{ lib, ... }:
{
  config = {
    users.mutableUsers = lib.mkDefault false;
    security.polkit.enable = lib.mkDefault true;
    services.openssh.enable = lib.mkDefault true;
    services.openssh.authorizedKeysInHomedir = lib.mkDefault false;
    users.users.admin = {
      home = lib.mkDefault "/home/admin";
      createHome = lib.mkDefault true;
      enable = lib.mkDefault true;
      isSystemUser = lib.mkDefault true;
      description = lib.mkDefault "Local administrator";
      hashedPasswordFile = lib.mkDefault "/etc/secrets.d/admin.pwhash";
      uid = lib.mkDefault 900;
      extraGroups = [
        "wheel"
        "users"
      ];
      group = "admin";
    };
    users.groups.admin = {
      name = "admin";
      gid = lib.mkDefault 900;
    };
    security.sudo = {
      enable = lib.mkDefault true;
      wheelNeedsPassword = lib.mkDefault false;
    };
    users.users.root = {
      # I *think* not having an enabled user with a UID >= 1000 breaks the login somehow
      # Disabling the root user somehow also disables the admin user, but disabling the root user manually works
      enable = lib.mkDefault true;
      hashedPassword = lib.mkDefault "!";
    };
  };
}
