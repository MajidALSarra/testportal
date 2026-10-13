# Builds the ChatGPT-reviewer demo PC. Run on the laptop (az signed in), in a VISIBLE PowerShell window,
# ONLY after Majid's typed go. Every resource lives in its own resource group, so
#   az group delete -n folderbird-review-rg
# removes all of it (that delete also needs Majid's go).
#
#   Set-ExecutionPolicy -Scope Process Bypass
#   .\new-review-vm.ps1 -AlertEmail <owner email>            # create + set up (asks for the demo-user password)
#   .\new-review-vm.ps1 -AlertEmail <owner email> -WhatIf    # print the plan, change nothing
#
# What it makes (West Europe):
#   * VM fb-review: Windows Server 2022 Azure Edition (small disk image, 64 GB Standard SSD), Standard_B2s.
#   * NSG with NO inbound allow rules. Admin work goes through run-command (SYSTEM); Majid reaches the
#     desktop once through Bastion Developer (free) to sign the app in.
#   * A Standard public IP for OUTBOUND only (new VNets no longer get default outbound internet); the NSG
#     blocks everything inbound.
#   * Admin account with a random password that is never shown or stored - nobody needs it.
#   * Standard local user 'fbreview' (password typed by Majid, masked) that auto-logs on and runs the app.
#   * Budget alert on the resource group: 50 / 80 / 100 % of $60 a month, by email.
# Not done: no auto-shutdown (reviewers test at any hour), no managed identity, no az/gh/keys on the VM.
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$AlertEmail,
  [string]$ResourceGroup = 'folderbird-review-rg',
  [string]$Location      = 'westeurope',
  [string]$Name          = 'fb-review',
  [string]$Size          = 'Standard_B2s',
  [string]$ReviewUser    = 'fbreview',
  [int]   $BudgetUsd     = 60,
  [switch]$WhatIf
)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$env:AZURE_EXTENSION_USE_DYNAMIC_INSTALL = 'yes_without_prompt'   # az must never wait on stdin

# az.cmd is broken on this laptop and routes arguments through cmd.exe; call the CLI's python directly.
$py = 'C:\Program Files\Microsoft SDKs\Azure\CLI2\python.exe'
if (-not (Test-Path -LiteralPath $py)) { throw "Azure CLI python not found at $py" }
# No param block on purpose: every token lands in $args verbatim (a param block makes -o ambiguous).
# stderr goes to a file, never merged: under 'Stop' a merged warning line throws NativeCommandError in 5.1.
function Az {
  $ef = [IO.Path]::GetTempFileName(); $ErrorActionPreference = 'Continue'
  $out = & $py -m azure.cli @args 2> $ef; $code = $LASTEXITCODE
  $err = Get-Content $ef -Raw; Remove-Item $ef
  if ($code -ne 0) { throw "az $($args[0]) $($args[1]) failed ($code): $err" }
  $out
}
function AzJson { (Az @args -o json | Out-String) | ConvertFrom-Json }
function Step($t) { Write-Host "`n== $t" -ForegroundColor Cyan }

Step 'Subscription'
$acct = AzJson account show
Write-Host "$($acct.name) ($($acct.id)) as $($acct.user.name)"
if ($WhatIf) { Write-Host "WhatIf: would create $ResourceGroup / $Name ($Size) in $Location, budget `$$BudgetUsd to $AlertEmail"; return }

# Passwords: the admin one is random and discarded; the demo-user one is typed by Majid.
$alpha = [char[]]'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789'
$bytes = New-Object byte[] 28; [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
$adminPw = 'Fb9!' + (-join ($bytes | ForEach-Object { $alpha[$_ % $alpha.Length] }))
$s1 = Read-Host "Password for the demo user '$ReviewUser' (12+ chars, upper/lower/digit/symbol, no double quote)" -AsSecureString
$s2 = Read-Host 'Again' -AsSecureString
$u1 = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($s1))
$u2 = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($s2))
if ($u1 -ne $u2) { throw 'passwords differ' }
if ($u1.Length -lt 12 -or $u1 -match '"') { throw 'password too short or contains a double quote' }

Step 'Resource group'
Az group create -n $ResourceGroup -l $Location --tags purpose=chatgpt-reviewer-demo owner=magpie -o none

Step 'Network security group (no inbound rules)'
Az network nsg create -g $ResourceGroup -n "$Name-nsg" -o none

Step 'Virtual machine'
Az vm create -g $ResourceGroup -n $Name --size $Size `
  --image 'MicrosoftWindowsServer:WindowsServer:2022-datacenter-azure-edition-smalldisk:latest' `
  --admin-username fbadmin --admin-password $adminPw `
  --nsg "$Name-nsg" --public-ip-sku Standard --storage-sku StandardSSD_LRS --os-disk-size-gb 64 `
  --vnet-name "$Name-vnet" --subnet default -o none
$adminPw = $null
$rules = AzJson network nsg rule list -g $ResourceGroup --nsg-name "$Name-nsg"
if (@($rules | Where-Object { $_.direction -eq 'Inbound' -and $_.access -eq 'Allow' }).Count -gt 0) { throw 'an inbound allow rule exists - stop' }

Step 'Bastion Developer (free)'
try { Az network bastion create -g $ResourceGroup -n "$Name-bastion" --sku Developer --vnet-name "$Name-vnet" -l $Location -o none }
catch { Write-Warning "Bastion Developer not created by CLI ($_). Use Portal > $Name > Connect > Bastion > Developer instead." }

Step 'Budget alert'
$rgId = (AzJson group show -n $ResourceGroup).id
$start = (Get-Date -Day 1).ToString('yyyy-MM-01')
$body = @{ properties = @{ category = 'Cost'; amount = $BudgetUsd; timeGrain = 'Monthly'
  timePeriod = @{ startDate = $start; endDate = (Get-Date).AddYears(1).ToString('yyyy-MM-01') }
  notifications = @{
    actual50  = @{ enabled = $true; operator = 'GreaterThan'; threshold = 50;  thresholdType = 'Actual';     contactEmails = @($AlertEmail) }
    actual80  = @{ enabled = $true; operator = 'GreaterThan'; threshold = 80;  thresholdType = 'Actual';     contactEmails = @($AlertEmail) }
    actual100 = @{ enabled = $true; operator = 'GreaterThan'; threshold = 100; thresholdType = 'Actual';     contactEmails = @($AlertEmail) }
    fcast100  = @{ enabled = $true; operator = 'GreaterThan'; threshold = 100; thresholdType = 'Forecasted'; contactEmails = @($AlertEmail) } } } }
$bf = Join-Path $env:TEMP 'fb-review-budget.json'; $body | ConvertTo-Json -Depth 6 | Set-Content $bf -Encoding ASCII
Az rest --method put --url "https://management.azure.com$rgId/providers/Microsoft.Consumption/budgets/fb-review-budget?api-version=2023-05-01" --body "@$bf" -o none
Remove-Item $bf

Step 'Demo user, auto-logon, app logon task (run-command as SYSTEM)'
# Managed run-command: the password goes in --protected-parameters, which Azure never returns or logs.
Az vm run-command create -g $ResourceGroup --vm-name $Name -n setup-user --script "@$here\vm\setup-user.ps1" `
  --parameters "ReviewUser=$ReviewUser" --protected-parameters "ReviewPassword=$u1" --timeout-in-seconds 600 -o none
$u1 = $null; $u2 = $null
$st = AzJson vm run-command show -g $ResourceGroup --vm-name $Name -n setup-user --instance-view
Write-Host $st.instanceView.output
if ($st.instanceView.output -notmatch 'SETUP-USER:OK') { throw "setup-user failed: $($st.instanceView.error)" }

Step 'Restart: auto-logon creates the profile, the logon task installs and starts Folderbird'
Az vm restart -g $ResourceGroup -n $Name -o none
Start-Sleep -Seconds 120

Step 'Seed fictional documents'
$zip = Join-Path $here 'seed\seed-docs.zip'                  # built by seed\make_seed_files.py, committed
$sha = (Get-FileHash $zip -Algorithm SHA256).Hash
$b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($zip))
$chunk = 20000   # a Windows command line holds at most 32,767 characters
for ($i = 0; $i -lt $b64.Length; $i += $chunk) {
  $part = $b64.Substring($i, [Math]::Min($chunk, $b64.Length - $i))
  Az vm run-command invoke -g $ResourceGroup -n $Name --command-id RunPowerShellScript --scripts "@$here\vm\seed-docs.ps1" `
    --parameters "Part=append" "Data=$part" "ReviewUser=$ReviewUser" -o none
}
$r = AzJson vm run-command invoke -g $ResourceGroup -n $Name --command-id RunPowerShellScript --scripts "@$here\vm\seed-docs.ps1" `
  --parameters "Part=finish" "Sha256=$sha" "ReviewUser=$ReviewUser"
Write-Host $r.value[0].message

Step 'Seed public-domain photos (metadata removed)'
$r = AzJson vm run-command invoke -g $ResourceGroup -n $Name --command-id RunPowerShellScript --scripts "@$here\vm\seed-photos.ps1" `
  --parameters "ReviewUser=$ReviewUser"
Write-Host $r.value[0].message

Step 'Done'
Write-Host @"
Next, Majid only:
 1. Portal > $Name > Connect > Bastion (Developer). Sign in as .\$ReviewUser with the password you typed.
 2. The Folderbird app should be open (or in the tray). Sign it into the reviewer account.
 3. Close the Bastion TAB. Do NOT sign out of Windows - the app runs in that session.
 4. Check folderbird.com > My Devices shows '$Name' as Connected.
Delete everything later with: az group delete -n $ResourceGroup   (needs Majid's go)
"@
