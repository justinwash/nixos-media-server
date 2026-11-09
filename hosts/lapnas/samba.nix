# One guest share: the whole USB drive. Files written from Windows
# end up as <admin user>:media, so the media apps can use them.
{ config, ... }:
let
  layout = import ./media-layout.nix;
in
{
  services.samba = {
    enable = true;
    openFirewall = true;
    nmbd.enable = true;
    settings = {
      global = {
        workgroup = "WORKGROUP";
        "server string" = "lapNAS";
        "netbios name" = "lapNAS";
        security = "user";
        "map to guest" = "Bad User";
        "guest account" = "nobody";
        "server min protocol" = "SMB2";
      };
      share = {
        path = layout.share;
        browseable = "yes";
        "read only" = "no";
        "guest ok" = "yes";
        "force user" = config.lapnas.user;
        "force group" = "media";
        "create mask" = "0664";
        "directory mask" = "2775";
      };
    };
  };

  # So Windows finds lapNAS under Network.
  services.samba-wsdd = {
    enable = true;
    openFirewall = true;
  };

  systemd.services.samba-smbd.unitConfig.RequiresMountsFor = [ layout.share ];
}
