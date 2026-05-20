{ self, inputs, ... }:
{ ... }:
{
  # https://github.com/hercules-ci/flake-parts/pull/251
  key = "${toString __curPos.file}#modules.nixos.services";
  imports = [
    self.nixosModules.cluster
    inputs.setup-secrets.nixosModules.default
  ]
  ++ map (path: self.lib.parts.importApply path { inherit self inputs; }) [
    ./actual-flow.nix
    ./actualbudget.nix
    ./alloy.nix
    ./flood.nix
    ./ghostbudget.nix
    ./ghostfolio.nix
    ./grafana.nix
    ./homepage.nix
    ./metrics-server.nix
    ./mimir.nix
    ./node-exporter.nix
    ./plex.nix
    ./postgresql.nix
    ./prowlarr.nix
    ./radarr.nix
    ./redis.nix
    ./rtorrent.nix
    ./sabnzbd.nix
    ./smartctl-exporter.nix
    ./sonarr.nix
    ./zfs-exporter.nix
  ];
  config = {
    homelab.cluster.backup.hostPaths = [ "services" ];
  };
}
