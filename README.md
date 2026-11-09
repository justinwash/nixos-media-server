# lapNAS: a home media server on NixOS

A NixOS flake that turns an old laptop (or any x86 box) into a home server:

| Service | What for |
|---|---|
| Plex | Movies and shows, from one USB media drive |
| Sonarr, Radarr, Prowlarr, qBittorrent | Finding and downloading TV and movies |
| Seerr | A request page for the household |
| Samba | The media drive as a Windows file share (guest) |
| Homepage | A start page with every app and live status (port 8082) |
| Cockpit | Logs, services and disks in the browser (port 9090) |
| Tailscale | Reaching it from outside without opening ports |
| XFCE | A local desktop for when ssh doesn't work |

The point is that it comes up **already wired**: after the first boot, Prowlarr feeds Sonarr and Radarr, they send downloads to qBittorrent and tell Plex to refresh, and Seerr sends requests to them. No clicking through settings pages except where an outside login is needed (Plex sign-in, indexer accounts).

It's shared as a starting point, as-is. It was written for one specific laptop and won't be kept up to date; take it and make it yours.

## Make it yours

1. **`settings.nix`**: your admin username, your PC's public SSH key, the box's address and subnet, timezone, the system disk (wiped at install) and the media drive's UUID (kept). Nothing else should need your personal details.
2. **`hosts/lapnas/hardware.nix`** and **`stability.nix`**: written for a 2019 Ryzen laptop that froze at idle. The kernel pin, kernel parameters (`processor.max_cstate=1`, NVMe and PCIe power saving off), the AMD hardware watchdog, and "never sleep, ignore the lid" are workarounds for that machine. Compare with `nixos-generate-config --show-hardware-config` on yours and drop what you don't need.
3. **`hosts/lapnas/disko.nix`**: how the system disk is partitioned (EFI + btrfs subvolumes + an 8 GB swapfile). The media drive is *not* in it, so the installer never touches it.
4. **`hosts/lapnas/media-layout.nix`**: folder layout on the media drive and the ports.
5. Optional: the desktop (`lapnas.desktop.enable` in `desktop.nix`), the home page (`homepage.nix`).

The media drive should already have (or will get) this layout, mounted at `/srv/share`:

| Path | Used by |
|---|---|
| `plex/movies/` | Radarr root folder, Plex "Movies" |
| `plex/shows/` | Sonarr root folder, Plex "TV Shows" |
| `plex/audiobooks/` | Plex only |
| `downloads/movies/`, `downloads/tv/` | qBittorrent categories `radarr` and `tv-sonarr` |

## How you manage it

From a Windows PC with PowerShell, ssh and Docker Desktop (the PC needs no Nix):
- **Install**: boot the installer ISO on the box, then `powershell -File install.ps1 -Address <ip>`. See [docs/install.md](docs/install.md).
- **Change something**: edit, commit, `powershell -File deploy.ps1` (the test VM) or `powershell -File deploy.ps1 -Target laptop` (the box). It copies the last commit over ssh and runs `nixos-rebuild` on the box. Every deploy is a boot entry you can roll back to.
- **Try it first** in a VirtualBox VM built from the same config: [docs/vm.md](docs/vm.md).

On Linux or macOS, skip the scripts: `nixos-anywhere` or `nixos-install --flake .#lapnas` to install, `nixos-rebuild switch --flake .#lapnas --target-host <user>@<ip> --use-remote-sudo` to deploy.

## Layout

```
settings.nix              # your details (above)
flake.nix                 # nixosConfigurations: lapnas, lapnas-vm, installer; packages: installer-iso
                          # inputs: nixos-26.05, plus nixos-unstable for Seerr only
install.ps1, deploy.ps1   # install and deploy from the PC over ssh
hosts/lapnas/
  default.nix             # imports; hostname, timezone, the lapnas.* options
  disko.nix               # system disk partitions
  hardware.nix            # kernel pin, kernel params, firmware, media drive by UUID
  stability.nix           # watchdog, panic-and-reboot on lockups, no sleep, Wi-Fi power save off
  network.nix             # NetworkManager, firewall, Tailscale, avahi (lapnas.local)
  admin.nix               # the admin user, ssh (keys only), Cockpit, nix settings, tools
  desktop.nix             # XFCE + LightDM, Firefox with bookmarks to every app
  media-layout.nix        # paths, ports, categories
  media.nix               # Plex, Sonarr, Radarr, Prowlarr, Seerr, qBittorrent; media group, folders, API keys
  media-wiring.nix        # runs scripts/media-wiring.py after every boot and deploy
  homepage.nix            # the start page
  samba.nix               # the share, plus wsdd so Windows sees it
hosts/lapnas-vm/          # the same, adjusted for VirtualBox
installer/                # the installer ISO: minimal NixOS + sshd with your key + NetworkManager
scripts/                  # media-wiring.py, qbt-config.py, library-import.py, settings.ps1
tests/wiring-smoke.sh     # the wiring against the real apps, in Docker
vm/                       # create and install the test VM
```

## How the media apps are wired

| From | To | What |
|---|---|---|
| Prowlarr | Sonarr, Radarr | Pushes its indexers to them (full sync) |
| Sonarr, Radarr | qBittorrent | Download client with their categories; removes each download once imported |
| Sonarr, Radarr | Plex | Refreshes the library after an import |
| Sonarr, Radarr | their root folders | `plex/shows`, `plex/movies` |
| Seerr | Sonarr, Radarr | Where requests go (once Seerr's own setup is done) |

- **API keys are fixed in advance.** On first boot `lapnas-media-keys` generates a random key for Sonarr, Radarr and Prowlarr in `/var/lib/lapnas/keys` (root-only), and the apps get them through environment files. So the wiring can run on the very first boot, and no key is ever in git.
- **`lapnas-media-wiring`** runs after every boot and deploy: for each connection above, find it by name, create it if missing, fix it if it differs. It never deletes anything, so what you add in the UIs survives. Plex and Seerr parts wait until you've signed Plex in and finished Seerr's setup page; then `sudo systemctl restart lapnas-media-wiring`.
- **qBittorrent** runs headless. `scripts/qbt-config.py` sets only a few keys in its config before each start (save path, ports, no password from localhost or your subnet), so everything you set in its UI survives.
- **No seeding**: torrents stop the moment they finish; Sonarr/Radarr import them and remove them from qBittorrent along with the download copy. Change `QBT_NO_SEEDING` in `media-wiring.py` and `removeCompletedDownloads` if you want to seed.
- **One `media` group** (Plex, the *arr apps, qBittorrent, the admin user); folders are setgid `2775`, services run with umask `0002`, and Samba forces the group, so files from anywhere stay usable by all of them.
- **No login from your home network** for Sonarr, Radarr, Prowlarr and qBittorrent (`homeAuth` in `media.nix`, `lanSubnet` in `settings.nix`). From elsewhere (Tailscale) they ask for a login you set in each app. Remove that if other people share your network.

## Credentials

None in git. Each lives in the app that uses it:

| Credential | Where | How it gets there |
|---|---|---|
| API keys between the apps | `/var/lib/lapnas/keys` | Generated on first boot |
| App logins (for outside your network) | each app | Set in its settings |
| Indexer accounts | Prowlarr | Its UI |
| Plex account | Plex | Sign in at `http://<ip>:32400/web` |
| Wi-Fi password | NetworkManager on the box | Typed in the installer, copied into the new system |
| Tailscale | tailscaled | `sudo tailscale up` once |
| Admin password | the box | Asked by `install.ps1` |

If one ever has to be in the config, use sops-nix and keep it encrypted.

## Moving an existing library in

`scripts/library-import.py` (run on the box) helps when the media drive already has a Plex library:
- `arr`: adds every movie and show Plex knows to Radarr/Sonarr at its folder, by the TMDB/TVDB id Plex matched. No searches, no downloads.
- `plex-paths --old-prefix <old mount path>`: moves Plex's library folders from an old mount path to `/srv/share`, checking every item and its watch history survive.

Without `--apply` it only prints what it would do. Usage is at the top of the file.

## License

MIT (see `LICENSE`).
