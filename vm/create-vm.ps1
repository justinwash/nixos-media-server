# Create the lapnas-vm VirtualBox VM and boot it from the installer ISO.
# Usage: powershell -File vm\create-vm.ps1   (see docs/vm.md)
#
# 4 GB RAM, 4 CPUs, UEFI. Disks: system.vdi (64 GB, plays the NVMe, /dev/sda) and
# share.vdi (20 GB, plays the USB media drive, /dev/sdb). Every app port is forwarded
# to the same port on 127.0.0.1, except ssh: localhost:2222.
$ErrorActionPreference = "Stop"
$VBox = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"
$Name = "lapnas-vm"
$Base = Join-Path $env:USERPROFILE "VirtualBox VMs"
$Dir = Join-Path $Base $Name
$Iso = Join-Path $Dir "lapnas-installer.iso"

if (-not (Test-Path $Iso)) { throw "Build the installer ISO first; it should be at $Iso (docs/vm.md)." }
if ((& $VBox list vms) -match "^`"$Name`" ") { throw "$Name already exists. Remove it first: `"$VBox`" unregistervm $Name --delete" }

& $VBox createvm --name $Name --ostype Linux_64 --basefolder $Base --register
& $VBox modifyvm $Name --memory 4096 --cpus 4 --firmware efi --rtc-use-utc on `
  --graphicscontroller vmsvga --vram 64 --audio-enabled off --nic1 nat

$ports = [ordered]@{ ssh = @(2222, 22); plex = 32400; sonarr = 8989; radarr = 7878; prowlarr = 9696;
  seerr = 5055; qbittorrent = 8080; homepage = 8082; cockpit = 9090 }
foreach ($p in $ports.GetEnumerator()) {
  $hostPort, $guestPort = if ($p.Value -is [array]) { $p.Value } else { $p.Value, $p.Value }
  & $VBox modifyvm $Name --nat-pf1 "$($p.Key),tcp,127.0.0.1,$hostPort,,$guestPort"
}

& $VBox createmedium disk --filename (Join-Path $Dir "system.vdi") --size 65536
& $VBox createmedium disk --filename (Join-Path $Dir "share.vdi") --size 20480
& $VBox storagectl $Name --name SATA --add sata --controller IntelAhci --portcount 3
& $VBox storageattach $Name --storagectl SATA --port 0 --type hdd --medium (Join-Path $Dir "system.vdi")
& $VBox storageattach $Name --storagectl SATA --port 1 --type hdd --medium (Join-Path $Dir "share.vdi")
& $VBox storageattach $Name --storagectl SATA --port 2 --type dvddrive --medium $Iso

& $VBox startvm $Name --type headless
Write-Host "`n$Name is booting the installer. Next: powershell -File vm\install-vm.ps1"
