# FBE2E-TOKEN-INJECT-v1  (marker line: vm-scrub.ps1 finds leftover copies of this script by it; never print it)
# vm-token - runs INSIDE the throwaway VM fb-e2e2c-win as SYSTEM ('az vm run-command invoke'). v4-vm-token.ps1 builds
# it from vm-token.template.ps1 by putting the device token (from t-device-token.ps1 -Device win) where the placeholder is, and blanks its own filled copy
# right after the call. The token is written as the app's LEGACY cleartext token file <profile>\host.txt, readable
# only by the autologon user fbe2e and SYSTEM. At its next start the 1.2.8.1 app, running as fbe2e, reads host.txt,
# re-saves it DPAPI-encrypted (CurrentUser) as host.dat and deletes host.txt (folderbird-agent main 1f14100,
# FileRouteClient/Utils.cs LoadToken 376-401 -> SaveToken 349-372; profile mode puts both files in the profile dir,
# Utils.cs 276-287, 344-346). An existing host.dat is removed first, because LoadToken prefers it over host.txt.
# Stops the running test copy first (the wrapper, then the app) so an old token cannot be re-saved in between.
# Never prints the token: only its length. Blanks its own script file in the run-command download folder at the end.
# Idempotent: a second run with the same token (hash kept in C:\FolderbirdE2E\logs\injected.sha256) changes nothing.
# Prints INJECT DONE ... or INJECT FAILED line N: message.
$ErrorActionPreference = 'Stop'
if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
  if (-not $PSCommandPath) { Write-Output 'INJECT FAILED line 0: 32-bit PowerShell and no script path to relaunch'; exit 1 }
  & (Join-Path $env:windir 'sysnative\WindowsPowerShell\v1.0\powershell.exe') -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath
  exit $LASTEXITCODE
}
$Prof = 'C:\FolderbirdE2E\profile-win'
$User = 'fbe2e'
$Addr = '02E2E2C00002'
$Base = 'https://folderbird-app-staging.azurewebsites.net'
function RunExe([string]$exe, [string]$argline) {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $exe; $psi.Arguments = $argline; $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
  $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
  $pr = [System.Diagnostics.Process]::Start($psi)
  $t1 = $pr.StandardOutput.ReadToEndAsync(); $t2 = $pr.StandardError.ReadToEndAsync(); $pr.WaitForExit()
  New-Object PSObject -Property @{ Code = $pr.ExitCode; Out = $t1.Result; Err = $t2.Result }
}
# Overwrites THIS script's file (the run-command extension's plaintext copy of it). PowerShell has already parsed
# the whole file, so this is safe while running.
function BlankSelf {
  try {
    if ($PSCommandPath -and (Test-Path -LiteralPath $PSCommandPath)) { [IO.File]::WriteAllText($PSCommandPath, '# blanked after use'); return 'yes' }
  } catch { return ('no (' + $_.Exception.Message + ')') }
  return 'no (not run from a file)'
}
$tk = $null
try {
  if ($env:COMPUTERNAME -ne 'FB-E2E2C-WIN') { throw ('refusing to run on ' + $env:COMPUTERNAME + ': this script is only for the throwaway VM FB-E2E2C-WIN') }
  $tk = '__TOKEN__'
  if ($tk -notmatch '^-[A-Za-z0-9+/]+={0,2}$') { throw 'the token was not filled in, or is not token-shaped (value not shown)' }
  if (-not (Get-LocalUser -Name $User -ErrorAction SilentlyContinue)) { throw ('user ' + $User + ' does not exist - run v2-vm-provision.ps1 first') }
  $a = [IO.File]::ReadAllText((Join-Path $Prof 'address.txt')).Trim()
  if ($a -ne $Addr) { throw ('profile address.txt is ' + $a + ', expected ' + $Addr + ' (the token is bound to ' + $Addr + ')') }
  $bu = [IO.File]::ReadAllText((Join-Path $Prof 'base-url.txt')).Trim()
  if ($bu -ne $Base) { throw ('profile base-url.txt is ' + $bu + ', expected the staging host') }

  # A run with the SAME token as the last successful one changes nothing and stops nothing (for example if the
  # run-command extension runs this script again after the reboot): it would otherwise kill the running test copy.
  $sha = [Security.Cryptography.SHA256]::Create()
  $th = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::ASCII.GetBytes($tk)))).Replace('-', '')
  $mark = 'C:\FolderbirdE2E\logs\injected.sha256'
  $hd = Join-Path $Prof 'host.dat'; $ht = Join-Path $Prof 'host.txt'
  if ((Test-Path -LiteralPath $mark) -and ([IO.File]::ReadAllText($mark).Trim() -eq $th) -and ((Test-Path -LiteralPath $hd) -or (Test-Path -LiteralPath $ht))) {
    $tk = $null
    $self = BlankSelf
    Write-Output ('INJECT DONE already injected (same token as the last run): nothing changed, nothing stopped; host.dat present: {0}; own script copy blanked: {1}' -f (Test-Path -LiteralPath $hd), $self)
    exit 0
  }

  # Stop the test copy: wrapper first (it would start the app again), then the app.
  $stopped = 0
  foreach ($pp in @(Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'powershell.exe' -and ([string]$_.CommandLine) -like '*run-e2e-copy.ps1*' })) {
    Stop-Process -Id $pp.ProcessId -Force -ErrorAction SilentlyContinue; $stopped++
  }
  foreach ($pp in @(Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'FolderbirdClient.exe' -and ([string]$_.ExecutablePath) -like 'C:\FolderbirdE2E\*' })) {
    Stop-Process -Id $pp.ProcessId -Force -ErrorAction SilentlyContinue; $stopped++
  }
  if ($stopped -gt 0) { Start-Sleep -Seconds 3 }

  $hadDat = Test-Path -LiteralPath $hd
  if ($hadDat) { Remove-Item -LiteralPath $hd -Force }
  [IO.File]::WriteAllText($ht, $tk, (New-Object System.Text.ASCIIEncoding))     # no newline; LoadToken trims anyway
  $n = $tk.Length; $tk = $null
  $acct = $env:COMPUTERNAME + '\' + $User
  $r = RunExe (Join-Path $env:SystemRoot 'System32\icacls.exe') ('"{0}" /inheritance:r /grant:r "{1}:(F)" "*S-1-5-18:(F)"' -f $ht, $acct)
  if ($r.Code -ne 0) { Remove-Item -LiteralPath $ht -Force; throw ('icacls on host.txt failed, file removed: ' + $r.Out.Trim() + ' ' + $r.Err.Trim()) }
  $ids = @((Get-Acl -LiteralPath $ht).Access | ForEach-Object { [string]$_.IdentityReference }) | Sort-Object -Unique
  $bad = @($ids | Where-Object { $_ -ne $acct -and $_ -ne 'NT AUTHORITY\SYSTEM' })
  if ($bad.Count -gt 0) { Remove-Item -LiteralPath $ht -Force; throw ('host.txt ACL still lists ' + ($bad -join ', ') + ' - file removed') }
  [IO.File]::WriteAllText($mark, $th)
  $self = BlankSelf
  Write-Output ('INJECT DONE host.txt {0} chars, ACL {1}; old host.dat removed: {2}; test-copy processes stopped: {3}; own script copy blanked: {4}' -f $n, ($ids -join ' + '), $hadDat, $stopped, $self)
} catch {
  $tk = $null
  $msg = 'INJECT FAILED line {0}: {1}' -f $_.InvocationInfo.ScriptLineNumber, $_.Exception.Message
  $self = BlankSelf
  Write-Output ($msg + ' (own script copy blanked: ' + $self + ')')
  exit 1
}
