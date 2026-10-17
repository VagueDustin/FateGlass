#Requires -Version 7
<#
.SYNOPSIS
    Builds the extra FateGlass theme packs from the FateGlass pack, recoloured with the palettes
    of Fate Takes You Home. Writes __assets\__app\_themes\<Folder>\ (icons, logo, igtheme.json,
    preview.webp). Needs ImageMagick 7 (magick) for the previews.
#>
$ErrorActionPreference = 'Stop'
$src = Resolve-Path "$PSScriptRoot\..\..\.."
$themesDir = "$src\__assets\__app\_themes"
$base = "$themesDir\FateGlass"

# palettes from Fate Takes You Home themes/*.json: base, raised, overlay, border, text, accent,
# and the icon stroke (accentHover on dark themes, accentDefault on light ones for contrast)
$themes = @(
    @{ Folder = 'Dracula';   Name = 'Dracula';    Dark = $true;  Base = '#21222C'; Raised = '#282A36'; Overlay = '#2F313F'; Border = '#3E4152'; Text = '#F8F8F2'; Accent = '#BD93F9'; Icon = '#D3B3FF'
       Desc = 'The community classic: soft violet on deep grey, with the palette everybody already knows.' }
    @{ Folder = 'Nord';      Name = 'Nord';       Dark = $true;  Base = '#272C36'; Raised = '#2E3440'; Overlay = '#353B49'; Border = '#434C5E'; Text = '#ECEFF4'; Accent = '#88C0D0'; Icon = '#A3D3E0'
       Desc = 'Arctic blues. Cold water, long light, nothing raising its voice.' }
    @{ Folder = 'Gruvbox';   Name = 'Gruvbox';    Dark = $true;  Base = '#221F1D'; Raised = '#282828'; Overlay = '#32302F'; Border = '#504945'; Text = '#EBDBB2'; Accent = '#FABD2F'; Icon = '#FFD75F'
       Desc = 'Retro warmth: toasted paper, amber light, a terminal that smells faintly of coffee.' }
    @{ Folder = 'One-Dark';  Name = 'One Dark';   Dark = $true;  Base = '#21252B'; Raised = '#282C34'; Overlay = '#2F333D'; Border = '#3E4451'; Text = '#D7DDE8'; Accent = '#61AFEF'; Icon = '#83C2F5'
       Desc = "Atom's classic editor dark, carried over to your photos." }
    @{ Folder = 'Rose-Pine'; Name = "Ros`u{e9} Pine"; Dark = $true; Base = '#16141F'; Raised = '#191724'; Overlay = '#1F1D2E'; Border = '#332F4D'; Text = '#E0DEF4'; Accent = '#EBBCBA'; Icon = '#F5CDCB'
       Desc = 'Soho vibes: dusk violet, rose gold, and a lamp left on for you.' }
    @{ Folder = 'Cyberpunk'; Name = 'Cyberpunk';  Dark = $true;  Base = '#0B0217'; Raised = '#150829'; Overlay = '#1D0C36'; Border = '#3A1F63'; Text = '#F2E9FF'; Accent = '#FF2ED2'; Icon = '#FF63DF'
       Desc = 'Violet dark and hot neon. The city outside the window never sleeps either.' }
    @{ Folder = 'Crimson';   Name = 'Crimson';    Dark = $true;  Base = '#151013'; Raised = '#1E171B'; Overlay = '#251C21'; Border = '#3A2E33'; Text = '#F2ECEE'; Accent = '#E5484D'; Icon = '#F26568'
       Desc = 'The classic red. Dark warm greys with a scarlet accent that means business.' }
    @{ Folder = 'Terminal';  Name = 'Terminal';   Dark = $true;  Base = '#020503'; Raised = '#04120A'; Overlay = '#06180D'; Border = '#12341F'; Text = '#C9F5D4'; Accent = '#33FF66'; Icon = '#66FF8C'
       Desc = 'Green phosphor on black glass.' }
    @{ Folder = 'Midnight';  Name = 'Midnight';   Dark = $true;  Base = '#1F1F1F'; Raised = '#272727'; Overlay = '#2D2D2D'; Border = '#3D3D3D'; Text = '#FFFFFF'; Accent = '#4CC2FF'; Icon = '#77CFFF'
       Desc = 'A neutral dark theme that follows Windows conventions rather than the house style.' }
    @{ Folder = 'Mono';      Name = 'Mono';       Dark = $true;  Base = '#0C0C0C'; Raised = '#141414'; Overlay = '#1C1C1C'; Border = '#2E2E2E'; Text = '#E8E8E8'; Accent = '#D8D8D8'; Icon = '#D8D8D8'
       Desc = 'Monochrome and quiet, for when only the photo should have colour.' }
    @{ Folder = 'Daybreak';  Name = 'Daybreak';   Dark = $false; Base = '#F6F4EE'; Raised = '#FFFFFF'; Overlay = '#FBFAF6'; Border = '#D8D2C4'; Text = '#141B2E'; Accent = '#8C6A26'; Icon = '#8C6A26'
       Desc = 'A light theme for bright rooms. Warm parchment surfaces with the house gold darkened enough to stay legible on them.' }
    @{ Folder = 'Light';     Name = 'Light';      Dark = $false; Base = '#F7F7F5'; Raised = '#FFFFFF'; Overlay = '#FCFCFA'; Border = '#DCDCD6'; Text = '#1A1E2E'; Accent = '#8A6D1F'; Icon = '#8A6D1F'
       Desc = 'Paper white. Clean, cool and quiet, for rooms with daylight.' }
)

# the FateGlass pack's own colours, which every SVG is written in
$gold = '#F2C94C'; $tile = '#0A0E27'; $edge = '#22325C'
$utf8 = [Text.UTF8Encoding]::new($false)
$baseJson = Get-Content "$base\igtheme.json" -Raw | ConvertFrom-Json -AsHashtable
$tmp = Join-Path ([IO.Path]::GetTempPath()) 'fateglass-themes'
New-Item -ItemType Directory $tmp -Force | Out-Null

foreach ($t in $themes) {
    $dir = Join-Path $themesDir $t.Folder
    if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
    New-Item -ItemType Directory $dir | Out-Null

    # 1. icons and logo, recoloured
    foreach ($svg in Get-ChildItem $base -Filter '*.svg') {
        $text = [IO.File]::ReadAllText($svg.FullName).Replace($gold, $t.Icon).Replace($tile, $t.Raised).Replace($edge, $t.Border)
        [IO.File]::WriteAllText((Join-Path $dir $svg.Name), $text, $utf8)
    }

    # 2. igtheme.json: same icon map, this theme's info and colours
    $json = $baseJson.Clone()
    $json.Info = [ordered]@{
        Name = $t.Name; Author = 'VagueDustin Enterprises'; Email = $baseJson.Info.Email
        Website = $baseJson.Info.Website; Description = $t.Desc; Version = 10
    }
    $json.Settings = [ordered]@{ IsDarkMode = $t.Dark; PreviewImage = 'preview.webp'; AppLogo = 'logo.svg' }
    $json.Colors = [ordered]@{
        AccentColor = $t.Accent; TextColor = $t.Text; BgColor = "$($t.Base)ee"
        ToolbarBgColor = "$($t.Raised)cc"; GalleryBgColor = "$($t.Raised)cc"; MenuBgColor = $t.Overlay
    }
    [IO.File]::WriteAllText("$dir\igtheme.json", ($json | ConvertTo-Json -Depth 5), $utf8)

    # 3. preview: a toolbar row of the theme's icons over its surface, with the logo in the viewer
    $row = 'ViewPreviousImage', 'ViewNextImage', 'RotateLeft', 'RotateRight', 'FlipHorz', 'Crop',
        'Gallery', 'Checkerboard', 'FullScreen', 'Delete', 'MainMenu'
    $icons = $row | ForEach-Object { "$tmp\$($t.Folder)-$_.png" }
    for ($i = 0; $i -lt $row.Count; $i++) {
        & magick -background none -density 192 "$dir\$($row[$i]).svg" $icons[$i]
    }
    & magick -background none @icons -bordercolor none -border 9 +append "$tmp\$($t.Folder)-row.png"
    & magick -background none -density 960 "$dir\logo.svg" -resize 150x150 "$tmp\$($t.Folder)-logo.png"
    & magick -size 660x442 "xc:$($t.Base)" `
        -fill $t.Raised -draw 'rectangle 0,0 660,58' -draw 'rectangle 0,370 660,442' `
        -fill $t.Accent -draw 'roundrectangle 268,380 334,432 6,6' `
        -fill $t.Border -draw 'roundrectangle 344,380 410,432 6,6' -draw 'roundrectangle 196,380 258,432 6,6' `
        "$tmp\$($t.Folder)-row.png" -gravity North -geometry +0+0 -composite `
        "$tmp\$($t.Folder)-logo.png" -gravity Center -geometry +0-6 -composite `
        -quality 90 "$dir\preview.webp"
    if ($LASTEXITCODE -ne 0) { throw "preview failed for $($t.Folder)" }
    Write-Host "  $($t.Folder)"
}
Write-Host "==> built $($themes.Count) themes"
