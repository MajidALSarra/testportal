# Runs INSIDE the reviewer demo VM as SYSTEM (managed run-command), ONCE, before any reviewer has access.
# NEVER re-run it (or any vm\*.ps1) as SYSTEM after reviewers have had a shell: they can plant files and
# junctions where SYSTEM works. Rebuild the VM instead.
#  0. A STANDARD local user runs the Folderbird app (reviewers get a shell through the exec scope).
#     The built-in admin account is disabled; admin work goes through run-command as SYSTEM.
#  1. Auto-logon via Sysinternals Autologon (LSA secret, never a plain-text registry value) plus
#     ForceAutoLogon, so a 'logoff' by a reviewer logs the user straight back on.
#  2. A task for the user, at logon and every 5 minutes, that installs Folderbird (signer checked) and
#     starts it when it is not running.
#  3. No sleep, no hibernate.
# The password arrives base64-encoded as a PROTECTED parameter, so no character can be mangled on the way.
param([Parameter(Mandatory)][string]$ReviewUser, [Parameter(Mandatory)][string]$ReviewPasswordB64,
      [string]$AdminUser = 'fbadmin')
$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue'
$pw = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($ReviewPasswordB64))
$root = 'C:\ProgramData\FolderbirdDemo'
New-Item -ItemType Directory -Force -Path $root | Out-Null
# ProgramData lets Users create files in new subfolders; this folder must be SYSTEM/Administrators-only for writes.
icacls $root /inheritance:r /grant:r 'SYSTEM:(OI)(CI)F' 'Administrators:(OI)(CI)F' 'Users:(OI)(CI)RX' | Out-Null

function SignerIs($file, $cn, $issuerLike) {
  $s = Get-AuthenticodeSignature $file
  if ($s.Status -ne 'Valid') { return $false }
  $c = $s.SignerCertificate
  ($c.GetNameInfo('SimpleName', $false) -eq $cn) -and ($c.GetNameInfo('SimpleName', $true) -like $issuerLike)
}

# --- standard user ------------------------------------------------------------------------------
$sec = ConvertTo-SecureString $pw -AsPlainText -Force
if (Get-LocalUser -Name $ReviewUser -ErrorAction SilentlyContinue) { Set-LocalUser -Name $ReviewUser -Password $sec -PasswordNeverExpires $true }
else { New-LocalUser -Name $ReviewUser -Password $sec -PasswordNeverExpires -UserMayNotChangePassword -FullName 'Demo User' | Out-Null }
Add-LocalGroupMember -Group 'Users' -Member $ReviewUser -ErrorAction SilentlyContinue
Add-LocalGroupMember -Group 'Remote Desktop Users' -Member $ReviewUser -ErrorAction SilentlyContinue   # Bastion sign-in
if (Get-LocalGroupMember -Group 'Administrators' | Where-Object Name -like "*\$ReviewUser") { throw "$ReviewUser must not be an administrator" }

# --- auto-logon ---------------------------------------------------------------------------------
$al = Join-Path $root 'Autologon64.exe'
[Net.ServicePointManager]::SecurityProtocol = 'Tls12'
Invoke-WebRequest -UseBasicParsing 'https://live.sysinternals.com/Autologon64.exe' -OutFile $al
try {
  if (-not (SignerIs $al 'Microsoft Corporation' 'Microsoft Code Signing PCA*')) { throw 'Autologon64.exe is not signed by Microsoft' }
  & $al /accepteula $ReviewUser $env:COMPUTERNAME $pw | Out-Null
} finally { Remove-Item $al -Force -ErrorAction SilentlyContinue }
$pw = $null; $sec = $null
$wlKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
Set-ItemProperty $wlKey -Name ForceAutoLogon -Value '1' -Type String
$wl = Get-ItemProperty $wlKey
if ($wl.AutoAdminLogon -ne '1' -or $wl.ForceAutoLogon -ne '1' -or $wl.DefaultUserName -ne $ReviewUser) { throw 'auto-logon not set' }
if ($wl.PSObject.Properties.Name -contains 'DefaultPassword') { throw 'plain-text DefaultPassword present - refusing' }

# --- the admin account is not needed: run-command as SYSTEM is the admin path ---------------------
Disable-LocalUser -Name $AdminUser

# --- per-user task: install once, keep running ------------------------------------------------------
$start = @'
# Runs as the review user at logon and every 5 minutes. Installs Folderbird once, then keeps it running.
$log = Join-Path $env:LOCALAPPDATA 'FolderbirdDemo'; New-Item -ItemType Directory -Force -Path $log | Out-Null
Start-Transcript -Path (Join-Path $log 'app-start.log') -Append | Out-Null
try {
  $exe = Join-Path $env:LOCALAPPDATA 'Programs\Folderbird\FolderbirdClient.exe'
  if (-not (Test-Path $exe)) {
    [Net.ServicePointManager]::SecurityProtocol = 'Tls12'
    $setup = Join-Path $env:TEMP 'Folderbird-Setup.exe'
    for ($i = 1; $i -le 5 -and -not (Test-Path $setup); $i++) {
      try { Invoke-WebRequest -UseBasicParsing 'https://folderbird.com/download/windows/setup' -OutFile $setup }
      catch { "download try $i failed: $_"; Start-Sleep -Seconds 30 }
    }
    $s = Get-AuthenticodeSignature $setup
    if ($s.Status -ne 'Valid' -or $s.SignerCertificate.GetNameInfo('SimpleName', $false) -ne 'Tair Foundation For CIT') {
      "installer signature not accepted: $($s.Status)"; Remove-Item $setup -Force; exit 2 }
    Start-Process $setup -ArgumentList '/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART' -Wait
    Remove-Item $setup -Force
  }
  if (-not (Get-Process FolderbirdClient -ErrorAction SilentlyContinue)) { Start-Process $exe; 'started FolderbirdClient' }
} finally { Stop-Transcript | Out-Null }
'@
Set-Content -Path (Join-Path $root 'app-start.ps1') -Value $start -Encoding ASCII
$act  = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$root\app-start.ps1`""
$t1   = New-ScheduledTaskTrigger -AtLogOn -User $ReviewUser
$t2   = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 5)
$prin = New-ScheduledTaskPrincipal -UserId $ReviewUser -LogonType Interactive -RunLevel Limited
$set  = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 20)
Register-ScheduledTask -TaskName 'FolderbirdDemoStart' -Action $act -Trigger $t1,$t2 -Principal $prin -Settings $set -Force | Out-Null

# --- never sleep ---------------------------------------------------------------------------------
powercfg /change standby-timeout-ac 0; powercfg /change hibernate-timeout-ac 0; powercfg /hibernate off
"SETUP-USER:OK autologon=$($wl.AutoAdminLogon) force=$($wl.ForceAutoLogon) admin-disabled task=FolderbirdDemoStart"
