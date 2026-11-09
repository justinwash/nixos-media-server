# For the PowerShell scripts: the admin user and the box's address from settings.nix,
# and the ssh key to log in with. Dot-source it: . scripts\settings.ps1
$settingsFile = Join-Path (Split-Path $PSScriptRoot -Parent) "settings.nix"
$settingsText = Get-Content $settingsFile -Raw
function SettingOf([string]$name) {
  if ($settingsText -match "(?m)^\s*$name\s*=\s*`"([^`"]*)`"") { return $Matches[1] }
  throw "No '$name' in $settingsFile"
}
$User = SettingOf "user"
$LanHost = SettingOf "lanHost"
# The private half of a key listed in settings.nix's sshKeys. Set LAPNAS_SSH_KEY to use another.
$Key = if ($env:LAPNAS_SSH_KEY) { $env:LAPNAS_SSH_KEY } else { Join-Path $env:USERPROFILE ".ssh\id_ed25519" }
