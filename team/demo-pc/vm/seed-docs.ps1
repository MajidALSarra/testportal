# Runs INSIDE the reviewer demo VM as SYSTEM. The seed-docs zip (from ../seed/make_seed_files.py)
# arrives base64 in chunks, because a run-command script has a size cap:
#   -Part 'append' -Data <base64 chunk>   (repeat)
#   -Part 'finish' -Sha256 <hex>          (decode, check hash, extract into the user's profile)
param([Parameter(Mandatory)][ValidateSet('append','finish')][string]$Part, [string]$Data, [string]$Sha256, [string]$ReviewUser = 'fbreview')
$ErrorActionPreference = 'Stop'
# Run only AFTER the first auto-logon has created the profile: writing C:\Users\<user> before that
# makes Windows give the user a new C:\Users\<user>.<PC> profile and these files are lost to it.
if (-not (Test-Path "C:\Users\$ReviewUser\NTUSER.DAT")) { throw "profile for $ReviewUser not created yet - reboot for auto-logon first" }
$b64 = 'C:\ProgramData\FolderbirdDemo\seed-docs.b64'
New-Item -ItemType Directory -Force -Path (Split-Path $b64) | Out-Null
if ($Part -eq 'append') { Add-Content -Path $b64 -Value $Data -NoNewline; "APPEND:OK $((Get-Item $b64).Length)"; return }
$zip = 'C:\ProgramData\FolderbirdDemo\seed-docs.zip'
[IO.File]::WriteAllBytes($zip, [Convert]::FromBase64String((Get-Content $b64 -Raw)))
$h = (Get-FileHash $zip -Algorithm SHA256).Hash
if ($h -ne $Sha256.ToUpper()) { throw "hash mismatch $h" }
$userDir = "C:\Users\$ReviewUser"
Add-Type -AssemblyName System.IO.Compression.FileSystem
$z = [IO.Compression.ZipFile]::OpenRead($zip)
$count = 0
try {
  foreach ($e in $z.Entries) {
    if (-not $e.Name) { continue }
    $dest = [IO.Path]::GetFullPath((Join-Path $userDir $e.FullName))
    if (-not $dest.StartsWith($userDir + '\')) { throw "unsafe entry $($e.FullName)" }
    New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
    [IO.Compression.ZipFileExtensions]::ExtractToFile($e, $dest, $true); $count++
  }
} finally { $z.Dispose() }
Remove-Item $b64, $zip
"SEED-DOCS:OK $count files"
