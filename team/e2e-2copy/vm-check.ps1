# vm-check - READ-ONLY state of the Windows test copy inside the throwaway VM fb-e2e2c-win (runs as SYSTEM through
# 'az vm run-command invoke'). Prints no secret: the token files are reported by existence, size and time only;
# Winlogon by AutoAdminLogon, DefaultUserName and whether a DefaultPassword value exists; log tails go through a
# token-shaped-string redaction. The key facts come LAST because run-command returns only the last 4 KB of stdout.
# Ends with CHECK DONE.
$ErrorActionPreference = 'Continue'
if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess -and $PSCommandPath) {
  & (Join-Path $env:windir 'sysnative\WindowsPowerShell\v1.0\powershell.exe') -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath
  exit $LASTEXITCODE
}
$Prof  = 'C:\FolderbirdE2E\profile-win'
$Files = 'C:\FolderbirdStaging\testfiles'
$User  = 'fbe2e'
function O([string]$m) { Write-Output $m }
function Red([string]$s) { [regex]::Replace($s, '-[A-Za-z0-9+/]{40,}={0,2}', '[token-redacted]') }
function Cut([string]$s) { if ($s.Length -gt 220) { $s.Substring(0, 220) + '...' } else { $s } }
function RunExe([string]$exe, [string]$argline) {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $exe; $psi.Arguments = $argline; $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
  $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
  $pr = [System.Diagnostics.Process]::Start($psi)
  $t1 = $pr.StandardOutput.ReadToEndAsync(); $t2 = $pr.StandardError.ReadToEndAsync(); $pr.WaitForExit()
  New-Object PSObject -Property @{ Code = $pr.ExitCode; Out = $t1.Result; Err = $t2.Result }
}
function Tail([string]$path, [int]$count) {
  if (Test-Path -LiteralPath $path) {
    O ('--- tail of {0}' -f $path)
    foreach ($ln in @(Get-Content -LiteralPath $path -Tail $count -ErrorAction SilentlyContinue)) { if ([string]$ln) { O (Cut (Red ([string]$ln))) } }
  } else { O ('--- {0}: absent' -f $path) }
}
if ($env:COMPUTERNAME -ne 'FB-E2E2C-WIN') { O ('CHECK FAILED: this is ' + $env:COMPUTERNAME + ', not FB-E2E2C-WIN'); exit 1 }

# ---- log tails first (they may be cut off at the top of the 4 KB) ----
Tail 'C:\FolderbirdE2E\logs\provision.log' 4
Tail 'C:\FolderbirdE2E\logs\wrapper.log' 6
Tail (Join-Path $Prof 'client-errors.log') 10
# Where an unusable FOLDERBIRD_PROFILE_DIR would have logged its refusal (the normal install's location):
Tail ('C:\Users\{0}\AppData\Local\Folderbird\client-errors.log' -f $User) 4

# ---- key facts ----
O '--- key facts'
$os = Get-CimInstance Win32_OperatingSystem
O ('host {0}; booted {1:u}; now {2:u}' -f $env:COMPUTERNAME, $os.LastBootUpTime.ToUniversalTime(), (Get-Date).ToUniversalTime())
$q = RunExe (Join-Path $env:SystemRoot 'System32\quser.exe') ''
$qtxt = (($q.Out + ' ' + $q.Err) -replace '\s+', ' ').Trim()
O ('sessions (quser, exit {0}): {1}' -f $q.Code, $qtxt)
$wl = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
O ('autologon: AutoAdminLogon={0} DefaultUserName={1} DefaultPassword present={2}' -f $wl.AutoAdminLogon, $wl.DefaultUserName, ($null -ne $wl.DefaultPassword))
$wl = $null
$ti = Get-ScheduledTask -TaskName 'FolderbirdE2ECopy' -ErrorAction SilentlyContinue
if ($ti) {
  $tinfo = Get-ScheduledTaskInfo -TaskName 'FolderbirdE2ECopy'
  O ('task FolderbirdE2ECopy: {0}, last run {1:u}, last result 0x{2:X}' -f $ti.State, $tinfo.LastRunTime, $tinfo.LastTaskResult)
} else { O 'task FolderbirdE2ECopy: MISSING' }
$wrap = @(Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'powershell.exe' -and ([string]$_.CommandLine) -like '*run-e2e-copy.ps1*' })
O ('wrapper processes: {0} (sessions {1})' -f $wrap.Count, (($wrap | ForEach-Object { $_.SessionId }) -join ','))
$apps = @(Get-CimInstance Win32_Process -Filter "Name='FolderbirdClient.exe'")
if ($apps.Count -eq 0) { O 'FolderbirdClient: NOT RUNNING' }
foreach ($ap in $apps) {
  $ow = Invoke-CimMethod -InputObject $ap -MethodName GetOwner
  O ('FolderbirdClient pid {0}: session {1}, owner {2}\{3}, started {4:u}, path {5}, args {6}' -f $ap.ProcessId, $ap.SessionId, $ow.Domain, $ow.User, $ap.CreationDate.ToUniversalTime(), $ap.ExecutablePath, ([string]$ap.CommandLine -replace '^.*FolderbirdClient\.exe"?\s*', ''))
}
$ht = Join-Path $Prof 'host.txt'; $hd = Join-Path $Prof 'host.dat'
$hdi = Get-Item -LiteralPath $hd -ErrorAction SilentlyContinue
O ('token files: host.txt present={0}; host.dat present={1}{2}' -f (Test-Path -LiteralPath $ht), [bool]$hdi, $(if ($hdi) { ' ({0} bytes, written {1:u})' -f $hdi.Length, $hdi.LastWriteTimeUtc } else { '' }))
$pf = @()
foreach ($nm in 'base-url.txt', 'device-name.txt', 'address.txt', 'user.txt') {
  $fp = Join-Path $Prof $nm
  if (Test-Path -LiteralPath $fp) { $pf += ('{0}={1}' -f $nm, ([IO.File]::ReadAllText($fp)).Trim()) } else { $pf += ($nm + '=MISSING') }
}
O ('profile: ' + ($pf -join '; '))
try {
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  $h = Invoke-WebRequest -UseBasicParsing -TimeoutSec 30 -Uri 'https://folderbird-app-staging.azurewebsites.net/healthz/ready'
  O ('staging /healthz/ready from the VM: HTTP {0}, {1}' -f $h.StatusCode, (Cut ([string]$h.Content)))
} catch { O ('staging /healthz/ready from the VM: ' + $_.Exception.Message) }
foreach ($fi in @(Get-ChildItem -LiteralPath $Files -File -ErrorAction SilentlyContinue)) {
  O ('HASH {0} {1} {2}' -f $fi.Name, $fi.Length, (Get-FileHash -LiteralPath $fi.FullName -Algorithm SHA256).Hash.ToLowerInvariant())
}
$ok = ($apps.Count -ge 1) -and (-not (Test-Path -LiteralPath $ht)) -and [bool]$hdi
O ('VERDICT: {0}' -f $(if ($ok) { 'app running, token migrated to host.dat (look for E2E2C-WIN online on staging)' } else { 'NOT READY - see the lines above' }))
O 'CHECK DONE'
