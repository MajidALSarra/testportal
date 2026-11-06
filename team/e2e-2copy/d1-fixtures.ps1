# D1 - put the preview fixtures test-deck.pptx and test-small.pdf (tools/e2e/fixtures at folderbird-web 91de08d,
# synthetic, no user data) into BOTH test devices' test folders, so staging-e2e action=preview can run on each.
# Fetched with gh (base64 through the contents API), checked against the SHA-256 in tools/e2e/fixtures/README.md, then
# sent with the e2e key through POST /api/v1/devices/{id}/files/upload?path=<folder> (field 'file'); each upload must
# answer 200 with delivered=true. This doubles as a first check of the upload path on both devices.
# [PROD-SHARED: Blob staging under transfers/, commands through the shared Redis]
# Run detached after b2 (needs apikey.txt):
#   Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','C:\Temp\e2e\d1-fixtures.ps1'
$NAME = 'd1-fixtures'
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
Add-Type -AssemblyName System.Net.Http
$REF = '91de08d'
$FIX = @(
  @{ n = 'test-deck.pptx'; len = 30264; sha = '484397af63e252019ce9c6a3ccfb5ba924654e5c5b38c40c4388b2db1540b6e1' },
  @{ n = 'test-small.pdf'; len = 1447; sha = '066da7eaca101e92bdc6ce5f76f0f568b5a4cec37ee32323dbea17297c27c047' })
$TARGET = @{ 'E2E2C-WIN' = 'C:\FolderbirdStaging\testfiles'; 'E2E2C-LNX' = '/root/testfiles' }
try {
  CheckLock
  $key = ReadSecret 'apikey.txt' '^fbk_live_[A-Za-z0-9_-]{43}$'
  $gh = GhPath
  if (-not $gh) { throw 'gh is not on this process PATH' }
  $fd = Join-Path $D 'fixtures'
  New-Item -ItemType Directory -Force -Path $fd | Out-Null
  $hasher = [Security.Cryptography.SHA256]::Create()
  foreach ($f in $FIX) {
    $r = RunExe $gh @('api', ('repos/{0}/contents/tools/e2e/fixtures/{1}?ref={2}' -f $REPO, $f.n, $REF), '--jq', '.content') $null 120
    if ($r.Err.Trim()) { [IO.File]::AppendAllText($ERRF, (Red $r.Err) + "`r`n") }
    if ($r.Code -ne 0) { throw ('gh api for {0} failed ({1}) - see {2}' -f $f.n, $r.Code, $ERRF) }
    $bytes = [Convert]::FromBase64String(($r.Out -replace '\s', ''))
    $h = ([BitConverter]::ToString($hasher.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    if ($bytes.Length -ne $f.len -or $h -ne $f.sha) { throw ('{0}: got {1} bytes sha256 {2}, expected {3} bytes {4}' -f $f.n, $bytes.Length, $h, $f.len, $f.sha) }
    [IO.File]::WriteAllBytes((Join-Path $fd $f.n), $bytes)
    L ('{0}: {1} bytes, sha256 {2} (matches tools/e2e/fixtures/README.md)' -f $f.n, $bytes.Length, $h)
  }

  $cl = New-Object System.Net.Http.HttpClient
  $cl.Timeout = [TimeSpan]::FromSeconds(300)
  $cl.DefaultRequestHeaders.Authorization = New-Object System.Net.Http.Headers.AuthenticationHeaderValue('Bearer', $key)
  $dr = $cl.GetAsync($STAGING + '/api/v1/devices').Result
  if ([int]$dr.StatusCode -ne 200) { throw ('GET /api/v1/devices -> HTTP ' + [int]$dr.StatusCode) }
  $devs = @((($dr.Content.ReadAsStringAsync().Result) | ConvertFrom-Json).devices)
  $hf = Join-Path $D 'hashes.txt'
  foreach ($dn in @('E2E2C-WIN', 'E2E2C-LNX')) {
    $hit = @($devs | Where-Object { [string]$_.name -eq $dn })
    if ($hit.Count -ne 1) { throw ('{0} device(s) named {1} visible to the key - expected exactly 1' -f $hit.Count, $dn) }
    if ([string]$hit[0].status -eq 'offline') { throw ($dn + ' is offline - fix the device first (aci-logs / v5-vm-check)') }
    $id = [string]$hit[0].id
    foreach ($f in $FIX) {
      $mp = New-Object System.Net.Http.MultipartFormDataContent
      $bc = New-Object System.Net.Http.ByteArrayContent -ArgumentList (, [IO.File]::ReadAllBytes((Join-Path $fd $f.n)))
      $mp.Add($bc, 'file', $f.n)
      $u = $STAGING + '/api/v1/devices/' + $id + '/files/upload?path=' + [uri]::EscapeDataString($TARGET[$dn])
      $resp = $cl.PostAsync($u, $mp).Result
      $code = [int]$resp.StatusCode
      $txt = $resp.Content.ReadAsStringAsync().Result
      $mp.Dispose()
      if ($code -ne 200) { throw ('upload {0} to {1} -> HTTP {2}: {3}' -f $f.n, $dn, $code, $txt) }
      $j = $txt | ConvertFrom-Json
      if (-not $j.delivered) { throw ('upload {0} to {1}: delivered is not true: {2}' -f $f.n, $dn, $txt) }
      L ('{0} -> {1} {2}: HTTP 200, delivered {3}, verified {4}' -f $f.n, $dn, $TARGET[$dn], $j.delivered, $j.verified)
      Add-Content -LiteralPath $hf -Value ('fixture {0}  {1}  {2}  {3}' -f $dn, $f.n, $f.len, $f.sha)
    }
  }
  $key = $null
  L 'DONE - both devices hold test-deck.pptx and test-small.pdf'
} catch { Fail $_ }
