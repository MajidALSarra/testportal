# Runs INSIDE the reviewer demo VM as SYSTEM (az vm run-command). No cost, no network change.
# Param ReviewPassword arrives as a PROTECTED run-command parameter: never logged, never echoed.
# 0. A STANDARD (non-admin) local user for the Folderbird app. Reviewers get a shell through the
#    exec scope, so the app must not run as an administrator. The VM's admin account is created with a
#    random password nobody keeps; all admin work goes through run-command as SYSTEM.
# 1. Auto-logon for the local user (Sysinternals Autologon stores the password as an LSA secret,
#    not as plain text in the Winlogon key) - the Folderbird tray app is not a service, so without
#    a logged-on user the device stays offline after every restart.
# 2. A logon task that installs the Folderbird app per-user (the installer is PrivilegesRequired=lowest
#    and must run as the interactive user, never as SYSTEM) and starts it if it is not running.
# 3. No sleep, no hibernate.
param([Parameter(Mandatory)][string]$ReviewUser, [Parameter(Mandatory)][string]$ReviewPassword)
$ErrorActionPreference = 'Stop'
$root = 'C:\ProgramData\FolderbirdDemo'
New-Item -ItemType Directory -Force -Path $root | Out-Null

# --- standard user ------------------------------------------------------------------------------
$sec = ConvertTo-SecureString $ReviewPassword -AsPlainText -Force
if (Get-LocalUser -Name $ReviewUser -ErrorAction SilentlyContinue) { Set-LocalUser -Name $ReviewUser -Password $sec -PasswordNeverExpires $true }
else { New-LocalUser -Name $ReviewUser -Password $sec -PasswordNeverExpires -UserMayNotChangePassword -FullName 'Demo User' | Out-Null }
Add-LocalGroupMember -Group 'Users' -Member $ReviewUser -ErrorAction SilentlyContinue
Add-LocalGroupMember -Group 'Remote Desktop Users' -Member $ReviewUser -ErrorAction SilentlyContinue   # Bastion sign-in
if (Get-LocalGroupMember -Group 'Administrators' | Where-Object Name -like "*\$ReviewUser") { throw "$ReviewUser must not be an administrator" }

# --- auto-logon -------------------------------------------------------------------------------
$al = Join-Path $root 'Autologon64.exe'
if (-not (Test-Path $al)) {
  [Net.ServicePointManager]::SecurityProtocol = 'Tls12'
  Invoke-WebRequest -UseBasicParsing 'https://live.sysinternals.com/Autologon64.exe' -OutFile $al
}
$sig = Get-AuthenticodeSignature $al
if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'Microsoft') { throw "Autologon64.exe signature not valid: $($sig.Status)" }
& $al /accepteula $ReviewUser $env:COMPUTERNAME $ReviewPassword | Out-Null
$wl = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
if ($wl.AutoAdminLogon -ne '1' -or $wl.DefaultUserName -ne $ReviewUser) { throw 'auto-logon not set' }
if ($wl.PSObject.Properties.Name -contains 'DefaultPassword') { throw 'plain-text DefaultPassword present - refusing' }

# --- per-user logon task -------------------------------------------------------------------------
$start = @'
# Runs at logon as the review user. Installs Folderbird once, then keeps it running.
$exe = Join-Path $env:LOCALAPPDATA 'Programs\Folderbird\FolderbirdClient.exe'
if (-not (Test-Path $exe)) {
  [Net.ServicePointManager]::SecurityProtocol = 'Tls12'
  $setup = Join-Path $env:TEMP 'Folderbird-Setup.exe'
  Invoke-WebRequest -UseBasicParsing 'https://folderbird.com/download/windows/setup' -OutFile $setup
  $s = Get-AuthenticodeSignature $setup
  if ($s.Status -ne 'Valid' -or $s.SignerCertificate.Subject -notmatch 'Tair Foundation For CIT') { exit 2 }
  Start-Process $setup -ArgumentList '/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART' -Wait
}
if (-not (Get-Process FolderbirdClient -ErrorAction SilentlyContinue)) { Start-Process $exe }
'@
Set-Content -Path (Join-Path $root 'app-start.ps1') -Value $start -Encoding UTF8
$act  = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$root\app-start.ps1`""
$trg  = New-ScheduledTaskTrigger -AtLogOn -User $ReviewUser
$prin = New-ScheduledTaskPrincipal -UserId $ReviewUser -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName 'FolderbirdDemoStart' -Action $act -Trigger $trg -Principal $prin -Force | Out-Null

# --- never sleep ---------------------------------------------------------------------------------
powercfg /change standby-timeout-ac 0; powercfg /change hibernate-timeout-ac 0; powercfg /hibernate off
"SETUP-USER:OK autologon=$($wl.AutoAdminLogon) task=FolderbirdDemoStart"
