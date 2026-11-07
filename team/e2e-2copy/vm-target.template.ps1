# vm-target - switch the Windows test copy inside the throwaway VM fb-e2e2c-win to another server (runs as SYSTEM
# through 'az vm run-command invoke', started by v7-vm-target.ps1, which fills in the target url below and checks it). No secret
# here: the device token (host.dat) stays as it is, because a device token is valid on both slots (one database, one
# token key). It (1) writes the test profile's base-url.txt (the app appends /api itself), the same way the provisioner
# wrote it: ASCII, no BOM, no newline; (2) stops ONLY FolderbirdClient processes whose executable is exactly the test
# copy's exe, never any other process; (3) waits up to 120 s for the logon wrapper run-e2e-copy.ps1 to start a new one
# (it waits 30 s after an exit). The key facts come LAST: run-command returns only the last 4 KB. Ends with TARGET DONE.
$ErrorActionPreference = 'Continue'
if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess -and $PSCommandPath) {
  & (Join-Path $env:windir 'sysnative\WindowsPowerShell\v1.0\powershell.exe') -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath
  exit $LASTEXITCODE
}
$Prof = 'C:\FolderbirdE2E\profile-win'
$Exe  = 'C:\FolderbirdE2E\app-1.2.8.1\FolderbirdClient.exe'
$Want = '__TARGETURL__'
function O([string]$m) { Write-Output $m }
function Red([string]$s) { [regex]::Replace($s, '-[A-Za-z0-9+/]{40,}={0,2}', '[token-redacted]') }
function Cut([string]$s) { if ($s.Length -gt 220) { $s.Substring(0, 220) + '...' } else { $s } }
function Tail([string]$path, [int]$count) {
  if (Test-Path -LiteralPath $path) {
    O ('--- tail of {0}' -f $path)
    foreach ($ln in @(Get-Content -LiteralPath $path -Tail $count -ErrorAction SilentlyContinue)) { if ([string]$ln) { O (Cut (Red ([string]$ln))) } }
  } else { O ('--- {0}: absent' -f $path) }
}
function TestApps { @(Get-CimInstance Win32_Process -Filter "Name='FolderbirdClient.exe'" | Where-Object { ([string]$_.ExecutablePath) -ieq $Exe }) }
if ($env:COMPUTERNAME -ne 'FB-E2E2C-WIN') { O ('TARGET FAILED: this is ' + $env:COMPUTERNAME + ', not FB-E2E2C-WIN'); exit 1 }
if ($Want -cne 'https://folderbird-app-staging.azurewebsites.net' -and $Want -cne 'https://folderbird-app.azurewebsites.net') { O ('TARGET FAILED: unexpected url ' + $Want); exit 1 }
$bu = Join-Path $Prof 'base-url.txt'
if (-not (Test-Path -LiteralPath $Prof)) { O ('TARGET FAILED: no test profile at ' + $Prof); exit 1 }
$old = '(absent)'; if (Test-Path -LiteralPath $bu) { $old = [IO.File]::ReadAllText($bu) }
[IO.File]::WriteAllText($bu, $Want, (New-Object System.Text.ASCIIEncoding))
$now = [IO.File]::ReadAllText($bu)
$before = @(TestApps | ForEach-Object { [int]$_.ProcessId })
$stopped = @()
foreach ($p in $before) {
  try { Stop-Process -Id $p -Force -ErrorAction Stop; $stopped += $p } catch { O ('stop of pid {0} failed: {1}' -f $p, $_.Exception.Message) }
}
$new = $null
for ($i = 0; $i -lt 24 -and $null -eq $new; $i++) {
  Start-Sleep -Seconds 5
  $new = @(TestApps | Where-Object { $before -notcontains [int]$_.ProcessId }) | Select-Object -First 1
}
Tail 'C:\FolderbirdE2E\logs\wrapper.log' 5
Tail (Join-Path $Prof 'client-errors.log') 6
O '--- key facts'
O ('base-url.txt before: {0}' -f $old)
O ('base-url.txt now:    {0}' -f $now)
O ('test app pids before: {0}; stopped: {1}' -f ($before -join ','), ($stopped -join ','))
if ($null -ne $new) {
  O ('TARGET DONE base-url={0} newpid={1} started={2:u}' -f $now, $new.ProcessId, ([datetime]$new.CreationDate).ToUniversalTime())
} else {
  O ('TARGET DONE base-url={0} newpid=NONE (no new test app process within 120 s; check the wrapper log above)' -f $now)
}
