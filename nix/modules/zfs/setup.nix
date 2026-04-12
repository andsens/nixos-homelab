{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.homelab.zfs;
in
{
  options.homelab.zfs = {
    cachePools = lib.mkOption {
      description = "List of ZFS pools to enable caching for";
      type = lib.types.listOf lib.types.str;
      default = [ ];
    };
  };
  config = lib.mkIf cfg.enable {
    boot = {
      # https://github.com/NixOS/nixpkgs/blob/203b1670b3a057675672c0ec8b32a5f896bbb807/nixos/modules/tasks/filesystems/zfs.nix#L704-L714
      kernelModules = [ "zfs" ];
      extraModulePackages = [ config.boot.kernelPackages.${pkgs.zfs.kernelModuleAttribute} ];
      initrd.kernelModules = [ "zfs" ];

      # https://github.com/openzfs/zfs/issues/260
      # https://github.com/openzfs/zfs/issues/12842
      # https://github.com/NixOS/nixpkgs/issues/106093
      kernelParams = lib.optionals (!config.boot.zfs.allowHibernation) [ "nohibernate" ];
    };

    environment.systemPackages = [ pkgs.zfs ];
    services.udev.packages = [ pkgs.zfs ];

    # Setup zfs-mount-generator
    # https://openzfs.github.io/openzfs-docs/man/master/8/zfs-mount-generator.8.html#EXAMPLES
    # https://github.com/NixOS/nixpkgs/issues/62644#issuecomment-1479523469
    systemd.generators."zfs-mount-generator" =
      "${config.boot.zfs.package}/lib/systemd/system-generator/zfs-mount-generator"; # The missing "s" on "system-generator" is a typo in the package

    systemd.tmpfiles.settings."50-zfs-cache" = lib.mergeAttrsList (
      map (pool: {
        "/etc/zfs/zfs-list.cache/${pool}".f = {
          user = "root";
          group = "root";
          mode = "0644";
        };
      }) cfg.cachePools
    );

    systemd.services.zfs-share.enable = false; # Share through explicit config in files, rather than ZFS properties
  };
}
