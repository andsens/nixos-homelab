{ ... }:
{
  lib,
  ...
}:
{
  options.homelab.zfs = {
    enable = lib.mkEnableOption "enable zfs support";
  };
  imports = [
    ./setup.nix
    ./encryption-keys.nix
    ./units.nix
    ./zed.nix
  ];
}
