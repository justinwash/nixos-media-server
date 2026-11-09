# The test VM (VirtualBox on the PC)

`lapnas-vm` is the real config running in VirtualBox, for trying changes before they reach the box. It differs only where it has to (`hosts/lapnas-vm/default.nix`):

- Disks: `system.vdi` (64 GB) plays the system disk, `share.vdi` (20 GB) plays the media drive.
- Hostname `lapnas-vm`; home page links point at `localhost`.
- The admin user's password is `lapnas-vm`, and root can ssh in with your key. Nothing in the VM is real.

Files live in `%USERPROFILE%\VirtualBox VMs\lapnas-vm`.

## Use it

Every app is forwarded to the same port on the PC (127.0.0.1 only):

| What | Address |
|---|---|
| Home page | http://localhost:8082 |
| Plex | http://localhost:32400/web |
| Sonarr / Radarr / Prowlarr | http://localhost:8989, :7878, :9696 |
| qBittorrent | http://localhost:8080 |
| Seerr | http://localhost:5055 |
| Cockpit | https://localhost:9090 (admin user / lapnas-vm) |
| ssh | `ssh -i ~/.ssh/id_ed25519 -p 2222 <admin user>@127.0.0.1` |

To see the desktop: open VirtualBox, select `lapnas-vm`, click **Show**.

Deploy a committed change: `powershell -File deploy.ps1` (defaults to the VM).

## Build it from scratch

1. **Installer ISO.** The PC has no Nix, so build it in Docker (Docker Desktop must be running). In PowerShell, from the repo folder:
   ```
   docker run --rm -v lapnas-nix-store:/nix -v "${PWD}:/repo" -v "$env:USERPROFILE\VirtualBox VMs\lapnas-vm:/out" nixos/nix:2.28.3 sh -c "git config --global safe.directory '*' && cd /repo && nix --extra-experimental-features 'nix-command flakes' build .#installer-iso --out-link /tmp/iso && cp -L /tmp/iso/iso/*.iso /out/lapnas-installer.iso"
   ```
   The `lapnas-nix-store` volume keeps Nix's downloads between runs. The same ISO is the one for the real install.
2. `powershell -File vm\create-vm.ps1`: creates the VM and boots the ISO.
3. `powershell -File vm\install-vm.ps1`: runs the same `install.ps1` as the real install, without the password prompts, then reboots into the installed system.

To start over: `"C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" unregistervm lapnas-vm --delete` (keeps the ISO), then steps 2 and 3.

To check the config builds without a VM, in the same Docker image: `nix build .#nixosConfigurations.lapnas.config.system.build.toplevel`.

## What it can't test

- Wi-Fi and the hardware watchdog: the VM has none of that hardware.
- Your real library: the stand-in drive starts empty.
- Plex connections from Sonarr/Radarr until Plex is signed in (sign in at http://localhost:32400/web, then `sudo systemctl restart lapnas-media-wiring`).

The quicker check, `tests/wiring-smoke.sh`, runs the wiring script against the real apps in Docker without a VM (instructions at the top of the file).
