# The lapNAS home page (http://lapnas.local:8082): one link to every app, with live
# status for the ones that have widgets. The first place to go after install.
{ config, ... }:
let
  layout = import ./media-layout.nix;
  inherit (layout) ports;
  inherit (config.lapnas) lanHost;
  lan = port: "http://${lanHost}:${toString port}";
  local = port: "http://127.0.0.1:${toString port}";

  app = name: icon: port: description: widget: {
    ${name} = {
      inherit icon description;
      href = lan port;
    } // (if widget == null then { } else { inherit widget; });
  };
  arrWidget = type: port: key: {
    inherit type key;
    url = local port;
  };
in
{
  services.homepage-dashboard = {
    enable = true;
    openFirewall = true;
    listenPort = ports.homepage;
    allowedHosts = builtins.concatStringsSep "," [
      "localhost:${toString ports.homepage}"
      "127.0.0.1:${toString ports.homepage}"
      "${lanHost}:${toString ports.homepage}"
      "lapnas.local:${toString ports.homepage}"
      "lapnas:${toString ports.homepage}"
    ];
    environmentFiles = [ "${layout.keysDir}/homepage.env" ];

    settings = {
      title = "lapNAS";
      headerStyle = "clean";
      layout = {
        Watch = {
          style = "row";
          columns = 2;
        };
        Downloads = {
          style = "row";
          columns = 4;
        };
        Machine = {
          style = "row";
          columns = 2;
        };
      };
    };

    widgets = [
      {
        resources = {
          cpu = true;
          memory = true;
          disk = [ "/" layout.share ];
        };
      }
    ];

    services = [
      {
        Watch = [
          (app "Plex" "plex.png" ports.plex "Movies and shows" null)
          (app "Seerr" "overseerr.png" ports.seerr "Ask for something to watch" null)
        ];
      }
      {
        Downloads = [
          (app "Sonarr" "sonarr.png" ports.sonarr "TV" (
            arrWidget "sonarr" ports.sonarr "{{HOMEPAGE_VAR_SONARR_KEY}}"
          ))
          (app "Radarr" "radarr.png" ports.radarr "Movies" (
            arrWidget "radarr" ports.radarr "{{HOMEPAGE_VAR_RADARR_KEY}}"
          ))
          (app "Prowlarr" "prowlarr.png" ports.prowlarr "Indexers" (
            arrWidget "prowlarr" ports.prowlarr "{{HOMEPAGE_VAR_PROWLARR_KEY}}"
          ))
          (app "qBittorrent" "qbittorrent.png" ports.qbittorrent "Torrents" null)
        ];
      }
      {
        Machine = [
          {
            Cockpit = {
              icon = "cockpit.png";
              description = "Logs, services, disks, network";
              href = "https://${lanHost}:9090";
            };
          }
        ];
      }
    ];
  };

  systemd.services.homepage-dashboard = {
    requires = [ "lapnas-media-keys.service" ];
    after = [ "lapnas-media-keys.service" ];
  };
}
