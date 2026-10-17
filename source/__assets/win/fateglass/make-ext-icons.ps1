<#
.SYNOPSIS
    Regenerates every file type icon in __assets\__app\_ext_icons as a FateGlass document icon:
    a navy page with a gold edge, the FateGlass mark, and the extension on a gold band.
    Needs ImageMagick 7 (magick) with librsvg.
#>
$ErrorActionPreference = 'Stop'
$src = Resolve-Path "$PSScriptRoot\..\..\.."
$iconDir = "$src\__assets\__app\_ext_icons"
$markSvg = "$src\ImageGlass.Win32\fateglass-icon.svg"
$tmp = Join-Path ([IO.Path]::GetTempPath()) "fateglass-ext-icons"
New-Item -ItemType Directory $tmp -Force | Out-Null

# brand primitives (gold-navy): navy-900 page, gold-600 edge, gold-500 band, navy-950 label
$page = @'
<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256">
  <defs><clipPath id="p"><rect x="30" y="8" width="196" height="240" rx="24"/></clipPath></defs>
  <rect x="30" y="8" width="196" height="240" rx="24" fill="#0A0E27"/>
  <rect x="30" y="160" width="196" height="88" fill="#D4AF37" clip-path="url(#p)"/>
  <rect x="33" y="11" width="190" height="234" rx="21" fill="none" stroke="#B8902B" stroke-width="6"/>
</svg>
'@
Set-Content "$tmp\page.svg" $page -Encoding utf8
& magick -background none "$tmp\page.svg" "$tmp\page.png"
& magick -background none -density 384 $markSvg -resize 128x128 "$tmp\mark.png"
if ($LASTEXITCODE -ne 0) { throw "could not render $markSvg" }

foreach ($ico in Get-ChildItem $iconDir -Filter '*.ico') {
    $label = $ico.BaseName.ToUpperInvariant()
    # bold caps run about 0.68 em wide, so shrink long extensions to fit the 170px band
    $size = [Math]::Min(68, [Math]::Floor(170 / (0.68 * $label.Length)))

    & magick "$tmp\page.png" "$tmp\mark.png" -gravity North -geometry +0+22 -composite `
        -font Segoe-UI-Bold -pointsize $size -fill '#070B1A' -gravity Center -annotate +0+76 $label `
        -define icon:auto-resize=256,128,96,64,48,32,24,16 $ico.FullName
    if ($LASTEXITCODE -ne 0) { throw "failed on $($ico.Name)" }
}
Write-Host "==> regenerated $((Get-ChildItem $iconDir -Filter '*.ico').Count) icons"
