# Runs INSIDE the reviewer demo VM as SYSTEM, ONCE, before any reviewer has access. Downloads CC0 /
# public-domain photos from Wikimedia Commons (license read per file from Commons' own metadata),
# re-encodes each (dropping EXIF, GPS and other metadata) and writes Pictures\CREDITS.txt.
param([string]$ReviewUser = 'fbreview', [int]$Want = 8, [int]$Min = 5)
$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue'
Add-Type -AssemblyName System.Drawing
[Net.ServicePointManager]::SecurityProtocol = 'Tls12'
$sid = (Get-LocalUser $ReviewUser).SID.Value
$userDir = (Get-CimInstance Win32_UserProfile | Where-Object SID -eq $sid).LocalPath
if (-not $userDir -or -not (Test-Path (Join-Path $userDir 'NTUSER.DAT'))) { throw "profile for $ReviewUser not created yet - auto-logon first" }
$out = Join-Path $userDir 'Pictures'
if ((Test-Path $out) -and ((Get-Item $out -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "$out is a reparse point - refusing" }
New-Item -ItemType Directory -Force -Path $out | Out-Null
$ua  = @{ 'User-Agent' = 'FolderbirdDemoSeed/1.0 (https://folderbird.com/Contact)' }
# Tags GDI+ reports on ANY JPEG it writes (quantisation tables, JFIF density). Anything else = metadata.
$structural = 0x5090,0x5091,0x5110,0x5111,0x5112,0x011A,0x011B,0x0128
$jpeg = [Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object MimeType -eq 'image/jpeg'
$ep = New-Object Drawing.Imaging.EncoderParameters 1
$ep.Param[0] = New-Object Drawing.Imaging.EncoderParameter ([Drawing.Imaging.Encoder]::Quality), 88L
$credits = @('Photos on this demo PC. Each is public domain or CC0 on Wikimedia Commons; metadata removed.', '')
$cats = 'Featured_pictures_of_astronomy','Featured_pictures_of_landscapes','Featured_pictures_of_plants','Featured_pictures_of_animals','Featured_pictures_of_architecture'
$n = 0
foreach ($c in $cats) {
  $cont = $null
  for ($page = 0; $page -lt 5 -and $n -lt $Want; $page++) {
    $api = "https://commons.wikimedia.org/w/api.php?action=query&format=json&generator=categorymembers&gcmtitle=Category:$c&gcmtype=file&gcmlimit=50&prop=imageinfo&iiprop=url|mime|extmetadata&iiurlwidth=1920&iiextmetadatafilter=LicenseShortName"
    if ($cont) { $api += "&gcmcontinue=$([Uri]::EscapeDataString($cont))" }
    try { $r = Invoke-RestMethod -Uri $api -Headers $ua } catch { break }
    if (-not $r.query) { break }
    foreach ($p in $r.query.pages.PSObject.Properties.Value) {
      if ($n -ge $Want) { break }
      if (-not $p.imageinfo -or -not $p.imageinfo[0].thumburl) { continue }
      $ii = $p.imageinfo[0]; $lic = "$($ii.extmetadata.LicenseShortName.value)"
      if ($ii.mime -ne 'image/jpeg' -or $lic -notmatch '^(CC0|Public domain)') { continue }
      $name = ($p.title -replace '^File:','' -replace '\.[^.]+$','' -replace '[^A-Za-z0-9 _-]','' -replace '\s+','-')
      if ($name.Length -gt 50) { $name = $name.Substring(0,50) }
      $tmp = Join-Path $env:TEMP "fbphoto-$n.jpg"; $dest = Join-Path $out "$name.jpg"
      try {
        Invoke-WebRequest -UseBasicParsing -Uri $ii.thumburl -Headers $ua -OutFile $tmp
        $img = [Drawing.Image]::FromFile($tmp)
        try { $bmp = New-Object Drawing.Bitmap $img; try { $bmp.Save($dest, $jpeg, $ep) } finally { $bmp.Dispose() } } finally { $img.Dispose() }
        $chk = [Drawing.Image]::FromFile($dest)
        try { $meta = @($chk.PropertyIdList | Where-Object { $structural -notcontains $_ }) } finally { $chk.Dispose() }
        if ($meta.Count -gt 0) { throw "metadata left: $($meta -join ',')" }
        $credits += "$name.jpg - $lic - $($ii.descriptionurl)"; $n++
      } catch { Remove-Item $dest -Force -ErrorAction SilentlyContinue }
      finally { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
    }
    $cont = $r.continue.gcmcontinue; if (-not $cont) { break }
  }
}
Set-Content -Path (Join-Path $out 'CREDITS.txt') -Value $credits -Encoding UTF8
icacls $out /setowner $ReviewUser /T /C /Q | Out-Null
if ($n -lt $Min) { throw "only $n photos passed the license and metadata checks" }
"SEED-PHOTOS:OK $n photos"
