# Plex, Sonarr, Radarr, Prowlarr, Seerr and qBittorrent, sharing one `media` group
# and one folder layout on the USB drive (see media-layout.nix).
# How they get connected to each other: media-wiring.nix.
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  layout = import ./media-layout.nix;
  inherit (layout) ports keysDir;

  # For services that read or write the USB drive: they wait for it, and never start without it.
  onDrive = {
    unitConfig.RequiresMountsFor = [ layout.share ];
    requires = [ "lapnas-media-dirs.service" ];
    after = [ "lapnas-media-dirs.service" ];
    # Files they create are group-writable, so the other apps can hardlink and rename them.
    serviceConfig.UMask = lib.mkForce "0002";
  };

  # Sonarr, Radarr, Prowlarr: no login from the home network. From
  # elsewhere they ask for a login, which works once you set one in Settings > General.
  # Without this, each one asks you to create a login on first visit.
  homeAuth = {
    method = "Forms";
    required = "DisabledForLocalAddresses";
  };

  # For services that get a pre-generated API key.
  withKey = {
    requires = [ "lapnas-media-keys.service" ];
    after = [ "lapnas-media-keys.service" ];
  };

  # Only these keys in qBittorrent.conf are managed; everything else (including the
  # Web UI password you set in its UI) is left alone.
  qbtManaged = pkgs.writeText "qbittorrent-managed.json" (
    builtins.toJSON {
      LegalNotice.Accepted = "true";
      BitTorrent = {
        "Session\\DefaultSavePath" = layout.downloads;
        "Session\\TempPathEnabled" = "false";
        "Session\\Port" = toString ports.torrent;
        # New torrents use automatic management, so category save paths apply.
        "Session\\DisableAutoTMMByDefault" = "false";
      };
      Preferences = {
        "WebUI\\Port" = toString ports.qbittorrent;
        # Sonarr and Radarr on this box need no password.
        "WebUI\\LocalHostAuth" = "false";
        # Nor does anything on the home network (like the *arr apps, see homeAuth).
        # From elsewhere, e.g. Tailscale, it asks for the password set in its UI.
        "WebUI\\AuthSubnetWhitelistEnabled" = "true";
        "WebUI\\AuthSubnetWhitelist" = (import ../../settings.nix).lanSubnet;
      };
    }
  );
in
{
  users.groups.media = { };

  # Create the media folders once the drive is mounted: owned by the admin user, group media,
  # setgid so new files stay in the group.
  systemd.services.lapnas-media-dirs = {
    description = "Create the media folders on the USB drive";
    wantedBy = [ "multi-user.target" ];
    unitConfig.RequiresMountsFor = [ layout.share ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = lib.concatMapStringsSep "\n" (
      d: ''install -d -m 2775 -o ${config.lapnas.user} -g media "${d}"''
    ) layout.dirs;
  };

  # One random API key per app, made on first boot and kept in /var/lib/lapnas/keys.
  # The apps read them from environment files, and the wiring unit uses them.
  # Nobody ever has to copy or type them.
  systemd.services.lapnas-media-keys = {
    description = "Generate API keys for the media apps";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.coreutils ];
    script = ''
      umask 077
      mkdir -p ${keysDir}
      for app in sonarr radarr prowlarr; do
        f=${keysDir}/$app.env
        if [ ! -s "$f" ]; then
          key=$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')
          echo "''${app^^}__AUTH__APIKEY=$key" > "$f"
        fi
      done
      # The same keys for the home page's status widgets (homepage.nix).
      for app in sonarr radarr prowlarr; do
        echo "HOMEPAGE_VAR_''${app^^}_KEY=$(cut -d= -f2- ${keysDir}/$app.env)"
      done > ${keysDir}/homepage.env
    '';
  };

  services.plex = {
    enable = true;
    openFirewall = true;
    group = "media";
  };

  services.sonarr = {
    enable = true;
    openFirewall = true;
    group = "media";
    environmentFiles = [ "${keysDir}/sonarr.env" ];
    settings.auth = homeAuth;
  };

  services.radarr = {
    enable = true;
    openFirewall = true;
    group = "media";
    environmentFiles = [ "${keysDir}/radarr.env" ];
    settings.auth = homeAuth;
  };

  services.prowlarr = {
    enable = true;
    openFirewall = true;
    environmentFiles = [ "${keysDir}/prowlarr.env" ];
    settings.auth = homeAuth;
  };

  services.seerr = {
    enable = true;
    openFirewall = true;
    # From unstable: 26.05 has 3.2.0, which can't open a database from Seerr 3.4 or newer
    # ("no such column discordId"); Seerr only migrates forward.
    # Back to the 26.05 package once that's 3.4.1 or newer.
    package = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system}.seerr;
  };

  services.qbittorrent = {
    enable = true;
    openFirewall = true;
    group = "media";
    webuiPort = ports.qbittorrent;
    torrentingPort = ports.torrent;
    # serverConfig stays empty on purpose: the module would overwrite the whole
    # config file on every start. qbtConfig below only sets our keys.
  };

  systemd.services.plex = onDrive;
  systemd.services.sonarr = lib.mkMerge [
    onDrive
    withKey
  ];
  systemd.services.radarr = lib.mkMerge [
    onDrive
    withKey
  ];
  systemd.services.prowlarr = withKey;
  systemd.services.qbittorrent = lib.mkMerge [
    onDrive
    {
      serviceConfig.ExecStartPre = [
        "${pkgs.python3.interpreter} ${../../scripts/qbt-config.py} ${config.services.qbittorrent.profileDir}/qBittorrent/config/qBittorrent.conf ${qbtManaged}"
      ];
    }
  ];
}
