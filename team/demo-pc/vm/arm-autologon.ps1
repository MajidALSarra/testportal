# Runs INSIDE the VM as SYSTEM, AFTER Majid has signed the Folderbird app in over Bastion and closed the tab.
# Turns on ForceAutoLogon, so a 'logoff' by anyone logs the demo user straight back on. Only writes one
# HKLM registry value (no user-writable path), so it is safe to run after reviewers have had access.
param([string]$ReviewUser = 'fbreview')
$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue'
$k = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
$wl = Get-ItemProperty $k
if ($wl.AutoAdminLogon -ne '1' -or $wl.DefaultUserName -ne $ReviewUser) { throw 'auto-logon is not set up for the demo user' }
Set-ItemProperty $k -Name ForceAutoLogon -Value '1' -Type String
"ARM:OK force=$((Get-ItemProperty $k).ForceAutoLogon)"
