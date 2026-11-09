# Hardware of the original box, a 2019 laptop (Ryzen 5 2500U, Vega iGPU, Intel AC 9260 Wi-Fi,
# WD SN550 NVMe). Compare with `nixos-generate-config --show-hardware-config` on yours.
{ pkgs, ... }:
{
  boot.loader.systemd-boot = {
    enable = true;
    configurationLimit = 20;
  };
  boot.loader.efi.canTouchEfiVariables = true;

  # Pinned on purpose: the original box froze on the 6.18 line and is stable on 6.12.
  # Changing kernels should be its own commit, so it's easy to roll back.
  boot.kernelPackages = pkgs.linuxPackages_6_12;

  # Idle-freeze workarounds for the original laptop (README, "Make it yours"). Likely not needed on yours.
  boot.kernelParams = [
    "processor.max_cstate=1" # no deep CPU idle (classic Ryzen 1st/2nd-gen idle freeze)
    "nvme_core.default_ps_max_latency_us=0" # no NVMe power saving (SN550 APST is flaky)
    "pcie_aspm=off" # no PCIe link power saving
  ];

  boot.initrd.availableKernelModules = [ "nvme" "xhci_pci" "usb_storage" "sd_mod" ];
  boot.kernelModules = [ "kvm-amd" "sp5100_tco" ];

  hardware.enableRedistributableFirmware = true;
  hardware.cpu.amd.updateMicrocode = true;
  hardware.graphics.enable = true;

  # The USB media drive, by UUID (settings.nix). nofail: the machine still boots without it,
  # and every service that uses it has RequiresMountsFor, so none of them write
  # to the NVMe by mistake while it's missing.
  fileSystems."/srv/share" = {
    device = (import ../../settings.nix).mediaDrive;
    fsType = "btrfs";
    options = [ "nofail" "noatime" "x-systemd.device-timeout=30s" ];
  };
}
