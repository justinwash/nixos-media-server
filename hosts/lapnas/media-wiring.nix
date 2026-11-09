# Connects the media apps to each other through their APIs, on every boot and
# whenever this config changes. Safe to run again any time:
#   sudo systemctl restart lapnas-media-wiring
# What it sets up: README.md, "How the media apps are wired".
{ config, pkgs, ... }:
let
  layout = import ./media-layout.nix;
  inherit (layout) ports;
  local = port: "http://127.0.0.1:${toString port}";

  wiringConfig = pkgs.writeText "media-wiring.json" (
    builtins.toJSON {
      keysDir = layout.keysDir;
      plexPreferences = "${config.services.plex.dataDir}/Plex Media Server/Preferences.xml";
      seerrSettings = "${config.services.seerr.configDir}/settings.json";
      plex = {
        host = "127.0.0.1";
        port = ports.plex;
      };
      qbittorrent = {
        url = local ports.qbittorrent;
        host = "127.0.0.1";
        port = ports.qbittorrent;
        categories = layout.categories;
      };
      prowlarr.url = local ports.prowlarr;
      sonarr = {
        url = local ports.sonarr;
        port = ports.sonarr;
        root = layout.roots.sonarr;
        category = "tv-sonarr";
      };
      radarr = {
        url = local ports.radarr;
        port = ports.radarr;
        root = layout.roots.radarr;
        category = "radarr";
      };
      seerr.url = local ports.seerr;
    }
  );

  apps = [
    "sonarr.service"
    "radarr.service"
    "prowlarr.service"
    "qbittorrent.service"
    "plex.service"
    "seerr.service"
  ];
in
{
  systemd.services.lapnas-media-wiring = {
    description = "Connect Sonarr, Radarr, Prowlarr, qBittorrent, Plex and Seerr to each other";
    wantedBy = [ "multi-user.target" ];
    wants = apps;
    after = apps ++ [ "lapnas-media-keys.service" "lapnas-media-dirs.service" ];
    requires = [ "lapnas-media-keys.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.python3.interpreter} ${../../scripts/media-wiring.py} ${wiringConfig}";
      TimeoutStartSec = "15min";
    };
  };
}
