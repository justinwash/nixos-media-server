{ config, pkgs, ... }:
let
  s = import ../../settings.nix;
in
{
  # The admin's password is set once at install time with `passwd` (see docs/install.md).
  users.users.${s.user} = {
    isNormalUser = true;
    description = s.userDescription;
    extraGroups = [ "wheel" "networkmanager" "media" ];
    openssh.authorizedKeys.keys = s.sshKeys;
  };

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  # System admin in the browser: logs, services, disks, network, a terminal.
  services.cockpit = {
    enable = true;
    openFirewall = true;
    allowed-origins = [
      "https://localhost:9090"
      "https://lapnas.local:9090"
      "https://${config.lapnas.lanHost}:9090"
    ];
  };

  nix = {
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      auto-optimise-store = true;
      trusted-users = [ "root" "@wheel" ];
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
  };

  nixpkgs.config.allowUnfree = true; # Plex

  environment.systemPackages = with pkgs; [
    git
    vim
    htop
    btop
    curl
    jq
    lm_sensors
    smartmontools
    pciutils
    usbutils
    iw
    btrfs-progs
    python3
  ];
}
