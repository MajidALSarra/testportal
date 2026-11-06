# vm-scrub - runs INSIDE the throwaway VM fb-e2e2c-win as SYSTEM ('az vm run-command invoke'), after vm-check has
# shown the token migrated to host.dat. Blanks every copy of the token-injection script that the run-command
# extension or the guest agent left on disk under C:\Packages\Plugins and C:\WindowsAzure (logs, cached
# goal-state/extension config), found by the injection script's FIRST
# line (its marker) as plain text, as UTF-16 text, or as the start of a base64 copy - never by the token, which this
# script does not know. The marker is assembled at run time so this script cannot match itself. A copy held only in
# encrypted protected settings cannot be found this way and goes with the VM. Also re-confirms host.txt is gone.
# Prints SCRUB DONE.
$ErrorActionPreference = 'Continue'
if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess -and $PSCommandPath) {
  & (Join-Path $env:windir 'sysnative\WindowsPowerShell\v1.0\powershell.exe') -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath
  exit $LASTEXITCODE
}
if ($env:COMPUTERNAME -ne 'FB-E2E2C-WIN') { Write-Output ('SCRUB FAILED: this is ' + $env:COMPUTERNAME + ', not FB-E2E2C-WIN'); exit 1 }
$mk = 'FBE2E-TOKEN-' + 'INJECT-v1'
# vm-token.ps1 starts with "# " + marker; its first 21 bytes ("# " + the marker without its last 2 characters) are
# exactly 28 base64 characters, so any base64 copy of the whole script starts with them.
$mk64 = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes('# ' + $mk.Substring(0, 19)))
$scanned = 0; $hit = @(); $failed = @()
foreach ($root in 'C:\Packages\Plugins', 'C:\WindowsAzure') {
  if (-not (Test-Path -LiteralPath $root)) { continue }
  foreach ($f in @(Get-ChildItem -LiteralPath $root -Recurse -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.Length -gt 0 -and $_.Length -lt 20MB -and $_.Extension -notin '.dll', '.exe', '.msi', '.zip', '.cab' })) {
    $scanned++
    try { $bytes = [IO.File]::ReadAllBytes($f.FullName) } catch { continue }
    $a = [Text.Encoding]::ASCII.GetString($bytes)
    $found = $a.Contains($mk) -or $a.Contains($mk64)
    if (-not $found) { $found = [Text.Encoding]::Unicode.GetString($bytes).Contains($mk) }
    $a = $null; $bytes = $null
    if ($found) {
      try { [IO.File]::WriteAllBytes($f.FullName, (New-Object byte[] 0)); $hit += $f.FullName }
      catch { $failed += ($f.FullName + ' (' + $_.Exception.Message + ')') }
    }
  }
}
$rs = @(Get-ChildItem -Path 'C:\Packages\Plugins' -Recurse -File -Filter '*.settings' -ErrorAction SilentlyContinue | Where-Object { $_.FullName -like '*RunCommand*' })
Write-Output ('scanned {0} files under C:\Packages\Plugins and C:\WindowsAzure' -f $scanned)
foreach ($p in $hit) { Write-Output ('blanked: ' + $p) }
foreach ($p in $failed) { Write-Output ('could NOT blank: ' + $p) }
Write-Output ('run-command .settings files present: {0} (a copy held in encrypted protected settings, if any, goes with the VM)' -f $rs.Count)
Write-Output ('host.txt present: {0}' -f (Test-Path -LiteralPath 'C:\FolderbirdE2E\profile-win\host.txt'))
Write-Output ('SCRUB DONE blanked={0} failed={1}' -f $hit.Count, $failed.Count)
