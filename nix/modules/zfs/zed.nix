{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.homeServer.zfs;
in
{
  options.homeServer.zfs.zed = {
    zedlets = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = "List of zedlets to enable.";
      example = ''
        [
          "deadman-slot_off.sh"
          "trim_finish-notify.sh"
        ]
      '';
    };
    zeventNotify = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = "List of zevents for which to send notifications, uses the generic-notify.sh zedlet.";
      example = ''[ "probe_failure" ]'';
      default = [ ];
    };
    settings = lib.mkOption {
      type =
        let
          t = lib.types;
        in
        t.attrsOf (
          t.oneOf [
            t.str
            t.int
            t.bool
            (t.listOf t.str)
          ]
        );
      example = builtins.literalExpression ''
        {
          ZED_DEBUG_LOG = "/tmp/zed.debug.log";

          ZED_EMAIL_ADDR = [ "root" ];
          ZED_EMAIL_PROG = "mail";
          ZED_EMAIL_OPTS = "-s '@SUBJECT@' @ADDRESS@";

          ZED_NOTIFY_INTERVAL_SECS = 3600;
          ZED_NOTIFY_VERBOSE = false;

          ZED_USE_ENCLOSURE_LEDS = true;
          ZED_SCRUB_AFTER_RESILVER = false;
        }
      '';
      description = ''
        ZFS Event Daemon /etc/zfs/zed.d/zed.rc content

        See
        {manpage}`zed(8)`
        for details on ZED and the scripts in /etc/zfs/zed.d to find the possible variables
      '';
    };
    literalSettings = lib.mkOption {
      type = lib.types.lines;
      example = builtins.literalExpression ''
        homeServer.zfs.zed.literalSettings = ${"''"}
          . /etc/zfs/pushover-credentials.sh
        ${"''"};

        where /etc/zfs/pushover-credentials.sh is:
        ZED_PUSHOVER_TOKEN="6bw51jqdwro0to3cv8lzardoae2zc4"
        ZED_PUSHOVER_USER="gAFC9TEEdyayByq0pMtMHWopFq7kQ9"
      '';
      description = ''
        Additional settings for zed.rc that will be appended to the rendered form of `homeServer.zfs.zed.settings`.
        Useful when configuring e.g. credentials that should not be part of the nix store.
      '';
    };
  };
  config = lib.mkIf cfg.enable {
    homeServer.zfs.zed.zedlets = [
      "all-syslog.sh"
      "resilver_finish-start-scrub.sh"

      "pool_import-led.sh"
      "statechange-led.sh"
      "vdev_attach-led.sh"
      "vdev_clear-led.sh"

      "data-notify.sh"
      "resilver_finish-notify.sh"
      "scrub_finish-notify.sh"
      "statechange-notify.sh"

      "history_event-zfs-list-cacher.sh"
    ];
    homeServer.zfs.zed.settings.ZED_USE_ENCLOSURE_LEDS = lib.mkDefault true;
    homeServer.zfs.zed.settings.ZED_SYSLOG_SUBCLASS_EXCLUDE = "history_event";
    homeServer.zfs.zed.literalSettings = ''
      PATH=${
        lib.makeBinPath [
          pkgs.diffutils # Added
          pkgs.logger # Added
          config.boot.zfs.package
          pkgs.coreutils
          pkgs.curl
          pkgs.gawk
          pkgs.gnugrep
          pkgs.gnused
          pkgs.nettools
          pkgs.util-linux
        ]
      }
    '';
    # https://github.com/NixOS/nixpkgs/blob/203b1670b3a057675672c0ec8b32a5f896bbb807/nixos/modules/tasks/filesystems/zfs.nix#L847-L868
    environment.etc =
      lib.genAttrs (map (file: "zfs/zed.d/${file}") cfg.zed.zedlets) (file: {
        source = "${pkgs.zfs}/libexec/${file}";
      })
      // lib.genAttrs (map (file: "zfs/zed.d/${file}") cfg.zed.zeventNotify) (file: {
        source = "${pkgs.zfs}/libexec/generic-notify.sh";
      })
      // {
        "zfs/zed.d/zed-functions.sh".source = "${pkgs.zfs}/etc/zfs/zed.d/zed-functions.sh";
        "zfs/zpool.d".source = "${pkgs.zfs}/etc/zfs/zpool.d/";
        "zfs/zed.d/zed.rc".text =
          (lib.generators.toKeyValue {
            # https://github.com/NixOS/nixpkgs/blob/f560ccec6b1116b22e6ed15f4c510997d99d5852/nixos/modules/tasks/filesystems/zfs.nix#L258-L275
            mkKeyValue = lib.generators.mkKeyValueDefault {
              mkValueString =
                v:
                if lib.isInt v then
                  toString v
                else if lib.isString v then
                  "\"${v}\""
                else if true == v then
                  "1"
                else if false == v then
                  "0"
                else if lib.isList v then
                  "\"" + (lib.concatStringsSep " " v) + "\""
                else
                  lib.err "this value is" (toString v);
            } "=";
          } cfg.zed.settings)
          + cfg.zed.literalSettings;
      };
  };
}
