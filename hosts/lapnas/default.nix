{ lib, ... }:
let
  s = import ../../settings.nix;
in
{
  imports = [
    ./disko.nix
    ./hardware.nix
    ./stability.nix
    ./network.nix
    ./admin.nix
    ./desktop.nix
    ./media.nix
    ./media-wiring.nix
    ./homepage.nix
    ./samba.nix
  ];

  options.lapnas = {
    lanHost = lib.mkOption {
      type = lib.types.str;
      default = s.lanHost;
      description = "Address other machines use to reach lapNAS. Used for links on the home page and Cockpit's allowed origins.";
    };
    user = lib.mkOption {
      type = lib.types.str;
      default = s.user;
      description = "The admin account (settings.nix).";
    };
  };

  config = {
    networking.hostName = lib.mkDefault "lapNAS";
    time.timeZone = s.timeZone;
    i18n.defaultLocale = "en_US.UTF-8";

    # Set at install time. Don't change it later: it decides data formats, not the NixOS version.
    system.stateVersion = "26.05";
  };
}
