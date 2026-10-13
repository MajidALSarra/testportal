# Runs INSIDE the reviewer demo VM as SYSTEM. Downloads public-domain / CC0 photos from Wikimedia
# Commons, re-encodes each one (which drops EXIF, GPS and every other metadata block) and writes a
# CREDITS.txt. The license is read from Commons' own metadata per file; anything that is not CC0 or
# public domain is skipped. Needs at least $Min photos or it fails.
param([string]$ReviewUser = 'fbreview', [int]$Want = 8, [int]$Min = 5)
$ErrorActionPreference = 'Stop'
# Run only AFTER the first auto-logon has created the profile: writing C:\Users\<user> before that
# makes Windows give the user a new C:\Users\<user>.<PC> profile and these files are lost to it.
if (-not (Test-Path "C:\Users\$ReviewUser\NTUSER.DAT")) { throw "profile for $ReviewUser not created yet - reboot for auto-logon first" }
Add-Type -AssemblyName System.Drawing
[Net.ServicePointManager]::SecurityProtocol = 'Tls12'
$ua  = @{ 'User-Agent' = 'FolderbirdDemoSeed/1.0 (https://folderbird.com/Contact)' }
$out = "C:\Users\$ReviewUser\Pictures"
New-Item -ItemType Directory -Force -Path $out | Out-Null
$cats = 'Featured_pictures_of_landscapes','Featured_pictures_of_plants','Featured_pictures_of_animals','Featured_pictures_of_architecture'
$jpeg = [Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object MimeType -eq 'image/jpeg'
$ep = New-Object Drawing.Imaging.EncoderParameters 1
$ep.Param[0] = New-Object Drawing.Imaging.EncoderParameter ([Drawing.Imaging.Encoder]::Quality), 88L
$credits = @('Photos on this demo PC. Each is public domain or CC0 on Wikimedia Commons; metadata removed.', '')
$n = 0
foreach ($c in $cats) {
  if ($n -ge $Want) { break }
  $api = "https://commons.wikimedia.org/w/api.php?action=query&format=json&generator=categorymembers&gcmtitle=Category:$c&gcmtype=file&gcmlimit=100&prop=imageinfo&iiprop=url|mime|extmetadata&iiurlwidth=2000&iiextmetadatafilter=LicenseShortName"
  $r = Invoke-RestMethod -Uri $api -Headers $ua
  if (-not $r.query) { continue }
  foreach ($p in $r.query.pages.PSObject.Properties.Value) {
    if ($n -ge $Want) { break }
    $ii = $p.imageinfo[0]
    $lic = "$($ii.extmetadata.LicenseShortName.value)"
    if ($ii.mime -ne 'image/jpeg' -or $lic -notmatch '^(CC0|Public domain)') { continue }
    $tmp = Join-Path $env:TEMP ("fbphoto-$n.jpg")
    try { Invoke-WebRequest -UseBasicParsing -Uri $ii.thumburl -Headers $ua -OutFile $tmp } catch { continue }
    $name = ($p.title -replace '^File:','' -replace '\.[^.]+$','' -replace '[^A-Za-z0-9 _-]','' -replace '\s+','-')
    if ($name.Length -gt 50) { $name = $name.Substring(0,50) }
    $dest = Join-Path $out "$name.jpg"
    $img = [Drawing.Image]::FromFile($tmp)
    try { $bmp = New-Object Drawing.Bitmap $img; $bmp.Save($dest, $jpeg, $ep); $bmp.Dispose() } finally { $img.Dispose() }
    Remove-Item $tmp
    $chk = [Drawing.Image]::FromFile($dest); $meta = $chk.PropertyIdList.Count; $chk.Dispose()
    if ($meta -gt 0) { Remove-Item $dest; continue }   # never keep a file that still carries metadata
    $credits += "$name.jpg - $lic - $($ii.descriptionurl)"
    $n++
  }
}
Set-Content -Path (Join-Path $out 'CREDITS.txt') -Value $credits -Encoding UTF8
if ($n -lt $Min) { throw "only $n photos passed the license and metadata checks" }
"SEED-PHOTOS:OK $n photos"
