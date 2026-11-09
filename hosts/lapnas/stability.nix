# Keep the box up, and bring it back by itself if it freezes.
# Everything here comes from chasing idle freezes on the original laptop: auto-reboot on a
# lockup, swap, never sleep. Mostly harmless elsewhere; review it for your machine.
{ ... }:
{
  # Hardware watchdog (sp5100_tco): a frozen machine reboots itself in about a minute.
  systemd.settings.Manager = {
    RuntimeWatchdogSec = "30s";
    RebootWatchdogSec = "10min";
  };

  # Turn lockups into panics, and panics into a reboot after 10 s.
  boot.kernel.sysctl = {
    "kernel.softlockup_panic" = 1;
    "kernel.hardlockup_panic" = 1;
    "kernel.panic_on_rcu_stall" = 1;
    "kernel.panic" = 10;
  };

  # Write the journal to disk often, so the lines just before a freeze survive.
  services.journald.extraConfig = ''
    SyncIntervalSec=15s
  '';

  # Never sleep, whatever the lid or a desktop app asks for.
  services.logind.settings.Login = {
    HandleLidSwitch = "ignore";
    HandleLidSwitchExternalPower = "ignore";
    HandleLidSwitchDocked = "ignore";
    HandleSuspendKey = "ignore";
    HandleHibernateKey = "ignore";
    IdleAction = "ignore";
  };
  systemd.sleep.settings.Sleep = {
    AllowSuspend = "no";
    AllowHibernation = "no";
    AllowHybridSleep = "no";
    AllowSuspendThenHibernate = "no";
  };
  systemd.targets = {
    sleep.enable = false;
    suspend.enable = false;
    hibernate.enable = false;
    hybrid-sleep.enable = false;
  };
  # No suspend/resume hooks, and no xfce4-power-manager.
  powerManagement.enable = false;

  # Wi-Fi power saving off, in NetworkManager and in the driver.
  networking.networkmanager.wifi.powersave = false;
  boot.extraModprobeConfig = ''
    options iwlmvm power_scheme=1
  '';
}
