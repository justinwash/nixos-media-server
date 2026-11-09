# Installer ISO for lapNAS (and the VirtualBox VM). It's the stock minimal NixOS
# installer plus:
#   - sshd on at boot, root login with the PC's key only, so the install can be
#     driven from the PC
#   - NetworkManager (nmtui) for joining Wi-Fi on the laptop
#   - flakes on, git and disko included
# Build: see docs/install.md.
{
  lib,
  modulesPath,
  pkgs,
  ...
}:
{
  imports = [ "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix" ];

  users.users.root.openssh.authorizedKeys.keys = (import ../settings.nix).sshKeys;
  services.openssh.settings.PasswordAuthentication = false;
  systemd.services.sshd.wantedBy = lib.mkForce [ "multi-user.target" ];

  # NetworkManager drives Wi-Fi through wpa_supplicant (networking.wireless, D-Bus
  # controlled). Don't force networking.wireless off: that removes wpa_supplicant and
  # the card shows as "unavailable".
  networking.networkmanager.enable = true;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  environment.systemPackages = with pkgs; [
    git
    disko
  ];
}
