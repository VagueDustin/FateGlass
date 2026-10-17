<#
.SYNOPSIS
    Builds the FateGlass x64 installer: __artifacts\bundle\FateGlass_<version>_win-x64.msi

.PARAMETER Aot
    Publish with Native AOT (needs the Visual Studio "Desktop development with C++" workload).
    Without it the build is a regular self-contained .NET app: same features, slower first start.
#>
param([switch]$Aot)

$ErrorActionPreference = 'Stop'
$src = Resolve-Path "$PSScriptRoot\..\..\.."
$publishDir = "$src\__artifacts\publish\fateglass-win-x64"
$bundleDir = "$src\__artifacts\bundle"
$version = ([xml](Get-Content "$src\Directory.Build.props")).Project.PropertyGroup.IgVersion | Select-Object -First 1

Write-Host "==> FateGlass $version (AOT: $([bool]$Aot))"
if (Test-Path $publishDir) { Remove-Item $publishDir -Recurse -Force }

$aotArgs = if ($Aot) { @() } else { @('-p:PublishAot=false', '-p:PublishTrimmed=false') }
& dotnet publish "$src\ImageGlass.Win32" -c Release -r win-x64 -p:Platform=x64 @aotArgs -o $publishDir
if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed (exit $LASTEXITCODE)" }

# shared payload: themes, languages, file type icons, transitions
Copy-Item "$src\__assets\__app\*" $publishDir -Recurse -Force
Get-ChildItem $publishDir -Recurse -Include '*.pdb' | Remove-Item -Force

New-Item -ItemType Directory $bundleDir -Force | Out-Null
$msi = "$bundleDir\FateGlass_${version}_win-x64.msi"
& wix build "$PSScriptRoot\FateGlass.wxs" -arch x64 -d "PayloadDir=$publishDir" -d "ProductVersion=$version" -o $msi
if ($LASTEXITCODE -ne 0) { throw "wix build failed (exit $LASTEXITCODE)" }

Write-Host "==> $msi"
