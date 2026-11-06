# V5 - READ-ONLY: the state of the Windows test copy inside fb-e2e2c-win (vm-check.ps1 through run-command) and, when
# apikey.txt holds a key, how staging lists the e2e devices (GET /api/v1/devices; the key goes only in the
# Authorization header). Retries the run-command up to 4 times, 60 s apart (the VM agent is slow after a restart).
# Run detached about 3 minutes after V4:
#   Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','C:\Temp\e2e\v5-vm-check.ps1'
$NAME = 'v5-vm-check'
# ---- common block: the SAME text in every laptop script (generated; change all copies together) ----
# Rules it enforces: az and gh run through RunExe (no shell, every argument quoted for the C runtime, stdin closed so a
# prompt fails at once instead of waiting forever, UTF-8 output, the REAL exit code, a time limit). Native stderr never
# becomes a PowerShell error record. Each script has its OWN .err file, so two scripts never share one. Every log line
# and every stderr line goes through Red, which removes the secrets this script has read.
$ErrorActionPreference = 'Stop'
$D       = 'C:\Temp\e2e'
$LOG     = Join-Path $D ($NAME + '.log')
$ERRF    = Join-Path $D ($NAME + '.err')
$PY      = 'C:\Program Files\Microsoft SDKs\Azure\CLI2\python.exe'
$STAGING = 'https://folderbird-app-staging.azurewebsites.net'
$REPO    = 'MajidALSarra/folderbird-web'
$RG      = 'folderbird-e2e-rg'
$script:SECRETS = @()
$script:REDACT_TOKENS = $false
$script:AZRC = -1
$env:AZURE_EXTENSION_USE_DYNAMIC_INSTALL = 'yes_without_prompt'
$env:AZURE_CORE_COLLECT_TELEMETRY = 'false'
$env:AZURE_CORE_NO_COLOR = 'true'
$env:PYTHONIOENCODING = 'utf-8'
$env:GH_PROMPT_DISABLED = '1'
$env:NO_COLOR = '1'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
[Net.ServicePointManager]::Expect100Continue = $false
New-Item -ItemType Directory -Force -Path $D | Out-Null

function Red([string]$s) {
  if (-not $s) { return '' }
  foreach ($x in $script:SECRETS) { if ($x -and $x.Length -ge 8) { $s = $s.Replace($x, '[redacted]') } }
  $s = [regex]::Replace($s, 'fbk_live_[A-Za-z0-9_-]{43}', '[key-redacted]')
  if ($script:REDACT_TOKENS) { $s = [regex]::Replace($s, '-[A-Za-z0-9+/]{40,}={0,2}', '[token-redacted]') }
  return $s
}
function L([string]$m) { Add-Content -LiteralPath $LOG -Value ('{0:u} {1}' -f (Get-Date).ToUniversalTime(), (Red $m)) }
# The catch of every script: the real cause (not "One or more errors occurred") plus the script stack.
function Fail($er) {
  L ('FAILED line {0}: {1}' -f $er.InvocationInfo.ScriptLineNumber, $er.Exception.GetBaseException().Message)
  L ('  stack: ' + (($er.ScriptStackTrace -split "`r?`n") -join ' <- '))
  exit 1
}
# One argument quoted the way the C runtime (python.exe, gh.exe, icacls.exe) splits a command line again.
function QArg([string]$a) {
  if ($a.Length -gt 0 -and $a -notmatch '[\s"]') { return $a }
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.Append('"')
  $bs = 0
  foreach ($ch in $a.ToCharArray()) {
    if ($ch -eq [char]92) { $bs++; continue }
    if ($ch -eq [char]34) { [void]$sb.Append([string]::new([char]92, 2 * $bs + 1)); [void]$sb.Append([char]34); $bs = 0; continue }
    if ($bs -gt 0) { [void]$sb.Append([string]::new([char]92, $bs)); $bs = 0 }
    [void]$sb.Append($ch)
  }
  if ($bs -gt 0) { [void]$sb.Append([string]::new([char]92, 2 * $bs)) }
  [void]$sb.Append('"')
  return $sb.ToString()
}
# Throws only when the program cannot start or runs past the limit; a non-zero exit is returned in .Code.
function RunExe([string]$exe, [string[]]$argv, [byte[]]$feed, [int]$limitSec) {
  if ($limitSec -le 0) { $limitSec = 3600 }
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $exe
  $psi.Arguments = (@($argv | ForEach-Object { QArg ([string]$_) }) -join ' ')
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $psi.RedirectStandardInput = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $utf8 = New-Object System.Text.UTF8Encoding($false)
  $psi.StandardOutputEncoding = $utf8
  $psi.StandardErrorEncoding = $utf8
  $pr = [System.Diagnostics.Process]::Start($psi)
  $t1 = $pr.StandardOutput.ReadToEndAsync()
  $t2 = $pr.StandardError.ReadToEndAsync()
  if ($feed) { $pr.StandardInput.BaseStream.Write($feed, 0, $feed.Length); $pr.StandardInput.BaseStream.Flush() }
  $pr.StandardInput.Close()
  if (-not $pr.WaitForExit($limitSec * 1000)) {
    try { $pr.Kill() } catch { }
    throw ('{0} did not finish within {1} s and was stopped' -f [IO.Path]::GetFileName($exe), $limitSec)
  }
  $pr.WaitForExit()
  return New-Object PSObject -Property @{ Code = $pr.ExitCode; Out = [string]$t1.Result; Err = [string]$t2.Result }
}
# az through the CLI's own python (az.cmd is broken on the laptop). NO param block on purpose: every token reaches az
# verbatim through $args. $AZRC is the real exit code, -1 when az could not run. Returns the non-empty stdout lines.
function AZ {
  $script:AZRC = -1
  $what = (@($args) | Select-Object -First 3) -join ' '
  $r = RunExe $PY (@('-m', 'azure.cli') + @($args)) $null 3600
  $script:AZRC = $r.Code
  if ($r.Err.Trim()) {
    [IO.File]::AppendAllText($ERRF, ('{0:u} az {1} ... (exit {2})' -f (Get-Date).ToUniversalTime(), $what, $r.Code) + "`r`n" + (Red $r.Err) + "`r`n")
  }
  return @($r.Out -split "`r?`n" | Where-Object { $_.Trim() -ne '' })
}
function GhPath {
  $g = Get-Command gh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($g) { return $g.Path }
  foreach ($p in @((Join-Path $env:ProgramFiles 'GitHub CLI\gh.exe'), (Join-Path $env:LOCALAPPDATA 'Programs\GitHub CLI\gh.exe'))) {
    if (Test-Path -LiteralPath $p) { return $p }
  }
  return $null
}
function MySid { return [Security.Principal.WindowsIdentity]::GetCurrent().User.Value }
# Every script that reads or writes a secret first proves C:\Temp\e2e is closed to everyone but this user and SYSTEM.
function CheckLock {
  $me = MySid
  $acl = Get-Acl -LiteralPath $D
  $other = @($acl.Access | Where-Object { $_.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value -notin @($me, 'S-1-5-18') })
  if (-not $acl.AreAccessRulesProtected -or $other.Count -gt 0) {
    throw ('{0} is not locked down (inheritance off: {1}; other entries: {2}) - run a1-account.ps1 first' -f $D, $acl.AreAccessRulesProtected, $other.Count)
  }
}
function ReadEmail {
  $e = [IO.File]::ReadAllText((Join-Path $D 'email.txt')).Trim()
  if ($e -notmatch '^e2e-2copy[a-z0-9-]*@folderbird\.com$') { throw 'email.txt is not an e2e-2copy...@folderbird.com address' }
  return $e
}
# Reads a secret file, checks its shape, adds it to the redaction list. Never logs the value.
function ReadSecret([string]$file, [string]$shape) {
  $p = Join-Path $D $file
  if (-not (Test-Path -LiteralPath $p)) { throw ($file + ' is missing') }
  $v = [IO.File]::ReadAllText($p).Trim()
  if (-not $v) { throw ($file + ' is empty (already used or blanked)') }
  if ($v -notmatch $shape) { throw ($file + ' does not have the expected shape (value not shown)') }
  $script:SECRETS += $v
  return $v
}
# The account must hold pw.txt (b0 done) before anything signs in with it.
function RequireB0 {
  $b = Join-Path $D 'bootstrap.txt'
  if ((Test-Path -LiteralPath $b) -and [IO.File]::ReadAllText($b).Trim()) { throw 'bootstrap.txt still holds a value - run b0-set-password.ps1 first' }
}
function NewPw([int]$n) {
  $cs = [char[]]'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789'
  $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
  $b = New-Object byte[] $n
  do { $rng.GetBytes($b); $p = -join ($b | ForEach-Object { $cs[$_ % $cs.Length] }) }
  until ($p -cmatch '[A-Z]' -and $p -cmatch '[a-z]' -and $p -match '[0-9]')
  return $p
}
# The e2e resource group: created with the e2e tag, or accepted only if it already carries it.
function EnsureRg {
  $ex = (@(AZ group exists -n $RG) -join '').Trim()
  if ($script:AZRC -ne 0) { throw ('az group exists failed ({0}) - see {1}' -f $script:AZRC, $ERRF) }
  if ($ex -eq 'true') {
    $tag = (@(AZ group show -n $RG --query tags.purpose -o tsv) -join '').Trim()
    if ($tag -ne 'e2e-2copy') { throw ("resource group $RG exists but is tagged purpose='$tag', not e2e-2copy - refusing") }
    L "resource group $RG exists, purpose=e2e-2copy"
  } else {
    AZ group create -n $RG -l westeurope --tags purpose=e2e-2copy owner=coordinator -o none | Out-Null
    if ($script:AZRC -ne 0) { throw ('group create failed ({0}) - see {1}' -f $script:AZRC, $ERRF) }
    L "resource group $RG created (westeurope, purpose=e2e-2copy)"
  }
}
# The SITE-WIDE sticky (slot-setting) app-setting names of folderbird-app. Production and staging share this ONE list,
# so nothing in this procedure may write it: 'az webapp config appsettings delete' removes every deleted name from it
# (azure-cli 2.86 delete_app_settings), even with --slot staging. Read-only GET; returns the names, throws on failure.
function StickyNames {
  $u = 'https://management.azure.com/subscriptions/{subscriptionId}/resourceGroups/folderbird-rg/providers/Microsoft.Web/sites/folderbird-app/config/slotConfigNames?api-version=2022-03-01'
  $n = @(AZ rest --method get --url $u --query properties.appSettingNames -o tsv)
  if ($script:AZRC -ne 0) { throw ('could not read the site-wide sticky-name list ({0}) - see {1}' -f $script:AZRC, $ERRF) }
  return @($n | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Sort-Object)
}
# ---- end of common block ----
# ---- vm block: the test VM and run-command (generated; the same in v2, v4, v5, v6) ----
$VM = 'fb-e2e2c-win'
# '<purpose tag> <power state>' of the VM, e.g. 'e2e-2copy VM running'; '' when az fails.
function VmState {
  $s = @(AZ vm show -d -g $RG -n $VM --query "[tags.purpose, powerState]" -o tsv)
  if ($script:AZRC -ne 0) { return '' }
  return ($s -join ' ').Trim()
}
# Runs a local .ps1 inside the VM as SYSTEM (RunPowerShellScript; az reads the file itself through "@<path>").
# Returns .Out / .Err (run-command keeps the last 4 KB of each, redacted here), or $null when az failed.
function VmRun([string]$file) {
  $o = @(AZ vm run-command invoke -g $RG -n $VM --command-id RunPowerShellScript --scripts ('@' + $file) -o json)
  if ($script:AZRC -ne 0) { return $null }
  $r = ($o -join "`n") | ConvertFrom-Json
  $so = [string](@($r.value | Where-Object { $_.code -like '*StdOut*' } | ForEach-Object { $_.message }) | Select-Object -First 1)
  $se = [string](@($r.value | Where-Object { $_.code -like '*StdErr*' } | ForEach-Object { $_.message }) | Select-Object -First 1)
  return New-Object PSObject -Property @{ Out = (Red $so); Err = (Red $se) }
}
function LogVm($res) {
  foreach ($line in ($res.Out -split "`r?`n")) { if ($line.Trim()) { L ('vm| ' + $line) } }
  foreach ($line in ($res.Err -split "`r?`n")) { if ($line.Trim()) { L ('vm stderr| ' + $line) } }
}
# ---- end of vm block ----
$script:REDACT_TOKENS = $true
try {
  $chkFile = Join-Path $D 'vm-check.ps1'
  if ([IO.File]::ReadAllText($chkFile) -match '[^\x00-\x7F]') { throw 'vm-check.ps1 is not ASCII' }
  $res = $null
  for ($i = 1; $i -le 4; $i++) {
    $st = VmState
    if ($st -notmatch '^e2e-2copy\s') { throw ("VM $VM is missing or not tagged purpose=e2e-2copy: '$st'") }
    L ('attempt {0}: {1}' -f $i, $st)
    if ($st -match 'VM running') {
      $res = VmRun $chkFile
      if ($null -ne $res -and $res.Out -match 'CHECK DONE') { break }
      if ($null -eq $res) { L ('run-command failed ({0}) - VM agent not ready yet? see {1}' -f $script:AZRC, $ERRF) } else { L 'no CHECK DONE in the VM output yet' }
    }
    if ($i -lt 4) { Start-Sleep -Seconds 60 }
  }
  if ($null -eq $res -or $res.Out -notmatch 'CHECK DONE') { throw 'no CHECK DONE from the VM after 4 attempts' }
  LogVm $res
  $kf = Join-Path $D 'apikey.txt'
  if ((Test-Path -LiteralPath $kf) -and [IO.File]::ReadAllText($kf).Trim()) {
    $k = ReadSecret 'apikey.txt' '^fbk_live_[A-Za-z0-9_-]{43}$'
    try {
      $resp = Invoke-WebRequest -UseBasicParsing -TimeoutSec 60 -Uri ($STAGING + '/api/v1/devices') -Headers @{ Authorization = ('Bearer ' + $k) }
      foreach ($dv in @(($resp.Content | ConvertFrom-Json).devices)) { L ('staging device: id {0}, name {1}, status {2}, version {3}, last seen {4}' -f $dv.id, $dv.name, $dv.status, $dv.appVersion, $dv.lastSeen) }
    } catch { L ('staging device list: ' + $_.Exception.GetBaseException().Message) }
    $k = $null
  } else { L 'apikey.txt has no key yet - the staging device list is checked by b2-mint-key.ps1' }
  L 'DONE - if the VERDICT line says the token migrated, run v6-vm-scrub.ps1'
} catch { Fail $_ }
