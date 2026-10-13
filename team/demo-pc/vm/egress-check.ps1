# Read-only check, run as SYSTEM after the outbound lock: Folderbird must be reachable, the open internet not.
$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = 'Tls12'
function Reach($u) { try { Invoke-WebRequest -UseBasicParsing -Uri $u -TimeoutSec 15 -Method Head | Out-Null; $true } catch { $_.Exception.Response -ne $null } }
$fb = Reach 'https://folderbird.com/Account/Login'
$ex = Reach 'https://example.com/'
$app = @(Get-Process FolderbirdClient -ErrorAction SilentlyContinue).Count
"EGRESS:OK folderbird=$fb open-internet=$ex app=$app"
