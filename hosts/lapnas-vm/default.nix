# lapNAS in a VirtualBox VM on the Windows PC, for trying changes before they reach
# the laptop. Same config as the real thing, except:
#   - disks: a 64 GB VDI as the "NVMe" (/dev/sda) and a 20 GB VDI as the "USB drive" (/dev/sdb)
#   - hostname lapnas-vm, and links point at localhost (VirtualBox forwards the ports)
#   - a known test password for the admin user, since nothing here is real
# Setup and use: docs/vm.md.
{ config, lib, ... }:
{
  imports = [ ../lapnas ];

  networking.hostName = "lapnas-vm";
  lapnas.lanHost = "localhost";

  disko.devices.disk.nvme.device = lib.mkForce "/dev/sda";
  # Stand-in for the USB media drive: formatted at install, mounted by label.
  disko.devices.disk.share = {
    type = "disk";
    device = "/dev/sdb";
    content = {
      type = "btrfs";
      extraArgs = [ "-L" "share" "-f" ];
    };
  };
  fileSystems."/srv/share".device = lib.mkForce "/dev/disk/by-label/share";

  users.users.${config.lapnas.user}.initialPassword = "lapnas-vm";

  # VM only: root ssh with the PC's key, so deploy.ps1 -Target vm needs no sudo password.
  users.users.root.openssh.authorizedKeys.keys = config.users.users.${config.lapnas.user}.openssh.authorizedKeys.keys;
  services.openssh.settings.PermitRootLogin = lib.mkForce "prohibit-password";

  virtualisation.virtualbox.guest.enable = true;
}
