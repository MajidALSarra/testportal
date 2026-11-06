# B2 - [PROD-SHARED: one ApiKeys row] sign in to STAGING as the e2e account and mint a 1-DAY API key bound to exactly
# the two test devices E2E2C-WIN and E2E2C-LNX (deviceScope=selected; scopes devices:read browse download upload exec,
# exactly what staging-api-e2e needs), into apikey.txt. Device ids come from /Device/MyDevicesJson (JSON, same
# session). A previous key in apikey.txt is revoked first (POST /app/revoke). Then proves the key: /api/v1/devices
# must list exactly those two devices. Never logs the key, the password or any page HTML.
# Run AFTER both devices exist (C1 and C2), detached:
#   Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','C:\Temp\e2e\b2-mint-key.ps1'
# The key lives 24 hours: if the test runs longer, run b2 and b-set-secret -Secret E2E_API_KEY again.
$NAME = 'b2-mint-key'
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
# ---- web block: cookie sign-in to the STAGING site (generated; the same in b0, b2, e2) ----
Add-Type -AssemblyName System.Net.Http
function NewClient([bool]$cookies) {
  $h = New-Object System.Net.Http.HttpClientHandler
  $h.AllowAutoRedirect = $false
  $h.UseCookies = $cookies
  if ($cookies) { $h.CookieContainer = New-Object System.Net.CookieContainer }
  $cl = New-Object System.Net.Http.HttpClient($h)
  $cl.Timeout = [TimeSpan]::FromSeconds(120)
  return $cl
}
function Enc([string]$s) { return [uri]::EscapeDataString($s) }
function Get200($cl, [string]$p) {
  $r = $cl.GetAsync($STAGING + $p).Result
  $code = [int]$r.StatusCode
  if ($code -ne 200) { throw ('GET {0} -> HTTP {1}' -f $p, $code) }
  return $r.Content.ReadAsStringAsync().Result
}
# Antiforgery tokens are bound to the signed-in user: always take one from a page fetched in the same session.
function Tok([string]$html, [string]$where) {
  $m = [regex]::Match($html, '<input[^>]*name="__RequestVerificationToken"[^>]*>')
  if (-not $m.Success) { throw ('no antiforgery field on ' + $where) }
  $v = [regex]::Match($m.Value, 'value="([^"]+)"')
  if (-not $v.Success) { throw ('no antiforgery value on ' + $where) }
  return $v.Groups[1].Value
}
function PostForm($cl, [string]$p, [string]$body) {
  $content = New-Object System.Net.Http.StringContent($body, [Text.Encoding]::UTF8, 'application/x-www-form-urlencoded')
  return $cl.PostAsync($STAGING + $p, $content).Result
}
# 'ok' = 302 away from the sign-in pages; 'locked' = the lockout page; 'refused' = 200 (wrong password, no such account,
# unconfirmed address). A 2FA redirect or a 429 throws.
function SignIn($cl, [string]$email, [string]$pw) {
  $t = Tok (Get200 $cl '/Account/Login') '/Account/Login'
  $r = PostForm $cl '/Account/Login' ('Email=' + (Enc $email) + '&Password=' + (Enc $pw) + '&RememberMe=false&__RequestVerificationToken=' + (Enc $t))
  $code = [int]$r.StatusCode
  $loc = [string]$r.Headers.Location
  if ($code -eq 429) { throw 'sign-in rate limit (HTTP 429, 20 per minute): wait 60 s and run again' }
  if ($code -eq 302) {
    if ($loc -match '(?i)totp|/Account/Login|lockout') { throw ('sign-in did not complete: redirected to ' + $loc) }
    return 'ok'
  }
  if ($code -eq 200) {
    $html = $r.Content.ReadAsStringAsync().Result
    if ($html -match '(?i)locked out') { return 'locked' }
    return 'refused'
  }
  throw ('POST /Account/Login -> HTTP ' + $code)
}
# A request with the API key in the Authorization header only (never in a URL, never logged).
function Bearer($cl, [string]$method, [string]$p, [string]$key) {
  $rq = New-Object System.Net.Http.HttpRequestMessage((New-Object System.Net.Http.HttpMethod($method)), ($STAGING + $p))
  $rq.Headers.Authorization = New-Object System.Net.Http.Headers.AuthenticationHeaderValue('Bearer', $key)
  return $cl.SendAsync($rq).Result
}
# ---- end of web block ----
$WANT = @('E2E2C-LNX', 'E2E2C-WIN')
try {
  CheckLock
  RequireB0
  $email = ReadEmail
  $pw = ReadSecret 'pw.txt' '^[A-Za-z0-9]{32}$'
  $kf = Join-Path $D 'apikey.txt'
  if ((Test-Path -LiteralPath $kf) -and [IO.File]::ReadAllText($kf).Trim()) {
    $old = ReadSecret 'apikey.txt' '^fbk_live_[A-Za-z0-9_-]{43}$'
    $rr = Bearer (NewClient $false) 'POST' '/app/revoke' $old
    L ('previous key: POST /app/revoke -> HTTP {0} (204 = revoked, 401 = already invalid)' -f [int]$rr.StatusCode)
    [IO.File]::WriteAllText($kf, '')
    $old = $null
  }
  $c = NewClient $true
  $s = SignIn $c $email $pw
  if ($s -ne 'ok') { throw ('sign-in with pw.txt: ' + $s) }
  L ('signed in as ' + $email)
  $parsed = (Get200 $c '/Device/MyDevicesJson') | ConvertFrom-Json
  $devs = @($parsed | Where-Object { $_ -and $_.name })
  foreach ($dv in $devs) { L ('device on the account: id {0}, name {1}, online {2}' -f $dv.id, $dv.name, $dv.online) }
  $ids = @()
  foreach ($n in $WANT) {
    $hit = @($devs | Where-Object { [string]$_.name -eq $n })
    if ($hit.Count -ne 1) { throw ('{0} device(s) named {1} on the account - expected exactly 1 (finish C1 and C2 first)' -f $hit.Count, $n) }
    if (-not $hit[0].online) { L ('WARNING: {0} is offline right now' -f $n) }
    $ids += [string]$hit[0].id
  }
  $others = @($devs | Where-Object { $WANT -notcontains [string]$_.name })
  if ($others.Count -gt 0) { L ('WARNING: {0} other device(s) on the account; the new key does NOT reach them' -f $others.Count) }

  $t = Tok (Get200 $c '/Manage/ApiKeys') '/Manage/ApiKeys'
  $keyName = 'e2e-2copy ' + (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HHmm') + ' UTC'
  $scopes = (@('devices:read', 'browse', 'download', 'upload', 'exec') | ForEach-Object { 'scopes=' + (Enc $_) }) -join '&'
  $devq = (@($ids) | ForEach-Object { 'deviceIds=' + $_ }) -join '&'
  $r = PostForm $c '/Manage/CreateApiKey' ('__RequestVerificationToken=' + (Enc $t) + '&name=' + (Enc $keyName) + '&' + $scopes + '&deviceScope=selected&' + $devq + '&expiresDays=1')
  if ([int]$r.StatusCode -ne 302) { throw ('CreateApiKey -> HTTP ' + [int]$r.StatusCode) }
  $html = Get200 $c '/Manage/ApiKeys'
  $m = [regex]::Match($html, 'id="fbNewKey">\s*(fbk_live_[A-Za-z0-9_-]{43})\s*<')
  $html = $null
  if (-not $m.Success) { throw ('the new key was not shown on /Manage/ApiKeys (TempData cookie lost?) - revoke the row named "{0}" by hand' -f $keyName) }
  $key = $m.Groups[1].Value
  $script:SECRETS += $key
  [IO.File]::WriteAllText($kf, $key)
  L ("key '{0}' written to apikey.txt: {1} chars, 1 day, device ids {2}" -f $keyName, $key.Length, ($ids -join ','))

  $vr = Bearer (NewClient $false) 'GET' '/api/v1/devices' $key
  if ([int]$vr.StatusCode -ne 200) { throw ('GET /api/v1/devices with the new key -> HTTP ' + [int]$vr.StatusCode) }
  $vis = @((($vr.Content.ReadAsStringAsync().Result) | ConvertFrom-Json).devices)
  foreach ($dv in $vis) { L ('the key sees: id {0}, name {1}, status {2}, version {3}' -f $dv.id, $dv.name, $dv.status, $dv.appVersion) }
  $seen = @($vis | ForEach-Object { [string]$_.name } | Sort-Object)
  if (($seen -join ',') -ne ($WANT -join ',')) { throw ('the key sees [{0}], expected exactly [{1}]' -f ($seen -join ','), ($WANT -join ',')) }
  $key = $null
  L 'DONE - next: b-set-secret.ps1 -Secret E2E_API_KEY, then d1-fixtures.ps1'
} catch { Fail $_ }
