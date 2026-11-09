# Installing

Rehearse it in the VM first (`docs/vm.md`): `vm/install-vm.ps1` runs the same `install.ps1`.

## Before

1. Fill in `settings.nix` (README, "Make it yours") and commit: the install uses the last commit.
2. The PC needs an ssh key whose public half is in `settings.nix` (`ssh-keygen -t ed25519` makes `~/.ssh/id_ed25519`; set `LAPNAS_SSH_KEY` to use another).
3. Build the installer ISO (`docs/vm.md`, step 1) and put it on a USB stick (Ventoy, Rufus, or `dd`). It has sshd on, letting in only your key.

## Install

At the box (keyboard and screen):

1. **Unplug the media drive.** The install only touches `systemDisk`, but there's no reason to risk the media.
2. Boot the stick.
3. Wired: nothing to do. Wi-Fi: `nmtui` → Activate a connection → your network. Then `ip -br addr` to see the address.

Then on the PC, from the repo:

```
powershell -File install.ps1 -Address <address from step 3>
```

It:
- refuses to run on anything but the live installer;
- asks you to type `WIPE`, then partitions `systemDisk` with disko;
- runs `nixos-install`, which asks for a **root password** (the console login for emergencies);
- copies the installer's Wi-Fi connection into the new system, so the password never goes in git;
- asks for the **admin user's password** (sudo and the desktop).

Then `reboot` at the box, pull the stick, and plug the media drive back in.

## After first boot

1. Give the box a DHCP reservation on the router, at `lanHost`.
2. If the media drive came from another machine: `sudo chgrp -R media /srv/share/plex /srv/share/downloads && sudo chmod -R g+rwX /srv/share/plex /srv/share/downloads`.
3. Open the home page, `http://<lanHost>:8082`, and:
   - [ ] **Plex**: sign in, add the libraries (`/srv/share/plex/movies`, `/shows`, `/audiobooks`).
   - [ ] **Prowlarr**: add your indexers. They show up in Sonarr and Radarr by themselves.
   - [ ] **Seerr**: go through its setup page (sign in with Plex).
   - [ ] Re-run the wiring so it picks up Plex and Seerr: `sudo systemctl restart lapnas-media-wiring`, then look for "All media connections in place." in `journalctl -u lapnas-media-wiring` (or Cockpit → Logs).
   - [ ] For access from outside your network: a login in Sonarr, Radarr and Prowlarr (Settings → General), and a qBittorrent Web UI password (Options → Web UI; its first one is in `journalctl -u qbittorrent`).
   - [ ] **Tailscale**: `sudo tailscale up` and open the link it prints.
4. Existing library on the drive: `scripts/library-import.py` adds it to Sonarr and Radarr (README, "Moving an existing library in").
