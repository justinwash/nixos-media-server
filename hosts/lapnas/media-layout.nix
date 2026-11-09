# One place for the media stack's paths, ports and names. Imported by media.nix,
# media-wiring.nix, homepage.nix and samba.nix.
rec {
  share = "/srv/share";
  downloads = "${share}/downloads";
  library = "${share}/plex";

  # qBittorrent category -> save path. Sonarr and Radarr use these categories.
  categories = {
    tv-sonarr = "${downloads}/tv";
    radarr = "${downloads}/movies";
  };

  # Sonarr/Radarr root folders = the Plex library folders.
  roots = {
    sonarr = "${library}/shows";
    radarr = "${library}/movies";
  };

  # Folders the media stack needs. Created on the USB drive at boot.
  dirs = [
    downloads
    "${downloads}/tv"
    "${downloads}/movies"
    library
    "${library}/shows"
    "${library}/movies"
    "${library}/audiobooks"
  ];

  ports = {
    plex = 32400;
    sonarr = 8989;
    radarr = 7878;
    prowlarr = 9696;
    seerr = 5055;
    qbittorrent = 8080;
    torrent = 24116; # any free port; forward it on the router for better speeds
    homepage = 8082;
  };

  # Where the generated API keys live. Root-only, never in git.
  keysDir = "/var/lib/lapnas/keys";
}
