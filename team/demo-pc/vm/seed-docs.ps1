# Runs INSIDE the reviewer demo VM as SYSTEM, ONCE, before any reviewer has access (never after: a reviewer
# could swap these folders for junctions). The seed-docs zip arrives base64 in chunks (command-line cap):
#   -Part reset                          (clear leftovers from an earlier try)
#   -Part append -Data <base64 chunk>    (repeat)
#   -Part finish -Sha256 <hex>           (decode, check hash, extract into the user's profile)
param([Parameter(Mandatory)][ValidateSet('reset','append','finish')][string]$Part, [string]$Data, [string]$Sha256,
      [string]$ReviewUser = 'fbreview')
$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue'
$dir = 'C:\ProgramData\FolderbirdDemo'; $b64 = Join-Path $dir 'seed-docs.b64'; $zip = Join-Path $dir 'seed-docs.zip'
if ($Part -eq 'reset') { Remove-Item $b64, $zip -Force -ErrorAction SilentlyContinue; 'RESET:OK'; return }
if ($Part -eq 'append') { Add-Content -Path $b64 -Value $Data -NoNewline; "APPEND:OK $((Get-Item $b64).Length)"; return }

# The user's real profile, from its SID (a leftover folder makes Windows use C:\Users\<user>.<PC>).
$sid = (Get-LocalUser $ReviewUser).SID.Value
$userDir = (Get-CimInstance Win32_UserProfile | Where-Object SID -eq $sid).LocalPath
if (-not $userDir -or -not (Test-Path (Join-Path $userDir 'NTUSER.DAT'))) { throw "profile for $ReviewUser not created yet - auto-logon first" }
foreach ($d in 'Desktop','Documents','Documents\Reports') {
  $p = Join-Path $userDir $d
  if ((Test-Path $p) -and ((Get-Item $p -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "$p is a reparse point - refusing" }
}
try {
  [IO.File]::WriteAllBytes($zip, [Convert]::FromBase64String((Get-Content $b64 -Raw)))
  $h = (Get-FileHash $zip -Algorithm SHA256).Hash
  if ($h -ne $Sha256.ToUpper()) { throw "hash mismatch $h" }
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $z = [IO.Compression.ZipFile]::OpenRead($zip); $count = 0
  try {
    foreach ($e in $z.Entries) {
      if (-not $e.Name) { continue }
      $dest = [IO.Path]::GetFullPath((Join-Path $userDir $e.FullName))
      if (-not $dest.StartsWith($userDir + '\')) { throw "unsafe entry $($e.FullName)" }
      New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
      [IO.Compression.ZipFileExtensions]::ExtractToFile($e, $dest, $true); $count++
    }
  } finally { $z.Dispose() }
} finally { Remove-Item $b64, $zip -Force -ErrorAction SilentlyContinue }   # a failed try never poisons the next
# Files written by SYSTEM: give the user ownership so they behave like the user's own files.
icacls (Join-Path $userDir 'Documents') /setowner $ReviewUser /T /C /Q | Out-Null
icacls (Join-Path $userDir 'Desktop') /setowner $ReviewUser /T /C /Q | Out-Null
"SEED-DOCS:OK $count files"
