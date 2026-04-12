{ lib, config, ... }:
{
  config = {
    services.samba = {
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
    services.samba-wsdd.enable = config.services.samba.enable;
    networking.firewall = lib.mkIf config.services.samba.enable {
      allowedTCPPorts = [
        139 # NetBIOS
        445 # SMB
        5357 # WSDD
      ];
      allowedUDPPorts = [
        139 # NetBIOS
        3702 # WSDD
      ];
    };
  };
}
