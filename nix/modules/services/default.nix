{ self, ... }:
{ ... }:
{
  imports = [
    self.nixosModules.backup
    ./actualbudget.nix
    ./alloy.nix
    ./flood.nix
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
}
