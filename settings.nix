# Your details: edit these before installing (README, "Make it yours").
# Everything else in the config reads them from here.
{
  # The admin account: sudo, ssh, the desktop, and owner of the media files.
  # Its password is set at install time; it's never in the config.
  user = "admin";
  userDescription = "Admin";

  # Public SSH key(s) of the PC you manage the box from. The installer and the
  # installed system only let these in (no ssh passwords). Example:
  #   "ssh-ed25519 AAAAC3Nza... you@your-pc"
  sshKeys = [ ];

  # The box's address on your network (give it a DHCP reservation on the router),
  # and the network the media apps trust without a login.
  lanHost = "192.168.1.50";
  lanSubnet = "192.168.1.0/24";

  timeZone = "America/Chicago";

  # The disk NixOS goes on. WIPED at install. Find yours with `ls -l /dev/disk/by-id/`
  # on the installer.
  systemDisk = "/dev/disk/by-id/nvme-YOUR_DISK_HERE";

  # The media drive (kept, never formatted): `blkid` shows its UUID.
  mediaDrive = "/dev/disk/by-uuid/YOUR-MEDIA-DRIVE-UUID";
}
