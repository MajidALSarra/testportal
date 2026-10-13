# Read-only check, run as SYSTEM after the outbound lock: Folderbird must be reachable, the open internet not.
$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = 'Tls12'
# Reached = any HTTP answer at all (even 4xx); not reached = connect/timeout failure.
function Reach($u) { try { Invoke-WebRequest -UseBasicParsing -Uri $u -TimeoutSec 15 -Method Head | Out-Null; $true } catch { $null -ne $_.Exception.Response } }
$site = Reach 'https://folderbird.com/Account/Login'
$app  = Reach 'https://folderbird-app.azurewebsites.net/Account/Login'
$blob = Reach 'https://folderbirdfiles.blob.core.windows.net/'
$open = Reach 'https://example.com/'
$proc = @(Get-Process FolderbirdClient -ErrorAction SilentlyContinue).Count
"EGRESS:OK site=$site apphost=$app blob=$blob open-internet=$open app=$proc"
