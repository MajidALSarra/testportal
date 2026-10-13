# Read-only probe, run as SYSTEM. READY when the review user's profile exists and the Folderbird app runs
# in that user's session. Changes nothing.
param([string]$ReviewUser = 'fbreview')
$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue'
$sid = (Get-LocalUser $ReviewUser).SID.Value
$prof = (Get-CimInstance Win32_UserProfile | Where-Object SID -eq $sid).LocalPath
$app = @(Get-Process FolderbirdClient -IncludeUserName -ErrorAction SilentlyContinue | Where-Object UserName -like "*\$ReviewUser")
$state = if ($prof -and (Test-Path (Join-Path $prof 'NTUSER.DAT')) -and $app.Count -gt 0) { 'READY' } else { 'WAIT' }
"PROBE:OK $state profile=$prof app=$($app.Count)"
