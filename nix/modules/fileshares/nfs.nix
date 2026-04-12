{ lib, config, ... }:
{
  options.homeServer.nfs = {
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
  config = {
    services.nfs.server = {
      statdPort = 4000;
      lockdPort = 4001;
      mountdPort = 4002;
      extraNfsdConfig = lib.concatStringsSep "\n" (map (ip: "host=${ip}") config.homeServer.nfs.ips);
    };
    networking.firewall.interfaces = lib.mkIf config.services.nfs.server.enable (
      lib.mergeAttrsList (
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
        }) config.homeServer.nfs.nics
      )
    );
  };
}
