{ lib, config, ... }:
let
  cfg = config.homelab.nfs;
in
{
  options.homelab.nfs = {
    enable = lib.mkEnableOption "NFS firewall adjustments";
    nics = lib.mkOption {
      description = "List of NIC names to open NFS firewall ports for";
      type = lib.types.listOf lib.types.str;
      default = [ ];
    };
    ips = lib.mkOption {
      description = "List of IPs to restrict NFS to";
      type = lib.types.listOf lib.types.str;
      default = [ ];
    };
  };
  config = lib.mkIf cfg.enable {
    services.nfs.server = {
      statdPort = 4000;
      lockdPort = 4001;
      mountdPort = 4002;
      extraNfsdConfig = lib.concatStringsSep "\n" (map (ip: "host=${ip}") cfg.ips);
    };
    networking.firewall.interfaces = lib.mergeAttrsList (
      map (nic: {
        "${nic}" = {
          allowedTCPPorts = [
            111 # portmapper
            2049 # nfs
            config.services.nfs.server.statdPort
            config.services.nfs.server.mountdPort
            config.services.nfs.server.lockdPort
          ];
          allowedUDPPorts = [
            111 # portmapper
            2049 # nfs
            config.services.nfs.server.statdPort
            config.services.nfs.server.mountdPort
            config.services.nfs.server.lockdPort
          ];
        };
      }) cfg.nics
    );
  };
}
