# vm-provision - runs INSIDE the throwaway VM fb-e2e2c-win as SYSTEM ('az vm run-command invoke', RunPowerShellScript).
# Built from vm-provision.template.ps1 by v2-vm-provision.ps1; only the e2e email (not a secret) is filled in.
# What it does, all idempotent:
#  1. downloads the PUBLIC signed Windows zip (https://folderbird.com/download/windows, read-only GET; if that request
#     fails, the staging slot's own /download/windows, which serves the same blob) and requires 863,864 bytes and
#     SHA-256 28E3BFF9...029285 (folderbird-web 91de08d Controllers/DownloadController.cs:44-46);
#  2. unpacks it to C:\FolderbirdE2E\app-1.2.8.1, requires both exes to match the zip, Authenticode Valid, signer
#     "Tair Foundation For CIT", a timestamp, and FolderbirdClient.exe FileVersion 1.2.8.1;
#  3. creates the local NON-admin user fbe2e with a random password generated HERE, which goes only into this VM's
#     Winlogon autologon values (AutoAdminLogon) so a real desktop session exists after a reboot - the tray app needs
#     one. The password is never printed, logged or sent anywhere. If the user and autologon already exist the
#     password is left alone (an admin reset would make the user's DPAPI-protected host.dat unreadable);
#  4. writes the test profile C:\FolderbirdE2E\profile-win (base-url.txt, device-name.txt, address.txt, user.txt,
#     each without a trailing newline) and gives fbe2e Modify on it;
#  5. creates C:\FolderbirdStaging\testfiles\random-24mb.bin (25,165,824 random bytes) and e2e-note.txt and prints
#     their SHA-256;
#  6. writes the wrapper C:\FolderbirdE2E\run-e2e-copy.ps1 (sets FOLDERBIRD_PROFILE_DIR for its own process only and
#     keeps FolderbirdClient.exe /startup running) and registers the logon task FolderbirdE2ECopy (user fbe2e,
#     interactive, limited, no time limit, normal priority).
# It does NOT reboot: t-device-token.ps1 -Device win (laptop) gets the token, v4-vm-token.ps1 writes it and restarts
# the VM.
# Prints PROVISION DONE, or PROVISION FAILED line N: message. Full log inside the VM: C:\FolderbirdE2E\logs\provision.log
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
# A 32-bit host would write the 32-bit registry view and may lack the LocalAccounts module: rerun in 64-bit.
if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
  if (-not $PSCommandPath) { Write-Output 'PROVISION FAILED line 0: 32-bit PowerShell and no script path to relaunch'; exit 1 }
  & (Join-Path $env:windir 'sysnative\WindowsPowerShell\v1.0\powershell.exe') -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath
  exit $LASTEXITCODE
}
$Root    = 'C:\FolderbirdE2E'
$App     = 'C:\FolderbirdE2E\app-1.2.8.1'
$Prof    = 'C:\FolderbirdE2E\profile-win'
$Logs    = 'C:\FolderbirdE2E\logs'
$Zip     = 'C:\FolderbirdE2E\Folderbird-Windows-1.2.8.1.zip'
$Stage   = 'C:\FolderbirdStaging'
$Files   = 'C:\FolderbirdStaging\testfiles'
$Wrapper = 'C:\FolderbirdE2E\run-e2e-copy.ps1'
$User    = 'fbe2e'
$TaskN   = 'FolderbirdE2ECopy'
$DlUrl   = 'https://folderbird.com/download/windows'
$ZipLen  = 863864
$ZipSha  = '28E3BFF9F2E9560459A7E936579473409A9ACAAB5D52A7CA678717C511029285'
$Base    = 'https://folderbird-app-staging.azurewebsites.net'
$DevName = 'E2E2C-WIN'
$Addr    = '02E2E2C00002'
$Email   = '__EMAIL__'
$PLOG    = 'C:\FolderbirdE2E\logs\provision.log'
$Ascii   = New-Object System.Text.ASCIIEncoding
$Rng     = [Security.Cryptography.RandomNumberGenerator]::Create()
function L([string]$m) {
  $s = '{0:u} {1}' -f (Get-Date).ToUniversalTime(), $m
  Write-Output $s
  try { Add-Content -LiteralPath $PLOG -Value $s } catch { }
}
# Native programs through .NET, so their stderr is read as text and can never become a PowerShell error record.
function RunExe([string]$exe, [string]$argline) {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $exe; $psi.Arguments = $argline; $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
  $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
  $pr = [System.Diagnostics.Process]::Start($psi)
  $t1 = $pr.StandardOutput.ReadToEndAsync(); $t2 = $pr.StandardError.ReadToEndAsync(); $pr.WaitForExit()
  New-Object PSObject -Property @{ Code = $pr.ExitCode; Out = $t1.Result; Err = $t2.Result }
}
function Grant([string]$path, [string]$acct, [string]$perm) {
  $r = RunExe (Join-Path $env:SystemRoot 'System32\icacls.exe') ('"{0}" /grant "{1}:{2}"' -f $path, $acct, $perm)
  if ($r.Code -ne 0) { throw ('icacls {0} failed: {1} {2}' -f $path, $r.Out.Trim(), $r.Err.Trim()) }
}
try {
  if ($env:COMPUTERNAME -ne 'FB-E2E2C-WIN') { throw ('refusing to run on ' + $env:COMPUTERNAME + ': this script is only for the throwaway VM FB-E2E2C-WIN') }
  if ($Email -notmatch '^[A-Za-z0-9._+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$') { throw 'the e2e email placeholder was not filled in' }
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  foreach ($dir in $Root, $App, $Prof, $Logs, $Stage, $Files) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  L ('provision start on {0} as {1}, PowerShell {2}, 64-bit {3}' -f $env:COMPUTERNAME, [Security.Principal.WindowsIdentity]::GetCurrent().Name, $PSVersionTable.PSVersion, [Environment]::Is64BitProcess)
  $free = (Get-PSDrive C).Free
  if ($free -lt 3GB) { throw ('only {0:N1} GB free on C:' -f ($free / 1GB)) }

  # ---- 1. the published signed zip ----
  $zipOk = $false
  if (Test-Path -LiteralPath $Zip) {
    $zipOk = ((Get-Item -LiteralPath $Zip).Length -eq $ZipLen) -and ((Get-FileHash -LiteralPath $Zip -Algorithm SHA256).Hash -eq $ZipSha)
    if (-not $zipOk) { Remove-Item -LiteralPath $Zip -Force }
  }
  # The public download first; if that request fails, the staging slot's /download/windows (same controller, same
  # private 'releases' blob). The hash check decides either way.
  foreach ($u in $DlUrl, ($Base + '/download/windows')) {
    if ($zipOk) { break }
    try { Invoke-WebRequest -UseBasicParsing -Uri $u -OutFile $Zip -TimeoutSec 600 }
    catch { L ('download from {0} failed: {1}' -f $u, $_.Exception.Message); continue }
    $len = (Get-Item -LiteralPath $Zip).Length; $sha = (Get-FileHash -LiteralPath $Zip -Algorithm SHA256).Hash
    if ($len -eq $ZipLen -and $sha -eq $ZipSha) { $zipOk = $true; L ('downloaded from ' + $u) }
    else { Remove-Item -LiteralPath $Zip -Force; L ('{0} served {1} bytes, sha256 {2} - not the published 1.2.8.1 zip, discarded' -f $u, $len, $sha) }
  }
  if (-not $zipOk) { throw 'could not get the published 1.2.8.1 zip (863864 bytes, sha256 28E3BFF9...029285)' }
  L ('zip ok: {0} bytes, sha256 {1}' -f $ZipLen, $ZipSha)

  # ---- 2. unpack and verify ----
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $want = @{}
  $za = [IO.Compression.ZipFile]::OpenRead($Zip)
  try {
    foreach ($en in $za.Entries) {
      if ($en.FullName -eq 'FolderbirdClient.exe' -or $en.FullName -eq 'Updater.exe') {
        $es = $en.Open()
        try { $h = [Security.Cryptography.SHA256]::Create(); $want[$en.FullName] = ([BitConverter]::ToString($h.ComputeHash($es))).Replace('-', '') }
        finally { $es.Dispose() }
      }
    }
  } finally { $za.Dispose() }
  foreach ($n in 'FolderbirdClient.exe', 'Updater.exe') { if (-not $want.ContainsKey($n)) { throw ('the zip has no root entry ' + $n) } }
  $need = $false
  foreach ($n in 'FolderbirdClient.exe', 'Updater.exe') {
    $p = Join-Path $App $n
    if (-not (Test-Path -LiteralPath $p)) { $need = $true } elseif ((Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash -ne $want[$n]) { $need = $true }
  }
  if ($need) {
    if (Get-Process -Name FolderbirdClient -ErrorAction SilentlyContinue) { throw 'FolderbirdClient is running and its files differ from the zip - stop it first' }
    Expand-Archive -LiteralPath $Zip -DestinationPath $App -Force
    L ('unpacked to ' + $App)
  }
  Get-ChildItem -LiteralPath $App -Recurse -File | Unblock-File
  foreach ($n in 'FolderbirdClient.exe', 'Updater.exe') {
    $p = Join-Path $App $n
    $h = (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash
    if ($h -ne $want[$n]) { throw ($n + ' on disk does not match the zip') }
    $s = Get-AuthenticodeSignature -LiteralPath $p
    if ($s.Status -ne 'Valid') { throw ('{0}: Authenticode status {1}' -f $n, $s.Status) }
    if ($s.SignerCertificate.Subject -notmatch 'Tair Foundation For CIT') { throw ('{0}: unexpected signer {1}' -f $n, $s.SignerCertificate.Subject) }
    if (-not $s.TimeStamperCertificate) { throw ($n + ' has no timestamp countersignature') }
    L ('{0}: v{1}, {2}, signer Tair Foundation For CIT, timestamped, sha256 {3}' -f $n, (Get-Item -LiteralPath $p).VersionInfo.FileVersion, $s.Status, $h)
  }
  $fv = (Get-Item -LiteralPath (Join-Path $App 'FolderbirdClient.exe')).VersionInfo.FileVersion
  if ($fv -ne '1.2.8.1') { throw ('FolderbirdClient.exe FileVersion is ' + $fv + ', not 1.2.8.1') }

  # ---- 3. the autologon user (non-admin) ----
  $Acct = $env:COMPUTERNAME + '\' + $User
  $wl = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
  $cur = Get-ItemProperty -LiteralPath $wl
  $haveAuto = ([string]$cur.AutoAdminLogon -eq '1') -and ([string]$cur.DefaultUserName -eq $User) -and ($null -ne $cur.DefaultPassword)
  $cur = $null
  $lu = Get-LocalUser -Name $User -ErrorAction SilentlyContinue
  if ($lu -and $haveAuto) {
    L ('user {0} and its autologon already exist - password left unchanged' -f $Acct)
  } else {
    $cs = [char[]]'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!#%-_.'
    $b = New-Object byte[] 24
    do { $Rng.GetBytes($b); $pw = -join ($b | ForEach-Object { $cs[$_ % $cs.Length] }) }
    until ($pw -cmatch '[A-Z]' -and $pw -cmatch '[a-z]' -and $pw -match '[0-9]' -and $pw -match '[!#%._-]')
    $sec = ConvertTo-SecureString -String $pw -AsPlainText -Force
    if ($lu) {
      Set-LocalUser -Name $User -Password $sec -PasswordNeverExpires $true
      L ('user {0} existed without autologon: password reset (a token injected before this is unreadable now - run v4 again)' -f $Acct)
    } else {
      New-LocalUser -Name $User -Password $sec -PasswordNeverExpires -AccountNeverExpires -FullName 'Folderbird e2e test copy' -Description 'Folderbird e2e autologon user' | Out-Null
      L ('user {0} created (not an administrator)' -f $Acct)
    }
    New-ItemProperty -LiteralPath $wl -Name DefaultPassword -Value $pw -PropertyType String -Force | Out-Null
    $pw = $null; $sec = $null; $b = $null
    New-ItemProperty -LiteralPath $wl -Name AutoAdminLogon -Value '1' -PropertyType String -Force | Out-Null
    New-ItemProperty -LiteralPath $wl -Name DefaultUserName -Value $User -PropertyType String -Force | Out-Null
    New-ItemProperty -LiteralPath $wl -Name DefaultDomainName -Value $env:COMPUTERNAME -PropertyType String -Force | Out-Null
    Remove-ItemProperty -LiteralPath $wl -Name AutoLogonCount -ErrorAction SilentlyContinue
    L ('autologon set for {0} (24 random chars, kept only in this VM''s Winlogon key)' -f $Acct)
  }
  if (-not (Get-LocalUser -Name $User).Enabled) { Enable-LocalUser -Name $User; L ('user {0} enabled' -f $User) }
  try { Add-LocalGroupMember -SID 'S-1-5-32-545' -Member $User; L ('{0} added to Users' -f $User) }
  catch { if ($_.FullyQualifiedErrorId -notlike 'MemberExists*') { throw } }
  # A logon notice would stop autologon at a dialog nobody can click.
  $polk = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
  $pol = Get-ItemProperty -LiteralPath $polk -ErrorAction SilentlyContinue
  foreach ($nm in 'LegalNoticeCaption', 'LegalNoticeText') {
    if ($pol -and [string]$pol.$nm) { Set-ItemProperty -LiteralPath $polk -Name $nm -Value ''; L ('cleared ' + $nm + ' (it would block autologon)') }
  }

  # ---- 4. the test profile (no trailing newlines) ----
  [IO.File]::WriteAllText((Join-Path $Prof 'base-url.txt'), $Base, $Ascii)       # the app appends /api
  [IO.File]::WriteAllText((Join-Path $Prof 'device-name.txt'), $DevName, $Ascii)
  [IO.File]::WriteAllText((Join-Path $Prof 'address.txt'), $Addr, $Ascii)
  [IO.File]::WriteAllText((Join-Path $Prof 'user.txt'), $Email, $Ascii)
  Grant $Prof $Acct '(OI)(CI)M'
  Grant $Logs $Acct '(OI)(CI)M'
  L ('profile {0}: base-url {1}, device-name {2}, address {3}, user {4}; {5} has Modify' -f $Prof, $Base, $DevName, $Addr, $Email, $Acct)

  # ---- 5. test files (the workflows' default folder) ----
  Grant $Stage $Acct '(OI)(CI)M'
  $bin = Join-Path $Files 'random-24mb.bin'
  $binOk = $false
  if (Test-Path -LiteralPath $bin) { $binOk = ((Get-Item -LiteralPath $bin).Length -eq 25165824) }
  if (-not $binOk) {
    $buf = New-Object byte[] 25165824; $Rng.GetBytes($buf); [IO.File]::WriteAllBytes($bin, $buf); $buf = $null
    L 'random-24mb.bin written'
  }
  # ~300 MB file for Falcon's restart ("holder dies") test; written in 4 MB chunks to keep memory low.
  $big = Join-Path $Files 'random-300mb.bin'
  $bigOk = $false
  if (Test-Path -LiteralPath $big) { $bigOk = ((Get-Item -LiteralPath $big).Length -eq 314572800) }
  if (-not $bigOk) {
    $chunk = New-Object byte[] 4194304
    $fs = [IO.File]::Open($big, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { for ($i = 0; $i -lt 75; $i++) { $Rng.GetBytes($chunk); $fs.Write($chunk, 0, $chunk.Length) } } finally { $fs.Dispose() }
    $chunk = $null
    L 'random-300mb.bin written'
  }
  $txt = Join-Path $Files 'e2e-note.txt'
  if (-not (Test-Path -LiteralPath $txt)) { [IO.File]::WriteAllText($txt, "Folderbird two-copy test note`r`n", $Ascii); L 'e2e-note.txt written' }

  # ---- 6. wrapper + logon task ----
  $wtext = @'
# run-e2e-copy.ps1 - started at logon of fbe2e by the task FolderbirdE2ECopy, in the autologon desktop session.
# Sets FOLDERBIRD_PROFILE_DIR for THIS process and the app it starts only (a persistent value would also switch a
# normal install into profile mode), then keeps one copy of the app running. No secrets in here.
$ErrorActionPreference = 'Continue'
$env:FOLDERBIRD_PROFILE_DIR = 'C:\FolderbirdE2E\profile-win'
$exe  = 'C:\FolderbirdE2E\app-1.2.8.1\FolderbirdClient.exe'
$wd   = 'C:\FolderbirdE2E\app-1.2.8.1'
$wlog = 'C:\FolderbirdE2E\logs\wrapper.log'
function W([string]$m) { try { Add-Content -LiteralPath $wlog -Value ('{0:u} {1}' -f (Get-Date).ToUniversalTime(), $m) } catch { } }
W ('wrapper started as {0} in session {1}' -f $env:USERNAME, [Diagnostics.Process]::GetCurrentProcess().SessionId)
for ($n = 1; $n -le 500; $n++) {
  try {
    $p = Start-Process -FilePath $exe -ArgumentList '/startup' -WorkingDirectory $wd -PassThru
    [void]$p.Handle
    W ('started FolderbirdClient pid {0} (start {1})' -f $p.Id, $n)
    $p.WaitForExit()
    W ('FolderbirdClient pid {0} exited with code {1}; starting it again in 30 s' -f $p.Id, $p.ExitCode)
  } catch { W ('start failed: ' + $_.Exception.Message + '; retrying in 30 s') }
  Start-Sleep -Seconds 30
}
W 'wrapper stopped after 500 starts'
'@
  [IO.File]::WriteAllText($Wrapper, $wtext, $Ascii)
  $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
  $act = New-ScheduledTaskAction -Execute $ps -Argument ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $Wrapper + '"') -WorkingDirectory $App
  $trg = New-ScheduledTaskTrigger -AtLogOn -User $Acct
  $trg.Delay = 'PT20S'
  $prn = New-ScheduledTaskPrincipal -UserId $Acct -LogonType Interactive -RunLevel Limited
  # Priority 5 = normal (the default 7 is below normal, and the app would inherit it); no 72-hour time limit.
  $set = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -Priority 5 -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
  Register-ScheduledTask -TaskName $TaskN -Action $act -Trigger $trg -Principal $prn -Settings $set -Force | Out-Null
  $ti = Get-ScheduledTask -TaskName $TaskN
  L ('task {0}: {1}, runs as {2} ({3}, {4}), at logon of {5}' -f $TaskN, $ti.State, $ti.Principal.UserId, $ti.Principal.LogonType, $ti.Principal.RunLevel, $Acct)

  # ---- summary (kept last: run-command returns only the last 4 KB of stdout) ----
  foreach ($fi in Get-ChildItem -LiteralPath $Files -File) {
    $hl = 'HASH {0} {1} {2}' -f $fi.Name, $fi.Length, (Get-FileHash -LiteralPath $fi.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    Write-Output $hl
    try { Add-Content -LiteralPath $PLOG -Value $hl } catch { }
  }
  L 'PROVISION DONE (no reboot: v4-vm-token.ps1 writes the token, then restarts the VM so autologon starts the app)'
} catch {
  $msg = 'PROVISION FAILED line {0}: {1}' -f $_.InvocationInfo.ScriptLineNumber, $_.Exception.Message
  Write-Output $msg
  try { Add-Content -LiteralPath $PLOG -Value $msg } catch { }
  exit 1
}
