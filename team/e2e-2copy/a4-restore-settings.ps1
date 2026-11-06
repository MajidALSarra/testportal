# A4 - [PROD-SHARED: another staging restart] put staging's TestAccount__* settings back exactly as A2 found them
# (values from old-testaccount.json, written with --settings so stickiness is never touched), or delete ours when
# staging had none. Runs right after B0, so the bootstrap value spends minutes, not the whole test, in App Service.
# Reads the result back and refuses to report DONE unless the names, their stickiness and the address match the backup.
# Then blanks old-testaccount.json (it holds the OLD account's password).
# * -Abort: the way back when the test is abandoned after A2 but before B0 finished (q-seed or b0 stopped, staging
#   trouble, Majid stops it). It only skips the "B0 must be done" check; the restore itself never depended on B0.
#   Then follow the RUNBOOK abort sequence (E1 if C1/V1 ran, E2, E3 if B1/B3 ran, E4). Never remove or replace this
#   folder while old-testaccount.json holds a value: it is the only copy of staging's original values.
# * The site-wide sticky-name list is shared with production and is never written here. 'az webapp config appsettings
#   delete' would remove a deleted name from that list (azure-cli 2.86 delete_app_settings, even with --slot), so a name
#   of ours that is in the list is BLANKED with --settings (the seeder ignores a blank address or password) instead of
#   deleted; any other delete is checked against the list before and after.
# Run detached:
#   Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','C:\Temp\e2e\a4-restore-settings.ps1'[,'-Abort']
param([switch]$Abort)
$NAME = 'a4-restore-settings'
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
try {
  CheckLock
  if ($Abort) { L 'ABORT mode: restoring staging settings without the B0 check (the test is being abandoned)' } else { RequireB0 }
  $bk = Join-Path $D 'old-testaccount.json'
  if (-not (Test-Path -LiteralPath $bk)) { throw 'old-testaccount.json is missing - nothing to restore from' }
  $old = [IO.File]::ReadAllText($bk)
  if (-not $old.Trim()) { throw 'old-testaccount.json is empty - already restored (see the last a4 log)' }
  $parsed = $old | ConvertFrom-Json
  $list = @($parsed | Where-Object { $_ -and $_.name })
  foreach ($s in $list) { if ($s.name -eq 'TestAccount__Password') { $script:SECRETS += [string]$s.value } }
  $ours = @('TestAccount__Email', 'TestAccount__Password')
  $names = @($list | ForEach-Object { [string]$_.name })
  $stickyBefore = @(StickyNames)
  L ('site-wide sticky app-setting names before (shared with production, {0}): {1}' -f $stickyBefore.Count, $(if ($stickyBefore.Count) { $stickyBefore -join ',' } else { 'none' }))
  $extra = @($ours | Where-Object { $names -notcontains $_ })
  $blank = @($extra | Where-Object { $stickyBefore -contains $_ })
  $del = @($extra | Where-Object { $stickyBefore -notcontains $_ })
  $h = @{}
  foreach ($s in $list) { $h[[string]$s.name] = [string]$s.value }
  foreach ($n in $blank) { $h[$n] = '' }
  if ($h.Count -gt 0) {
    $f = Join-Path $D 'restore.json'
    try {
      [IO.File]::WriteAllText($f, ($h | ConvertTo-Json -Compress))
      $h = $null
      AZ webapp config appsettings set -g folderbird-rg -n folderbird-app --slot staging --settings ('@' + $f) -o none | Out-Null
      $rc = $script:AZRC
    } finally { [IO.File]::WriteAllText($f, '') }
    if ($rc -ne 0) { throw ('restore failed ({0}) - see {1}' -f $rc, $ERRF) }
    if ($names.Count) { L ('restored values of: ' + ($names -join ', ')) }
    if ($blank.Count) { L ('BLANKED, not deleted (staging had none before, but the name is in the site-wide sticky list; a delete would change production''s list): ' + ($blank -join ', ')) }
  }
  if ($del.Count -gt 0) {
    AZ webapp config appsettings delete -g folderbird-rg -n folderbird-app --slot staging --setting-names @del -o none | Out-Null
    if ($script:AZRC -ne 0) { throw ('delete of {0} failed ({1}) - see {2}' -f ($del -join ','), $script:AZRC, $ERRF) }
    L ('deleted (staging had none before, not in the sticky list): ' + ($del -join ', '))
  }
  $stickyAfter = @(StickyNames)
  if (($stickyAfter -join ',') -ne ($stickyBefore -join ',')) { throw ('the site-wide sticky list CHANGED during this run: before [{0}], after [{1}] - production''s configuration differs; tell Falcon at once' -f ($stickyBefore -join ','), ($stickyAfter -join ',')) }
  L ('site-wide sticky list unchanged ({0} names)' -f $stickyAfter.Count)
  $now = @(AZ webapp config appsettings list -g folderbird-rg -n folderbird-app --slot staging --query "[?starts_with(name,'TestAccount__')].[name, to_string(slotSetting)]" -o tsv)
  foreach ($line in $now) { L ('now: ' + $line) }
  $want = @(@($list | ForEach-Object { ("{0}`t{1}" -f $_.name, ([string]$_.slotSetting).ToLowerInvariant()) }) + @($blank | ForEach-Object { "$_`ttrue" }) | Sort-Object)
  $got = @($now | ForEach-Object { $_.Trim() } | Sort-Object)
  if (($want -join '|') -ne ($got -join '|')) { throw ('names/stickiness after restore [{0}] differ from the backup [{1}]' -f ($got -join ', '), ($want -join ', ')) }
  foreach ($n in $blank) {
    $v = (@(AZ webapp config appsettings list -g folderbird-rg -n folderbird-app --slot staging --query "[?name=='$n'].value | [0]" -o tsv) -join '').Trim()
    if ($v) { $v = $null; throw ('{0} still holds a value after blanking (value not shown)' -f $n) }
    L ('{0} reads back blank' -f $n)
  }
  # '' + (...), not [string](...): a cast of an EMPTY pipeline gives $null, and '' -ne $null would fail a correct restore.
  $oldEmail = '' + (@($list | Where-Object { $_.name -eq 'TestAccount__Email' } | ForEach-Object { $_.value }) | Select-Object -First 1)
  $nowEmail = (@(AZ webapp config appsettings list -g folderbird-rg -n folderbird-app --slot staging --query "[?name=='TestAccount__Email'].value | [0]" -o tsv) -join '').Trim()
  if ($nowEmail -ne $oldEmail) { throw ('TestAccount__Email is {0}, the backup says {1}' -f $nowEmail, $oldEmail) }
  L ('TestAccount__Email = {0} (as before A2)' -f $(if ($nowEmail) { $nowEmail } else { '(unset or blank)' }))
  [IO.File]::WriteAllText($bk, '')
  L 'old-testaccount.json blanked'
  if ($Abort) { L 'DONE (abort) - the staging slot is restarting; check /healthz/ready, then the RUNBOOK abort sequence: E1 if C1/V1 ran, E2, E3 if B1/B3 ran, E4' }
  else { L 'DONE - the staging slot is restarting; check /healthz/ready, then b-set-secret.ps1 -Secret E2E_PASSWORD' }
} catch { Fail $_ }
