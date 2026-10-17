#Requires -Version 7.3
<#
.SYNOPSIS
    Builds the FateGlass x64 installer: __artifacts\bundle\FateGlass_<version>_win-x64.msi

.PARAMETER Aot
    Publish with Native AOT (needs the Visual Studio "Desktop development with C++" workload).
    Without it the build is a regular self-contained .NET app: same features, slower first start.

.PARAMETER NoSettingsSync
    Ship igconfig.default.json as it is, without folding in the live FateGlass settings.

.PARAMETER Version
    App and installer version (e.g. 10.0.7 or 10.0.7.1200). Defaults to IgVersion in
    Directory.Build.props. The release workflow passes the release tag here.
#>
param([switch]$Aot, [switch]$NoSettingsSync, [string]$Version)

$ErrorActionPreference = 'Stop'
$src = Resolve-Path "$PSScriptRoot\..\..\.."
$publishDir = "$src\__artifacts\publish\fateglass-win-x64"
$bundleDir = "$src\__artifacts\bundle"
$version = if ($Version) { $Version } else {
    ([xml](Get-Content "$src\Directory.Build.props")).Project.PropertyGroup.IgVersion | Select-Object -First 1
}
if ($version -notmatch '^\d+\.\d+\.\d+(\.\d+)?$') { throw "Version '$version' must look like 10.0.7 or 10.0.7.1200" }

Write-Host "==> FateGlass $version (AOT: $([bool]$Aot))"

# 1. fold Dustin's current settings into the shipped defaults, so every change carries into installs
$defaultsPath = "$PSScriptRoot\igconfig.default.json"
$livePath = "$env:LOCALAPPDATA\FateGlass\igconfig.json"
if (-not $NoSettingsSync -and (Test-Path $livePath)) {
    # history and bookkeeping, not preferences
    $skip = '_Metadata', 'LastSeenImagePath', 'LastOpenedSetting', 'LastOpenedTool',
        'UpdatePendingVersion', 'UpdateSkippedVersion', 'AutoUpdate', 'LockedFeatures'
    $defaults = Get-Content $defaultsPath -Raw | ConvertFrom-Json -AsHashtable
    $live = Get-Content $livePath -Raw | ConvertFrom-Json -AsHashtable

    $changed = @($live.Keys | Where-Object {
        $_ -notin $skip -and (ConvertTo-Json $live[$_] -Depth 20 -Compress) -ne (ConvertTo-Json $defaults[$_] -Depth 20 -Compress)
    })
    foreach ($key in $changed) { $defaults[$key] = $live[$key] }

    $json = $defaults | ConvertTo-Json -Depth 20
    [IO.File]::WriteAllText($defaultsPath, $json + "`r`n", [Text.UTF8Encoding]::new($false))
    Write-Host "    settings synced from $livePath ($($changed.Count) changed: $($changed -join ', '))"
}

# 2. publish
if (Test-Path $publishDir) { Remove-Item $publishDir -Recurse -Force }
$aotArgs = if ($Aot) { @() } else { @('-p:PublishAot=false', '-p:PublishTrimmed=false') }
& dotnet publish "$src\ImageGlass.Win32" -c Release -r win-x64 -p:Platform=x64 "-p:IgVersion=$version" @aotArgs -o $publishDir
if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed (exit $LASTEXITCODE)" }

# 3. payload: themes, languages, file type icons, transitions, and the default settings
Copy-Item "$src\__assets\__app\*" $publishDir -Recurse -Force
Copy-Item $defaultsPath $publishDir
Get-ChildItem $publishDir -Recurse -Include '*.pdb' | Remove-Item -Force

# 4. installer
New-Item -ItemType Directory $bundleDir -Force | Out-Null
$msi = "$bundleDir\FateGlass_${version}_win-x64.msi"
& wix build "$PSScriptRoot\FateGlass.wxs" -arch x64 -d "PayloadDir=$publishDir" -d "ProductVersion=$version" -o $msi
if ($LASTEXITCODE -ne 0) { throw "wix build failed (exit $LASTEXITCODE)" }

Write-Host "==> $msi"
