# Install lapNAS into the VM over ssh, then reboot it into the installed system.
# Usage: powershell -File vm\install-vm.ps1   (after create-vm.ps1; see docs/vm.md)
#
# Runs the same install.ps1 as the real install, so this doubles as a rehearsal.
$ErrorActionPreference = "Continue"
$VBox = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"
$Name = "lapnas-vm"
$Repo = Split-Path $PSScriptRoot -Parent
. (Join-Path $Repo "scripts\settings.ps1")  # $User, $Key
# Windows' own OpenSSH, even when started from Git Bash: Git's ssh would treat NUL as a file name.
$Ssh = Join-Path $env:SystemRoot "System32\OpenSSH\ssh.exe"

& (Join-Path $Repo "install.ps1") -Address 127.0.0.1 -Port 2222 -Config lapnas-vm -Yes -NoPasswords

Write-Host "Rebooting into the installed system..."
& $Ssh -i $Key -p 2222 -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL -o LogLevel=ERROR root@127.0.0.1 poweroff 2>$null
for ($i = 0; $i -lt 60; $i++) {
  if ((& $VBox showvminfo $Name --machinereadable | Select-String '^VMState="poweroff"')) { break }
  Start-Sleep 2
}
& $VBox storageattach $Name --storagectl SATA --port 2 --type dvddrive --medium emptydrive
& $VBox startvm $Name --type headless
Write-Host "`nDone. In a minute or two: ssh -i $Key -p 2222 ${User}@127.0.0.1, or open http://localhost:8082"
