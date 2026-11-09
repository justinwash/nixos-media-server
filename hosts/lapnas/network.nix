{ ... }:
{
  # Wi-Fi is joined once by hand at install time (see docs/install.md). NetworkManager
  # keeps that connection in /etc/NetworkManager/system-connections, so the
  # Wi-Fi password never goes in this repo.
  networking.networkmanager.enable = true;

  networking.firewall = {
    enable = true;
    # Everything on Tailscale is ours.
    trustedInterfaces = [ "tailscale0" ];
  };

  # Remote access. Log in once with `sudo tailscale up` (see docs/install.md).
  services.tailscale.enable = true;

  # lapnas.local on the LAN.
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
    };
  };
}
