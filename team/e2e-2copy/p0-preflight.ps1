# P0 - READ-ONLY preflight. Logs names, counts, states and health only; never a value of a secret.
# The production HOST is never contacted: production's instance ids come from ARM (az webapp list-instances).
# Run detached:
#   Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','C:\Temp\e2e\p0-preflight.ps1'
# Read: Get-Content C:\Temp\e2e\p0-preflight.log -Tail 60
$NAME = 'p0-preflight'
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
# ---- end of common block ----
$ErrorActionPreference = 'Continue'
function Probe([string]$label, [scriptblock]$body) {
  try { & $body } catch { L ('{0}: ERROR {1}' -f $label, $_.Exception.GetBaseException().Message) }
}
L '--- P0 preflight (read-only) ---'
Probe 'az python' { L ('az python present: ' + (Test-Path -LiteralPath $PY)) }
Probe 'az version' {
  $v = (@(AZ version -o json) -join "`n") | ConvertFrom-Json
  L ('az version: {0} (exit {1})' -f $v.'azure-cli', $script:AZRC)
}
Probe 'az account' { L ('az account: {0} (exit {1})' -f (@(AZ account show --query "[name, user.name]" -o tsv) -join ' / '), $script:AZRC) }
Probe 'staging instances' { L ('staging instances: {0} (exit {1})' -f (@(AZ webapp list-instances -g folderbird-rg -n folderbird-app --slot staging --query "[].name" -o tsv) -join ' '), $script:AZRC) }
Probe 'production instances' { L ('production instances (ARM; keep as the baseline for E5): {0} (exit {1})' -f (@(AZ webapp list-instances -g folderbird-rg -n folderbird-app --query "[].name" -o tsv) -join ' '), $script:AZRC) }
Probe 'staging TestAccount' {
  $n = @(AZ webapp config appsettings list -g folderbird-rg -n folderbird-app --slot staging --query "[?starts_with(name,'TestAccount__')].[name, to_string(slotSetting)]" -o tsv)
  L ('staging TestAccount__* settings (name, sticky): {0}' -f $(if ($n.Count) { $n -join ' | ' } else { 'none' }))
  $e = (@(AZ webapp config appsettings list -g folderbird-rg -n folderbird-app --slot staging --query "[?name=='TestAccount__Email'].value | [0]" -o tsv) -join '').Trim()
  L ('staging TestAccount__Email (an address, not a secret): ' + $(if ($e) { $e } else { '(unset)' }))
}
Probe 'resource group' {
  L ('rg {0} exists: {1}' -f $RG, (@(AZ group exists -n $RG) -join ''))
  L ('NetworkWatcherRG exists: {0}' -f (@(AZ group exists -n NetworkWatcherRG) -join ''))
}
Probe 'quota' {
  $q = @(AZ vm list-usage -l westeurope --query "[?name.value=='cores' || name.value=='standardDSv4Family' || name.value=='standardBSFamily'].[name.value, to_string(currentValue), to_string(limit)]" -o tsv)
  foreach ($line in $q) { L ('quota westeurope: ' + $line) }
}
Probe 'gh' {
  $gh = GhPath
  if (-not $gh) { L 'gh: NOT FOUND on this process PATH - b-set-secret, d1-fixtures and e3 cannot run from here' }
  else {
    L ('gh: ' + $gh)
    $r = RunExe $gh @('auth', 'status') $null 60
    L ('gh auth status exit: ' + $r.Code)
    $r = RunExe $gh @('secret', 'list', '-R', $REPO) $null 60
    L ('repo secrets (exit {0}): {1}' -f $r.Code, ((@($r.Out -split "`r?`n" | Where-Object { $_.Trim() })) -join ' | '))
    foreach ($wf in 'staging-e2e.yml', 'staging-api-e2e.yml') {
      $r = RunExe $gh @('run', 'list', '-R', $REPO, '-w', $wf, '-L', '3') $null 60
      L ('{0} last runs (exit {1}): {2}' -f $wf, $r.Code, ((@($r.Out -split "`r?`n" | Where-Object { $_.Trim() })) -join ' | '))
    }
  }
}
Probe 'disk' { L ('C: free GB: {0:N2}' -f ((Get-PSDrive C).Free / 1GB)) }
Probe 'laptop FolderbirdClient' {
  $ps = @(Get-Process FolderbirdClient -ErrorAction SilentlyContinue)
  if ($ps.Count -eq 0) { L 'FolderbirdClient on the laptop: none running' }
  foreach ($p in $ps) { L ('FolderbirdClient pid {0}: {1}' -f $p.Id, $p.Path) }
}
Probe 'staging health' {
  $r = Invoke-WebRequest -UseBasicParsing -TimeoutSec 30 -Uri ($STAGING + '/healthz/ready')
  L ('staging /healthz/ready -> {0} {1}' -f $r.StatusCode, $r.Content)
}
Probe 'files' {
  $acl = Get-Acl -LiteralPath $D
  L ('{0}: inheritance off = {1}' -f $D, $acl.AreAccessRulesProtected)
  foreach ($fn in 'pw.txt', 'bootstrap.txt', 'email.txt', 'apikey.txt', 'win-token.txt', 'lnx-token.txt', 'vm-admin.txt', 'old-testaccount.json', 'hashes.txt') {
    $p = Join-Path $D $fn
    if (Test-Path -LiteralPath $p) { L ('{0}: present, {1} bytes' -f $fn, (Get-Item -LiteralPath $p).Length) } else { L ($fn + ': absent') }
  }
  L ('C:\FolderbirdE2E on the laptop (draft leftovers; must be absent): {0}' -f (Test-Path -LiteralPath 'C:\FolderbirdE2E'))
}
L 'DONE'
