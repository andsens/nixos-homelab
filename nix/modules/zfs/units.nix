{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.homelab.zfs;
  zfs = lib.getExe' pkgs.zfs "zfs";
  zpool = lib.getExe' pkgs.zfs "zpool";
  zed = lib.getExe' pkgs.zfs "zed";
in
{
  config = lib.mkIf cfg.enable {
    # Setup the official ZFS units from the source repo. The ones from nixpks are pretty shoddy.
    # I am also unable to just do systemd.packages=[pkgs.zfs], then the units don't get enabled

    # This is all verbatim translated from https://github.com/openzfs/zfs/tree/6ae99d26924decb5f618b596ec7663e6a26d2e5f/etc/systemd/system
    systemd.targets = {
      zfs = {
        description = "ZFS startup target";
        wantedBy = [ "multi-user.target" ];
      };
      zfs-import = {
        description = "ZFS pool import target";
        wantedBy = [ "zfs.target" ];
      };
    };
    systemd.services = {
      zfs-import-cache = {
        description = "Import ZFS pools by cache file";
        wantedBy = [ "zfs-import.target" ];
        requires = [ "systemd-udev-settle.service" ];
        after = [
          "systemd-udev-settle.service"
          "cryptsetup.target"
          "multipathd.service"
          "systemd-remount-fs.service"
        ];
        before = [ "zfs-import.target" ];
        unitConfig = {
          Documentation = "man:zpool(8)";
          DefaultDependencies = false;
          ConditionFileNotEmpty = "%E/zfs/zpool.cache";
          ConditionPathIsDirectory = "/sys/module/zfs";
        };
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${zpool} import -c %E/zfs/zpool.cache -aN";
        };
      };
      zfs-share = {
        description = "ZFS file system shares";
        wantedBy = [ "zfs.target" ];
        wants = [ "zfs-mount.service" ];
        after = [
          "samba-smbd.service"
          "zfs-mount.service"
        ];
        before = [
          "nfs-server.service"
          "nfs-kernel-server.service"
          "rpc-statd-notify.service"
        ];
        unitConfig = {
          Documentation = "man:zfs(8)";
          PartOf = [
            "nfs-server.service"
            "nfs-kernel-server.service"
            "samba-smbd.service"
          ];
          ConditionPathIsDirectory = "/sys/module/zfs";
        };
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${zfs} share -a";
        };
      };
      "zfs-scrub@" = {
        description = "zpool scrub on %i";
        requires = [ "zfs.target" ];
        after = [ "zfs.target" ];
        unitConfig = {
          Documentation = "man:zpool-scrub(8)";
          ConditionACPower = true;
          ConditionPathIsDirectory = "/sys/module/zfs";
        };
        script = ''
          if ${zpool} status "$1" | ${lib.getExe pkgs.gnugrep} -q "scrub in progress"; then
            exec ${zpool} wait -t scrub "$1";
          else
            exec ${zpool} scrub -w "$1"
          fi
        '';
        scriptArgs = "%i";
        serviceConfig.ExecStop = "-/bin/sh -c '${zpool} scrub -p %i 2>/dev/null || true'";
      };
      "zfs-trim@" = {
        description = "zpool trim on %i";
        requires = [ "zfs.target" ];
        after = [ "zfs.target" ];
        unitConfig = {
          Documentation = "man:zpool-trim(8)";
          ConditionACPower = true;
          ConditionPathIsDirectory = "/sys/module/zfs";
        };
        script = ''
          if ${zpool} status "$1" | ${lib.getExe pkgs.gnugrep} -q "(trimming)"; then
            exec ${zpool} wait -t trim "$1";
          else
            exec ${zpool} trim -w "$1"
          fi
        '';
        scriptArgs = "%i";
        serviceConfig.ExecStop = "-/bin/sh -c '${zpool} trim -s %i 2>/dev/null || true'";
      };
      zfs-zed = {
        description = "ZFS Event Daemon (zed)";
        wantedBy = [ "zfs.target" ];
        restartTriggers = [ config.environment.etc."zfs/zed.d/zed.rc".text ];
        unitConfig = {
          Documentation = "man:zed(8)";
          ConditionPathIsDirectory = "/sys/module/zfs";
        };
        serviceConfig = {
          ExecStart = "${zed} -F";
          Restart = "always";
        };
        aliases = [ "zed.service" ];
      };
    };
    systemd.timers = {
      "zfs-scrub-monthly@" = {
        description = "Monthly zpool scrub timer for %i";
        unitConfig.Documentation = "man:zpool-scrub(8)";
        # wantedBy = [ "timers.target" ]; # .. I don't think that's right, templates shouldn't have install sections
        timerConfig = {
          OnCalendar = "monthly";
          Persistent = true;
          RandomizedDelaySec = "1h";
          Unit = "zfs-scrub@%i.service";
        };
      };
      "zfs-scrub-weekly@" = {
        description = "Weekly zpool scrub timer for %i";
        unitConfig.Documentation = "man:zpool-scrub(8)";
        # wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "weekly";
          Persistent = true;
          RandomizedDelaySec = "1h";
          Unit = "zfs-scrub@%i.service";
        };
      };
      "zfs-trim-monthly@" = {
        description = "Monthly zpool trim timer for %i";
        unitConfig.Documentation = "man:zpool-trime(8)";
        # wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "monthly";
          Persistent = true;
          RandomizedDelaySec = "1h";
          Unit = "zfs-trim@%i.service";
        };
      };
      "zfs-trim-weekly@" = {
        description = "Weekly zpool trim timer for %i";
        unitConfig.Documentation = "man:zpool-trime(8)";
        # wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "weekly";
          Persistent = true;
          RandomizedDelaySec = "1h";
          Unit = "zfs-trim@%i.service";
        };
      };
    };
  };
}
