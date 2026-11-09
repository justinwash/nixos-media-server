# A light local desktop for when ssh doesn't work: plug in a keyboard, log in, look around.
# Rules: no file indexer, no automount, never sleeps (stability.nix), password login.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.lapnas.desktop;
  bookmark = name: url: { inherit name url; };
in
{
  options.lapnas.desktop.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "XFCE + LightDM for local troubleshooting. Turn off to test whether the desktop is involved in a freeze.";
  };

  config = lib.mkIf cfg.enable {
    services.xserver = {
      enable = true;
      desktopManager.xfce.enable = true;
      displayManager.lightdm.enable = true;
      xkb.layout = "us";
    };
    services.displayManager.defaultSession = "xfce";

    # Thunar without thunar-volman, so nothing mounts drives automatically.
    programs.thunar.plugins = [ ];

    # Wi-Fi in the tray: the thing most likely to be broken when ssh fails.
    programs.nm-applet.enable = true;

    programs.firefox = {
      enable = true;
      policies = {
        DisableTelemetry = true;
        DisplayBookmarksToolbar = "always";
        Homepage = {
          URL = "http://localhost:8082";
          StartPage = "homepage";
        };
        ManagedBookmarks = [
          { toplevel_name = "lapNAS"; }
          (bookmark "Home page" "http://localhost:8082")
          (bookmark "Cockpit (logs, services, disks)" "https://localhost:9090")
          (bookmark "Plex" "http://localhost:32400/web")
          (bookmark "Sonarr" "http://localhost:8989")
          (bookmark "Radarr" "http://localhost:7878")
          (bookmark "Prowlarr" "http://localhost:9696")
          (bookmark "qBittorrent" "http://localhost:8080")
          (bookmark "Seerr" "http://localhost:5055")
        ];
      };
    };

    environment.systemPackages = with pkgs; [
      xfce4-terminal
      xfce4-taskmanager
      gnome-disk-utility
    ];
  };
}
