# V1 - [SPEND ~$0.23/h for Standard_D2s_v4, ~$0.07/h for Standard_B2s] create the THROWAWAY Windows test VM
# fb-e2e2c-win in folderbird-e2e-rg (the same group as the Linux container; 'e1-delete-rg.ps1' removes every piece).
# It replaces the draft "second copy on Majid's laptop": the e2e key and password allow exec on the test device, so
# the device must hold nothing of value - no az, no gh, no Folderbird sign-in, no keys, no source.
#  * No inbound rule at all: --nsg-rule NONE leaves only Azure's default NSG rules (inbound from the internet denied).
#    The Standard public IP is there for OUTBOUND only (a new VNet may have no default outbound access).
#  * The VM admin password is generated here into vm-admin.txt and handed to az as "@<path>": az reads the file
#    itself, so the password is never on a command line. Nobody needs it (there is no RDP); Azure requires one.
#  * No auto-shutdown schedule (the app must keep running).
# Logs names, ids, lengths and prices only.
# Run detached (Majid's go for the cost first):
#   Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','C:\Temp\e2e\v1-vm-create.ps1'
# Cheaper, CPU-credit throttled: add '-Size','Standard_B2s'. The default Standard_D2s_v4 + this image is the pair
# fb-build was created with in this subscription (DSv5 has 0 quota in westeurope).
param([string]$Size = 'Standard_D2s_v4')
$NAME = 'v1-vm-create'
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
$LOC = 'westeurope'; $VM = 'fb-e2e2c-win'
$IMAGE = 'MicrosoftWindowsServer:WindowsServer:2022-datacenter-azure-edition:latest'
$ADMIN = 'fbe2eadmin'; $PWF = Join-Path $D 'vm-admin.txt'
$VNET = 'fb-e2e2c-vnet'; $SUBNET = 'fb-e2e2c-subnet'; $NSG = 'fb-e2e2c-win-nsg'; $PIP = 'fb-e2e2c-win-ip'
try {
  if ($Size -notin 'Standard_D2s_v4', 'Standard_B2s', 'Standard_B2ms', 'Standard_D2s_v3') { throw ('size {0} is not in the allowed list (DSv5 has 0 quota in westeurope)' -f $Size) }
  CheckLock
  L ('start: size {0}, image {1}' -f $Size, $IMAGE)
  $acct = @(AZ account show --query "[name, user.name]" -o tsv)
  if ($script:AZRC -ne 0) { throw ('az account show failed ({0}) - see {1} (is az signed in?)' -f $script:AZRC, $ERRF) }
  L ('az account: ' + ($acct -join ' / '))

  if (-not (Test-Path -LiteralPath $PWF) -or -not [IO.File]::ReadAllText($PWF).Trim()) {
    $cs = [char[]]'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!#%-_.'
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create(); $b = New-Object byte[] 28
    do { $rng.GetBytes($b); $pw = -join ($b | ForEach-Object { $cs[$_ % $cs.Length] }) }
    until ($pw -cmatch '[A-Z]' -and $pw -cmatch '[a-z]' -and $pw -match '[0-9]' -and $pw -match '[!#%._-]')
    [IO.File]::WriteAllText($PWF, $pw)
    $pw = $null
    L 'vm-admin.txt written'
  }
  # If az cannot READ the file it silently uses the literal text "@C:\..." as the password, so check it right before.
  $chk = [IO.File]::ReadAllText($PWF)
  if ($chk.Length -lt 16 -or $chk -match '[\r\n\s"]') { $chk = $null; throw 'vm-admin.txt is unreadable, too short or has whitespace/quotes - blank it and rerun' }
  $script:SECRETS += $chk
  L ('vm-admin.txt: {0} chars' -f $chk.Length)
  $chk = $null

  foreach ($line in @(AZ vm list-usage -l $LOC --query "[?name.value=='cores' || name.value=='standardDSv4Family' || name.value=='standardBSFamily' || name.value=='standardDSv3Family'].[name.value, to_string(currentValue), to_string(limit)]" -o tsv)) { L ('quota westeurope: ' + $line) }
  try {
    $f = "serviceName eq 'Virtual Machines' and armRegionName eq '$LOC' and armSkuName eq '$Size' and priceType eq 'Consumption'"
    $pr = Invoke-RestMethod -UseBasicParsing -TimeoutSec 30 -Uri ('https://prices.azure.com/api/retail/prices?$filter=' + [uri]::EscapeDataString($f))
    foreach ($it in @($pr.Items)) {
      if ($it.productName -like '*Windows*' -and $it.skuName -notlike '*Spot*' -and $it.skuName -notlike '*Low Priority*') {
        L ('list price {0}: {1} {2} per {3} ({4})' -f $Size, $it.retailPrice, $it.currencyCode, $it.unitOfMeasure, $it.productName)
      }
    }
  } catch { L ('price lookup skipped: ' + $_.Exception.GetBaseException().Message) }
  $nw = @(AZ network watcher list --query "[?location=='$LOC'].id" -o tsv)
  L ('network watcher in {0} before create: {1} (if none, Azure may create NetworkWatcherRG, which e1 does not delete)' -f $LOC, $(if ($nw.Count) { $nw -join ' ' } else { 'none' }))

  EnsureRg
  $vtag = (@(AZ vm show -g $RG -n $VM --query tags.purpose -o tsv) -join '').Trim()
  if ($script:AZRC -eq 0) {
    if ($vtag -ne 'e2e-2copy') { throw ("VM $VM exists but is tagged purpose='$vtag' - refusing") }
    L "VM $VM already exists - not creating it again"
  } else {
    L "creating VM $VM (3-8 minutes)"
    $o = @(AZ vm create -g $RG -n $VM -l $LOC --image $IMAGE --size $Size --computer-name $VM `
           --admin-username $ADMIN --admin-password ('@' + $PWF) --authentication-type password `
           --vnet-name $VNET --subnet $SUBNET --nsg $NSG --nsg-rule NONE `
           --public-ip-address $PIP --public-ip-sku Standard `
           --storage-sku StandardSSD_LRS --license-type None `
           --tags purpose=e2e-2copy owner=coordinator `
           --query "[powerState, publicIpAddress, privateIpAddress]" -o tsv)
    $rc = $script:AZRC
    if ($rc -ne 0) { throw ('vm create failed ({0}) - see {1} (quota? size/image not allowed? password rejected?)' -f $rc, $ERRF) }
    L ('vm created: ' + ($o -join ' / '))
  }

  $n = (@(AZ network nsg rule list -g $RG --nsg-name $NSG --query "length(@)" -o tsv) -join '').Trim()
  if ($script:AZRC -ne 0) { throw ('could not list the rules of {0} ({1})' -f $NSG, $script:AZRC) }
  if ($n -ne '0') { throw ('NSG {0} has {1} custom rule(s) - expected none; inspect it before going on' -f $NSG, $n) }
  $nic = (@(AZ vm show -g $RG -n $VM --query "networkProfile.networkInterfaces[0].id" -o tsv) -join '').Trim()
  $nicNsg = (@(AZ network nic show --ids $nic --query networkSecurityGroup.id -o tsv) -join '').Trim()
  if ($nicNsg -notlike "*/networkSecurityGroups/$NSG") { throw ("the NIC is not behind $NSG (got '$nicNsg')") }
  L ('NSG {0}: 0 custom rules (Azure defaults only, no inbound from the internet), attached to the NIC' -f $NSG)
  $info = @(AZ vm show -d -g $RG -n $VM --query "[powerState, publicIps, hardwareProfile.vmSize, storageProfile.imageReference.exactVersion, securityProfile.securityType, storageProfile.osDisk.managedDisk.storageAccountType]" -o tsv)
  L ('vm: ' + ($info -join ' | '))
  $sched = (@(AZ resource list -g $RG --resource-type Microsoft.DevTestLab/schedules --query "length(@)" -o tsv) -join '').Trim()
  L ('auto-shutdown schedules in {0}: {1} (expected 0)' -f $RG, $sched)
  L 'DONE - next: v2-vm-provision.ps1'
} catch { Fail $_ }
