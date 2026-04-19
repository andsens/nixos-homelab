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
      groupadd -r -g 900 flood
      useradd -r -u 900 -g flood -d /data flood
    '';
    config.User = "900:900";
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
    assertions = [
      {
        assertion = config.homelab.services.rtorrent.enable;
        message = "The rtorrent service must be enabled in order for flood to work (homelab.services.rtorrent.enable)";
      }
    ];
    homelab.services.homepage.services.Download.Flood = {
      icon = "flood.png";
      description = "rTorrent WebUI";
      href = "https://flood.${ccfg.domain}";
      widget = {
        type = "flood";
        url = "http://flood.flood:3000";
      };
    };
    homelab.services.homepage.allowEgress = [ "flood" ];
    services.k3s.images = [ image ];
    kubetree.resources.flood.content = {
      apiVersion = "cluster.local";
      kind = "ServiceMacro";
      metadata.name = "flood";
      spec = {
        allowEgress = [ "rtorrent" ];
        ingressPort = 3000;
        dataPath = "/data";
        servicePodSpec.mainContainer = {
          image = "${image.buildArgs.name}:${image.imageTag}";
          imagePullPolicy = "Never";
          args = [
            "--host=0.0.0.0"
            "--rthost=rtorrent.rtorrent"
            "--rtport=5000"
            "--rundir=/data"
            "--auth=none"
          ];
          portsByName.web = 3000;
          livenessProbe.httpGet.port = "web";
          readinessProbe.httpGet.port = "web";
          volumeMountsByPath."/downloads" = "downloads";
        };
        servicePodSpec.volumesByName.downloads = config.homelab.services.rtorrent.downloadsVolume;
      };
    };
  };
}
