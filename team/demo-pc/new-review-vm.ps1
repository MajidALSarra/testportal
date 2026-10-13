# Builds the ChatGPT-reviewer demo PC. Runs on the laptop (az signed in) for 20-40 minutes, so it can NOT
# run inside a 45 s Folderbird run_command. Majid starts it himself in a visible window, or an agent
# starts it DETACHED and polls the log:
#   Start-Process powershell.exe -ArgumentList '-NoExit','-ExecutionPolicy','Bypass','-File',
#     '"<path>\new-review-vm.ps1"','-SubscriptionId','<id>','-AlertEmail','<email>'
#   log: %LOCALAPPDATA%\fb-review\build.log   last line BUILD:OK or BUILD:FAILED <step>
# It asks for nothing and takes no password argument (never add one). Only after Majid's typed go.
#
#   .\new-review-vm.ps1 -SubscriptionId <id> -AlertEmail <email> -WhatIf      # preflight only, changes nothing
#   .\new-review-vm.ps1 -SubscriptionId <id> -AlertEmail <email>              # build (re-runnable: resumes by stage)
#   .\new-review-vm.ps1 -SubscriptionId <id> -AlertEmail <email> -RefreshEgress   # re-resolve folderbird IPs only
#   .\new-review-vm.ps1 -SubscriptionId <id> -AlertEmail <email> -ArmAutoLogon    # after Majid's Bastion sign-in
#
# What it makes, all in its own resource group (West Europe):
#   budget alert (first, before anything billable) -> NSG -> VM fb-review (Windows Server 2022, Standard_B2s,
#   64 GB Standard SSD, outbound-only Standard public IP, no managed identity) -> Bastion Developer (free)
#   -> standard user + auto-logon + app task -> fictional documents -> CC0/PD photos -> OUTBOUND LOCK.
# Inbound: no allow rule (the script stops if one appears). Outbound after seeding: only folderbird.com,
# the App Service host, the folderbirdfiles blob host (file transfers), Windows Update / activation; the rest of
# the internet is denied, because reviewers get a shell and abuse would be billed to this subscription.
# Passwords: admin is random and never kept (the account is disabled inside the VM); the demo user's is
# random, shown ONCE in this window (not in the log) for Majid's single Bastion sign-in.
# Teardown: az group delete -n folderbird-review-rg  (a deletion: needs Majid's go).
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$SubscriptionId,
  [Parameter(Mandatory)][string]$AlertEmail,
  [string]$ResourceGroup = 'folderbird-review-rg',
  [string]$Location      = 'westeurope',
  [string]$Name          = 'fb-review',
  [string]$Size          = 'Standard_B2s',
  [string]$ReviewUser    = 'fbreview',
  [int]   $Budget        = 60,          # in the billing account's currency
  [switch]$WhatIf,
  [switch]$RefreshEgress,
  [switch]$ArmAutoLogon
)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$logDir = Join-Path $env:LOCALAPPDATA 'fb-review'; New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$log = Join-Path $logDir 'build.log'
try { $lock = [IO.File]::Open((Join-Path $logDir 'build.lock'), 'OpenOrCreate', 'ReadWrite', 'None') }
catch { throw 'another new-review-vm.ps1 is already running' }
Start-Transcript -Path $log -Append | Out-Null
$step = 'start'
$prevSub = $null
$secretFiles = @()

$env:AZURE_EXTENSION_USE_DYNAMIC_INSTALL = 'yes_without_prompt'   # az must never wait on stdin
$env:PYTHONPATH = $null; $env:PYTHONNOUSERSITE = '1'               # no stray modules on az's sys.path
$py = 'C:\Program Files\Microsoft SDKs\Azure\CLI2\python.exe'      # az.cmd routes arguments through cmd.exe

# No param block on purpose: every token lands in $args verbatim. stderr goes to a file (merging it under
# 'Stop' throws NativeCommandError in PowerShell 5.1). Runs from TEMP so the script folder is not on sys.path.
function Az {
  $ef = [IO.Path]::GetTempFileName(); $ErrorActionPreference = 'Continue'
  Push-Location $env:TEMP
  try { $out = & $py -B -m azure.cli @args 2> $ef; $code = $LASTEXITCODE } finally { Pop-Location }
  $err = Get-Content $ef -Raw; Remove-Item $ef
  if ($code -ne 0) { throw "az $($args[0]) $($args[1]) $($args[2]) failed ($code): $err" }
  $out
}
function AzJson { (Az @args -o json | Out-String) | ConvertFrom-Json }
function Step($t) { $script:step = $t; Write-Host "`n== $t" -ForegroundColor Cyan }
# A secret travels only as an @file az reads itself: never on a command line, never in the log.
function SecretFile($content) {
  $f = Join-Path $env:TEMP ("fbr-" + [guid]::NewGuid().ToString('N') + '.txt')
  [IO.File]::WriteAllText($f, $content)
  icacls $f /inheritance:r /grant:r "$($env:USERNAME):F" | Out-Null
  $script:secretFiles += $f; $f
}
function NewPassword {
  $alpha = [char[]]'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789'
  $b = New-Object byte[] 24; [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b)
  'Fb9-' + (-join ($b | ForEach-Object { $alpha[$_ % $alpha.Length] }))
}
# Legacy run-command exits 0 even when the in-VM script throws: check stderr AND the success marker.
function InVm($file, $marker, [string[]]$params) {
  $a = @('vm','run-command','invoke','-g',$ResourceGroup,'-n',$Name,'--command-id','RunPowerShellScript','--scripts',"@$here\vm\$file")
  if ($params) { $a += '--parameters'; $a += $params }
  $r = AzJson @a
  $o = "$($r.value[0].message)".Trim(); $e = "$($r.value[1].message)".Trim()
  if ($e -or $o -notmatch "$($marker):OK") { throw "$file failed. out: $o  err: $e" }
  $o
}
function Stage { (AzJson vm show -g $ResourceGroup -n $Name).tags.stage }
function SetStage($s) { Az vm update -g $ResourceGroup -n $Name --set "tags.stage=$s" -o none; Write-Host "stage = $s" }

function LockEgress {
  $nsg = "$Name-nsg"
  $ips = @()
  foreach ($h in 'folderbird.com','folderbird-app.azurewebsites.net') {
    $ips += @(Resolve-DnsName $h -Type A -ErrorAction Stop | Where-Object Type -eq 'A' | ForEach-Object IPAddress)
  }
  # Device file transfers PUT to / GET from the folderbirdfiles blob account (DeviceOps.StageDeviceFileToBlobAsync,
  # MCP download_file / upload_file). Only that account's address, not the whole Storage service tag.
  $blob = @(Resolve-DnsName 'folderbirdfiles.blob.core.windows.net' -Type A -ErrorAction Stop | Where-Object Type -eq 'A' | ForEach-Object IPAddress)
  if ($blob.Count -eq 0) { throw 'could not resolve folderbirdfiles.blob.core.windows.net' }
  $kms = @(Resolve-DnsName 'azkms.core.windows.net' -Type A -ErrorAction Stop | Where-Object Type -eq 'A' | ForEach-Object IPAddress)
  $ips = $ips | Sort-Object -Unique
  if ($ips.Count -eq 0) { throw 'could not resolve folderbird.com' }
  Write-Host "folderbird IPs: $($ips -join ', ')"
  $rule = { param($n, $p, $dest, $ports, $acc) Az network nsg rule create -g $ResourceGroup --nsg-name $nsg -n $n --priority $p `
      --direction Outbound --access $acc --protocol '*' --source-address-prefixes VirtualNetwork `
      --destination-address-prefixes @dest --destination-port-ranges @ports -o none }
  & $rule 'allow-folderbird'   100 $ips                          @('443','80')   'Allow'
  & $rule 'allow-blob'         110 $blob                         @('443')        'Allow'
  try { Az network nsg rule delete -g $ResourceGroup --nsg-name $nsg -n 'allow-storage-weu' -o none } catch { }
  & $rule 'allow-winupdate'    120 @('AzureUpdateDelivery')      @('443','80')   'Allow'
  & $rule 'allow-ms-frontdoor' 130 @('AzureFrontDoor.FirstParty') @('443','80')  'Allow'
  & $rule 'allow-kms'          140 $kms                          @('1688')       'Allow'
  & $rule 'deny-internet'     4000 @('Internet')                 @('*')          'Deny'
}
function CheckEgress {
  $e = InVm 'egress-check.ps1' 'EGRESS'; Write-Host $e
  foreach ($want in 'site=True','apphost=True','blob=True','open-internet=False') { if ($e -notmatch [regex]::Escape($want)) { throw "outbound check failed ($want): $e" } }
}

try {
  Step 'Preflight'
  if ($ResourceGroup -match 'cloudpc|build|^folderbird-rg$') { throw "refusing resource group name $ResourceGroup" }
  foreach ($f in 'vm\setup-user.ps1','vm\seed-docs.ps1','vm\seed-photos.ps1','vm\probe.ps1','vm\egress-check.ps1','vm\arm-autologon.ps1','seed\seed-docs.zip') {
    if (-not (Test-Path -LiteralPath (Join-Path $here $f))) { throw "missing $f" } }
  if (-not (Test-Path -LiteralPath $py)) { throw "Azure CLI python not found at $py" }
  $prevSub = "$(Az account show --query id -o tsv)".Trim()
  Az account set --subscription $SubscriptionId
  $acct = AzJson account show
  Write-Host "subscription: $($acct.name)"
  $rgExists = (Az group exists -n $ResourceGroup) -eq 'true'
  if ($rgExists -and (AzJson group show -n $ResourceGroup).tags.purpose -ne 'chatgpt-reviewer-demo') { throw "$ResourceGroup exists and is not ours - refusing" }
  $sku = (AzJson vm list-skus -l $Location --size $Size --resource-type virtualMachines) | Where-Object name -eq $Size
  if (-not $sku -or $sku.restrictions.Count -gt 0) { throw "$Size is not available in $Location for this subscription" }
  Write-Host "group exists: $rgExists   size $Size available in $Location"
  if ($WhatIf) { Write-Host "WhatIf: would build $ResourceGroup/$Name, budget $Budget/month to $AlertEmail. Nothing changed."; Write-Host 'BUILD:OK whatif'; return }

  if ($RefreshEgress) { Step 'Refresh outbound rule'; LockEgress; CheckEgress; Write-Host 'BUILD:OK refresh'; return }
  if ($ArmAutoLogon)  { Step 'Arm ForceAutoLogon'; Write-Host (InVm 'arm-autologon.ps1' 'ARM' @("ReviewUser=$ReviewUser")); Write-Host 'BUILD:OK arm'; return }

  Step 'Resource group'
  if (-not $rgExists) { Az group create -n $ResourceGroup -l $Location --tags purpose=chatgpt-reviewer-demo owner=magpie -o none }

  Step 'Budget alert (before anything billable)'
  $rgId = (AzJson group show -n $ResourceGroup).id
  $budgetUrl = "https://management.azure.com$rgId/providers/Microsoft.Consumption/budgets/fb-review-budget?api-version=2023-05-01"
  $notify = { param($t, $kind) @{ enabled = $true; operator = 'GreaterThan'; threshold = $t; thresholdType = $kind; contactEmails = @($AlertEmail) } }
  $body = @{ properties = @{ category = 'Cost'; amount = $Budget; timeGrain = 'Monthly'
    timePeriod = @{ startDate = (Get-Date -Day 1).ToString('yyyy-MM-01'); endDate = (Get-Date).AddYears(5).ToString('yyyy-MM-01') }
    notifications = @{ actual50 = (& $notify 50 'Actual'); actual80 = (& $notify 80 'Actual'); actual100 = (& $notify 100 'Actual'); fcast100 = (& $notify 100 'Forecasted') } } }
  $have = $null; try { $have = AzJson rest --method get --url $budgetUrl } catch { }
  if (-not $have -or $have.properties.amount -ne $Budget) {
    $bf = Join-Path $env:TEMP 'fb-review-budget.json'; $body | ConvertTo-Json -Depth 6 | Set-Content $bf -Encoding ASCII
    try { Az rest --method put --url $budgetUrl --body "@$bf" -o none } finally { Remove-Item $bf -Force }
  }
  if ((AzJson rest --method get --url $budgetUrl).properties.amount -ne $Budget) { throw 'budget not readable after create' }

  Step 'Network security group'
  $nsgExists = $true; try { Az network nsg show -g $ResourceGroup -n "$Name-nsg" -o none } catch { $nsgExists = $false }
  if (-not $nsgExists) { Az network nsg create -g $ResourceGroup -n "$Name-nsg" -o none }

  Step 'Virtual machine'
  $vmExists = $true; try { Az vm show -g $ResourceGroup -n $Name -o none } catch { $vmExists = $false }
  if (-not $vmExists) {
    $adminFile = SecretFile (NewPassword)
    Az vm create -g $ResourceGroup -n $Name --size $Size `
      --image 'MicrosoftWindowsServer:WindowsServer:2022-datacenter-azure-edition-smalldisk:latest' `
      --admin-username fbadmin --admin-password "@$adminFile" `
      --nsg "$Name-nsg" --public-ip-sku Standard --storage-sku StandardSSD_LRS --os-disk-size-gb 64 `
      --vnet-name "$Name-vnet" --subnet default --tags stage=created -o none
  }
  $vm = AzJson vm show -g $ResourceGroup -n $Name
  if ($vm.identity) { throw 'the VM has a managed identity - remove it before reviewers get access' }
  $rules = AzJson network nsg rule list -g $ResourceGroup --nsg-name "$Name-nsg"
  if (@($rules | Where-Object { $_.direction -eq 'Inbound' -and $_.access -eq 'Allow' }).Count -gt 0) { throw 'an inbound allow rule exists - stop' }
  $stage = Stage
  if ($stage -notin 'created','user','seeded','locked') { throw "unknown stage tag '$stage' - refusing" }
  if ($stage -eq 'locked') { throw 'this VM is locked (reviewers may have had access). Never re-run the in-VM steps; rebuild instead.' }

  Step 'Bastion Developer (free)'
  try { Az network bastion show -g $ResourceGroup -n "$Name-bastion" -o none }
  catch {
    try { Az network bastion create -g $ResourceGroup -n "$Name-bastion" --sku Developer --vnet-name "$Name-vnet" -l $Location -o none }
    catch { Write-Warning "Bastion Developer not created by CLI. Use Portal > $Name > Connect > Bastion > Developer. ($_)" }
  }

  if ($stage -eq 'created') {
    Step 'Demo user, auto-logon, app task'
    $userPw = NewPassword
    $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($userPw))
    $protFile = SecretFile "ReviewPasswordB64=$b64"
    $b64 = $null
    try {
      Az vm run-command create -g $ResourceGroup --vm-name $Name --name setup-user --script "@$here\vm\setup-user.ps1" `
        --parameters "ReviewUser=$ReviewUser" --protected-parameters "@$protFile" --timeout-in-seconds 900 -o none
      $st = AzJson vm run-command show -g $ResourceGroup --vm-name $Name --name setup-user --instance-view
      $out = "$($st.instanceView.output)"
    } finally {
      # never leave the stored protected parameters on the VM, whatever happened
      try { Az vm run-command delete -g $ResourceGroup --vm-name $Name --name setup-user --yes -o none } catch { Write-Warning "run-command delete failed: $_" }
    }
    if ($out -notmatch 'SETUP-USER:OK') { throw "setup-user failed: $out $($st.instanceView.error)" }
    Write-Host $out
    # The password goes to a Key Vault in THIS resource group (deleted with it), so whoever signs in over
    # Bastion picks it from the vault in the portal ("Password from Azure Key Vault") and it never passes
    # through chat. Read access: the signed-in az account only (RBAC).
    Step 'Store the demo-user password in the review Key Vault'
    $h = [Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($rgId.ToLower()))
    $kvName = 'fbrev' + (-join ($h[0..5] | ForEach-Object { $_.ToString('x2') }))   # stable, globally unique-ish
    try { Az keyvault show -n $kvName -g $ResourceGroup -o none }
    catch { Az keyvault create -n $kvName -g $ResourceGroup -l $Location --enable-rbac-authorization true --retention-days 7 -o none }
    $kvId = (AzJson keyvault show -n $kvName -g $ResourceGroup).id
    $me = "$(Az ad signed-in-user show --query id -o tsv)".Trim()
    try { Az role assignment create --assignee-object-id $me --assignee-principal-type User --role 'Key Vault Secrets Officer' --scope $kvId -o none } catch { Write-Warning "role assignment: $_" }
    $pwFile = SecretFile $userPw
    $stored = $false
    for ($i = 1; $i -le 8 -and -not $stored; $i++) {   # RBAC takes a minute or two to apply
      try { Az keyvault secret set --vault-name $kvName -n 'fbreview-password' --file $pwFile --encoding utf-8 -o none; $stored = $true }
      catch { Start-Sleep -Seconds 20 }
    }
    if (-not $stored) { throw "could not store the password in $kvName" }
    $userPw = $null
    Write-Host "demo-user password stored: vault $kvName, secret fbreview-password"
    SetStage 'user'; $stage = 'user'
    Step 'Restart for auto-logon'
    Az vm restart -g $ResourceGroup -n $Name -o none
  }

  if ($stage -eq 'user') {
    Step 'Wait for the profile and the Folderbird app'
    $ready = $false
    for ($i = 1; $i -le 12 -and -not $ready; $i++) {
      try { $p = InVm 'probe.ps1' 'PROBE' @("ReviewUser=$ReviewUser") } catch { $p = "probe error: $_" }
      Write-Host "  try $i : $p"
      $ready = $p -match 'READY'; if (-not $ready) { Start-Sleep -Seconds 30 }
    }
    if (-not $ready) { throw 'profile or app not ready after ~10 minutes (check %LOCALAPPDATA%\FolderbirdDemo\app-start.log on the VM)' }

    Step 'Seed fictional documents'
    $zip = Join-Path $here 'seed\seed-docs.zip'
    $sha = (Get-FileHash $zip -Algorithm SHA256).Hash
    $data = [Convert]::ToBase64String([IO.File]::ReadAllBytes($zip))
    InVm 'seed-docs.ps1' 'RESET' @('Part=reset') | Out-Null
    $chunk = 20000   # a Windows command line holds at most 32,767 characters
    for ($i = 0; $i -lt $data.Length; $i += $chunk) {
      InVm 'seed-docs.ps1' 'APPEND' @('Part=append', "Data=$($data.Substring($i, [Math]::Min($chunk, $data.Length - $i)))") | Out-Null
    }
    Write-Host (InVm 'seed-docs.ps1' 'SEED-DOCS' @('Part=finish', "Sha256=$sha", "ReviewUser=$ReviewUser"))

    Step 'Seed public-domain photos'
    Write-Host (InVm 'seed-photos.ps1' 'SEED-PHOTOS' @("ReviewUser=$ReviewUser"))
    SetStage 'seeded'; $stage = 'seeded'
  }

  if ($stage -eq 'seeded') {
    Step 'Outbound lock'
    LockEgress
    CheckEgress
    SetStage 'locked'
  }

  Step 'Done'
  Write-Host @"
Next, Majid only:
 1. Portal > $Name > Connect > Bastion (Developer). User .\$ReviewUser, password from Key Vault (vault 'fbrev...' in $ResourceGroup, secret fbreview-password).
 2. Sign the Folderbird app (tray) into the REVIEWER account only. Never sign Edge or anything else into a
    Microsoft/Google account, and clear the browser's saved logins before you leave: reviewers can read it all.
 3. Close the Bastion TAB. Do not sign out of Windows (if you do, auto-logon brings the user back).
 4. folderbird.com > My Devices must show '$Name' as Connected.
 5. Then run this script again with -ArmAutoLogon (a logoff by anyone then logs the demo user back on).
"@
  Write-Host 'BUILD:OK'
}
catch { Write-Host "BUILD:FAILED $step : $_" -ForegroundColor Red; throw }
finally {
  foreach ($f in $secretFiles) { Remove-Item $f -Force -ErrorAction SilentlyContinue }
  if ($prevSub -and $prevSub -ne $SubscriptionId) { try { Az account set --subscription $prevSub } catch { } }
  try { Stop-Transcript | Out-Null } catch { }
  $lock.Dispose()
}
