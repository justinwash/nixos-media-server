# Install lapNAS from the PC onto a machine booted from the lapNAS installer (docs/install.md).
#
#   powershell -File install.ps1 -Address 192.168.1.x   # asks for root's and the admin user's passwords
#
# Wipes the target disk (disko), installs the last commit (git archive HEAD), keeps the
# installer's Wi-Fi connection, and sets the admin user's password. It doesn't reboot:
# you pull the stick.
# vm\install-vm.ps1 runs this same script against the VM.
#
# Failures are checked through exit codes: in Windows PowerShell, "Stop" would also trip
# over native programs writing progress to stderr.
param(
  [Parameter(Mandatory = $true)] [string] $Address,
  [int] $Port = 22,
  [string] $Config = "lapnas",
  [switch] $Yes,          # don't ask before wiping
  [switch] $NoPasswords   # VM: no root password, the admin's comes from the config
)
$ErrorActionPreference = "Continue"
$Repo = $PSScriptRoot
. (Join-Path $Repo "scripts\settings.ps1")  # $User, $Key
# Windows' own OpenSSH, even when started from Git Bash: Git's ssh would treat NUL as a file name.
$Ssh = Join-Path $env:SystemRoot "System32\OpenSSH\ssh.exe"
$Scp = Join-Path $env:SystemRoot "System32\OpenSSH\scp.exe"
# The installer makes a new host key on every boot, so don't record it.
$Opts = @("-i", $Key, "-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=NUL",
  "-o", "LogLevel=ERROR", "-o", "ConnectTimeout=5")
$Target = "root@$Address"

function Remote([string]$cmd, [switch]$Tty) {
  if ($Tty) { & $Ssh @Opts -p $Port -t $Target $cmd } else { & $Ssh @Opts -p $Port $Target $cmd }
  if ($LASTEXITCODE -ne 0) { throw "failed on ${Address}: $cmd" }
}
function Send([string]$from, [string]$to) {
  & $Scp @Opts -P $Port -r $from "${Target}:$to"
  if ($LASTEXITCODE -ne 0) { throw "copying $from failed" }
}

Write-Host "Waiting for the installer's ssh on ${Address}:$Port..."
for ($i = 0; $i -lt 60; $i++) {
  & $Ssh @Opts -p $Port $Target true 2>$null
  if ($LASTEXITCODE -eq 0) { break }
  Start-Sleep 5
}
if ($LASTEXITCODE -ne 0) { throw "Nothing answered on ${Address}:$Port (installer booted? a VPN in the way?)" }
# Only ever run against the live installer: its root filesystem is a tmpfs.
# (No double quotes inside remote commands: Windows PowerShell mangles them for ssh.)
Remote "[ `$(findmnt -n -o FSTYPE /) = tmpfs ] || { echo 'Not the live installer: refusing.'; exit 1; }"

if (-not $Yes) {
  Write-Host "`nThis ERASES the disk(s) in hosts/$Config/disko.nix on $Address and installs '$Config'." -ForegroundColor Yellow
  if ((Read-Host "Type WIPE to go on") -cne "WIPE") { throw "Stopped; nothing was changed." }
}

Write-Host "Copying the flake (HEAD)..."
if (git -C $Repo status --porcelain) { Write-Warning "Uncommitted changes are not installed; only HEAD is." }
$tar = Join-Path $env:TEMP "lapnas-nix.tar"
git -C $Repo archive --format=tar -o $tar HEAD
if ($LASTEXITCODE -ne 0) { throw "git archive failed" }
Send $tar "/root/lapnas-nix.tar"
Remote "rm -rf /root/lapnas-nix && mkdir /root/lapnas-nix && tar -xf /root/lapnas-nix.tar -C /root/lapnas-nix"

Write-Host "Partitioning with disko..."
Remote "disko --mode destroy,format,mount --yes-wipe-all-disks --flake /root/lapnas-nix#$Config"

Write-Host "Installing (downloads a few GB; takes a while)..."
if ($NoPasswords) {
  Remote "nixos-install --flake /root/lapnas-nix#$Config --no-root-passwd --no-channel-copy"
} else {
  Write-Host "At the end it asks for a root password: the console login for emergencies."
  Remote -Tty "nixos-install --flake /root/lapnas-nix#$Config --no-channel-copy"
}

# Keep the Wi-Fi joined in the installer, so its password never goes in git.
Remote ("c=/etc/NetworkManager/system-connections; if ls `$c/*.nmconnection >/dev/null 2>&1; then " +
  "install -d -m 700 /mnt`$c && cp `$c/*.nmconnection /mnt`$c/ && chmod 600 /mnt`$c/* && echo 'Wi-Fi connection copied.'; fi")

if (-not $NoPasswords) {
  Write-Host "Set ${User}'s password (for sudo and the desktop):"
  Remote -Tty "nixos-enter --root /mnt -c 'passwd $User'"
}

Write-Host "`nInstalled. Next: 'reboot' it, pull the USB stick, plug the media drive back in." -ForegroundColor Green
Write-Host "Then follow docs/install.md, 'After first boot'."
