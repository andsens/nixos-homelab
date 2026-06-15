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
    ++ lib.optionals cfg.debug ccfg.debugTools;
    config.Entrypoint = [
      (pkgs.lib.getExe pkgs.flood)
    ];
  };
in
{
  options.homelab.services.flood = {
    enable = lib.mkEnableOption "flood";
    debug = lib.mkEnableOption "debug mode";
  };
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.homelab.services.rtorrent.enable;
        message = "The rtorrent service must be enabled in order for flood to work (homelab.services.rtorrent.enable)";
      }
    ];
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
          volumeMountsByPath."/torrents" = "downloads";
        };
        servicePodSpec.volumesByName.downloads = config.homelab.services.rtorrent.downloadsVolume;
      };
    };
  };
}
