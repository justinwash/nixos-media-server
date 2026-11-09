# Deploy the last commit to the VM or the laptop.
#
#   powershell -File deploy.ps1                  # the VirtualBox VM (no password)
#   powershell -File deploy.ps1 -Target laptop   # the real box; asks for your sudo password
#   ... -Boot                                    # apply at next reboot instead of now (kernel changes)
#
# Copies `git archive HEAD` over ssh and runs nixos-rebuild on the box itself, so the PC
# needs no Nix. Uncommitted edits are NOT deployed. Every deploy is a new boot entry:
# a bad one is undone with `sudo nixos-rebuild switch --rollback` or from the boot menu.
#
# The box: the user and address come from settings.nix (scripts/settings.ps1). Check nobody's
# watching before a deploy that restarts Plex.
param(
  [ValidateSet("vm", "laptop")] [string] $Target = "vm",
  [switch] $Boot
)
$ErrorActionPreference = "Continue"
$Repo = $PSScriptRoot
. (Join-Path $Repo "scripts\settings.ps1")  # $User, $LanHost, $Key
# Windows' own OpenSSH, even when started from Git Bash: Git's ssh would treat NUL as a file name.
$Ssh = Join-Path $env:SystemRoot "System32\OpenSSH\ssh.exe"
$Scp = Join-Path $env:SystemRoot "System32\OpenSSH\scp.exe"
$Action = if ($Boot) { "boot" } else { "switch" }

if (git -C $Repo status --porcelain) { Write-Warning "Uncommitted changes are not deployed; only HEAD is." }
$tar = Join-Path $env:TEMP "lapnas-nix.tar"
git -C $Repo archive --format=tar -o $tar HEAD
if ($LASTEXITCODE -ne 0) { throw "git archive failed" }
$unpack = "rm -rf ~/lapnas-nix && mkdir ~/lapnas-nix && tar -xf ~/lapnas-nix.tar -C ~/lapnas-nix"

if ($Target -eq "vm") {
  $o = @("-i", $Key, "-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=NUL", "-o", "LogLevel=ERROR")
  & $Scp @o -P 2222 $tar root@127.0.0.1:lapnas-nix.tar
  if ($LASTEXITCODE -ne 0) { throw "scp to the VM failed (is it running?)" }
  & $Ssh @o -p 2222 root@127.0.0.1 "$unpack && nixos-rebuild $Action --flake ~/lapnas-nix#lapnas-vm"
} else {
  & $Scp -i $Key $tar "${User}@${LanHost}:lapnas-nix.tar"
  if ($LASTEXITCODE -ne 0) { throw "scp to ${LanHost} failed (on the network? a VPN in the way?)" }
  & $Ssh -i $Key -t "${User}@${LanHost}" "$unpack && sudo nixos-rebuild $Action --flake ~/lapnas-nix#lapnas"
}
if ($LASTEXITCODE -ne 0) { throw "nixos-rebuild failed; see the output above." }
