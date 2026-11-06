# A3 - READ-ONLY: wait for staging /healthz/ready, then read the TestAccountSeeder console lines of the last 90 minutes
# from Log Analytics (they name the address only, never a password). No slot filter in the query: each line is labelled
# with its slot instead, so an unverified _ResourceId filter cannot hide the answer.
# Seeder texts (Services/TestAccountSeeder.cs at 91de08d):
#   "[TestAccountSeeder] created pre-verified account <email>"                 created -> go on to b0
#   "[TestAccountSeeder] account <email> already exists and is confirmed ..."   existed already (an earlier run of A2, or
#                                                                               someone else's account: b0 decides)
#   "[TestAccountSeeder] existing account <email> marked email-confirmed."      someone REGISTERED that address: stop,
#                                                                               a4 -Abort (same folder), then start again
#                                                                               with a1 -Email e2e-2copy-b@folderbird.com
#   "[TestAccountSeeder] FAILED to create <email>: <Identity text>"            "is already taken" next to a created line
#                                                                               = the second instance lost the race (fine);
#                                                                               anything else = a password rule failed
#   "[TestAccountSeeder] error (startup continues): ..."                        harmless only if a created line exists
# Run detached ~1 minute after A2:
#   Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','C:\Temp\e2e\q-seed.ps1'
param([int]$WaitReadyMinutes = 10, [int]$QueryMinutes = 14)
$NAME = 'q-seed'
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
$WS = 'e6ed9be0-2c69-41a8-9581-55a5a6690ffb'
try {
  $email = ReadEmail
  $deadline = (Get-Date).AddMinutes($WaitReadyMinutes)
  $ready = $false
  while ((Get-Date) -lt $deadline) {
    try {
      $h = Invoke-WebRequest -UseBasicParsing -TimeoutSec 30 -Uri ($STAGING + '/healthz/ready')
      if ($h.StatusCode -eq 200 -and $h.Content -match '"status"\s*:\s*"ready"') { $ready = $true; L ('staging ready: ' + $h.Content); break }
      L ('staging answered {0} but not ready yet' -f $h.StatusCode)
    } catch { L ('staging not ready yet: ' + $_.Exception.GetBaseException().Message) }
    Start-Sleep -Seconds 20
  }
  if (-not $ready) { L ('WARNING: staging did not report ready within {0} min' -f $WaitReadyMinutes) }

  $kq = Join-Path $D 'q-seed.kql'
  $kql = "AppServiceConsoleLogs`n| where TimeGenerated > ago(90m)`n| where ResultDescription has 'TestAccountSeeder'`n| project TimeGenerated, Where = iff(_ResourceId contains '/slots/', 'staging', 'production'), ResultDescription`n| order by TimeGenerated asc"
  [IO.File]::WriteAllText($kq, $kql)
  $deadline = (Get-Date).AddMinutes($QueryMinutes)
  $mine = @()
  do {
    $rows = @(AZ monitor log-analytics query -w $WS --analytics-query ('@' + $kq) -o tsv)
    if ($script:AZRC -ne 0) { L ('query failed ({0}) - see {1}' -f $script:AZRC, $ERRF) }
    else {
      $mine = @($rows | Where-Object { $_ -like ('*' + $email + '*') })
      L ('{0} seeder line(s) in the last 90 min, {1} for {2}' -f $rows.Count, $mine.Count, $email)
      if ($mine.Count -gt 0) { break }
    }
    if ((Get-Date).AddSeconds(120) -lt $deadline) { L 'nothing for the e2e address yet (log ingestion takes about 5 min); next try in 120 s'; Start-Sleep -Seconds 120 } else { break }
  } while ((Get-Date) -lt $deadline)
  foreach ($row in $mine) { L ('seeder| ' + $row) }
  if ($mine.Count -eq 0) { throw ('no seeder line for {0} within {1} min - read q-seed.err; b0-set-password.ps1 is the final proof (to give up instead: a4-restore-settings.ps1 -Abort, then the RUNBOOK abort sequence)' -f $email, $QueryMinutes) }
  $created = @($mine | Where-Object { $_ -match 'created pre-verified account' }).Count -gt 0
  if (@($mine | Where-Object { $_ -match 'marked email-confirmed' }).Count -gt 0) { throw 'someone had REGISTERED this address (seeder only confirmed it): stop. Run a4-restore-settings.ps1 -Abort in THIS folder first (old-testaccount.json is the only copy of staging''s old values), then the RUNBOOK abort sequence, then a1 -Email e2e-2copy-b@folderbird.com' }
  if ($created) { L 'VERDICT: account created by the seeder' }
  elseif (@($mine | Where-Object { $_ -match 'already exists and is confirmed' }).Count -gt 0) { L 'VERDICT: the address already existed - fine if an earlier A2 created it; b0 proves it (bootstrap sign-in)' }
  else { throw 'no created line for the address - a password rule failed or the seeder errored; read the seeder| lines, then a4-restore-settings.ps1 -Abort and the RUNBOOK abort sequence' }
  L 'DONE - next: b0-set-password.ps1'
} catch { Fail $_ }
