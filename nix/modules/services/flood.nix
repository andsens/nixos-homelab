{ ... }:
{
  pkgs,
  lib,
  config,
  ...
}:
let
  ccfg = config.homelab.cluster;
  cfg = config.homelab.services.flood;
  image = pkgs.dockerTools.buildImage {
    name = "cluster.local/flood";
    copyToRoot = [
      pkgs.flood
      pkgs.mediainfo
    ]
    ++ ccfg.debugTools;
    runAsRoot = ''
      #!${pkgs.runtimeShell}
      ${pkgs.dockerTools.shadowSetup}
      groupadd -r -g ${toString ccfg.defaultUser.gid} admin
      useradd -r -u ${toString ccfg.defaultUser.uid} -g admin -d "${ccfg.dataPath}/flood" flood
    '';
    config.User = "${toString ccfg.defaultUser.uid}:${toString ccfg.defaultUser.gid}";
    config.Entrypoint = [
      (pkgs.lib.getExe pkgs.flood)
    ];
  };
in
{
  options.homelab.services.flood = {
    enable = lib.mkEnableOption "flood";
  };
  config = lib.mkIf cfg.enable {
    homelab.services.homepage.services.Download.Flood = {
      icon = "flood.png";
      description = "rTorrent WebUI";
      href = "https://flood.${ccfg.domain}";
      widget = {
        type = "flood";
        url = "http://flood.flood:3000";
      };
    };
    homelab.services.rtorrent.enable = true;
    homelab.services.homepage.allowEgress = [ "flood" ];
    services.k3s.images = [ image ];
    kubetree.resources.flood.content = {
      apiVersion = "cluster.local";
      kind = "ServiceMacro";
      metadata.name = "flood";
      spec = {
        allowEgress = [ "rtorrent" ];
        ingressPort = 3000;
        podSpec.addDataMount = true;
        podSpec.mainContainer = {
          image = "${image.buildArgs.name}:${image.imageTag}";
          imagePullPolicy = "Never";
          args = [
            "--host=0.0.0.0"
            "--rthost=rtorrent.rtorrent"
            "--rtport=5000"
            "--rundir=${ccfg.dataPath}/flood"
            "--auth=none"
          ];
          portsByName.web = 3000;
          hostMounts."${config.homelab.services.rtorrent.downloadPath}".readOnly = true;
          hostMounts."${ccfg.dataPath}/rtorrent".readOnly = true;
          livenessProbe.httpGet.port = "web";
          readinessProbe.httpGet.port = "web";
        };
      };
    };
  };
}
