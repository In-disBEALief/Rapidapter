# Build-Rapidapter.ps1
# Compiles Rapidapter.ps1 into a standalone .exe using PS2EXE.
# Run this on your development machine; the output goes into dist\.
#
# Prerequisites:
#   Install-Module ps2exe -Scope CurrentUser

param(
    [string]$Version   = "1.0.0",
    [string]$OutputDir = "dist"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not (Get-Module -ListAvailable -Name ps2exe)) {
    throw "PS2EXE not found. Run: Install-Module ps2exe -Scope CurrentUser"
}

$root    = Split-Path -Parent $MyInvocation.MyCommand.Path
$distDir = Join-Path $root $OutputDir

# Clean and recreate dist\
if (Test-Path $distDir) { Remove-Item -Recurse -Force $distDir }
New-Item -ItemType Directory -Force -Path $distDir | Out-Null

# Compile
Invoke-PS2EXE `
    -InputFile    (Join-Path $root "Rapidapter.ps1") `
    -OutputFile   (Join-Path $distDir "Rapidapter.exe") `
    -IconFile     (Join-Path $root "rapidapter.ico") `
    -NoConsole `
    -RequireAdmin `
    -Title        "Rapidapter" `
    -Description  "Rapidly adapt your network adapter IPv4 settings" `
    -Company      "beal.digital" `
    -Version      $Version

# Copy only the assets the exe needs at runtime
$assetsSrc = Join-Path $root "assets"
$assetsDst = Join-Path $distDir "assets"
New-Item -ItemType Directory -Force -Path $assetsDst | Out-Null
Copy-Item -Force (Join-Path $assetsSrc "rapidapter_96.png") $assetsDst

# Copy icon (used by installer for the shortcut)
Copy-Item -Force (Join-Path $root "rapidapter.ico") $distDir

# Copy default presets (installer preserves any existing user presets)
Copy-Item -Force (Join-Path $root "presets.json") $distDir

Write-Host ""
Write-Host "Build complete -> $distDir"
Write-Host "  Rapidapter.exe"
Write-Host "  rapidapter.ico"
Write-Host "  assets\rapidapter_96.png"
Write-Host "  presets.json"

# Compile Inno Setup installer if ISCC is available
$iscc = "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
if (Test-Path $iscc) {
    Write-Host ""
    Write-Host "Inno Setup found - compiling installer..."
    & $iscc /DMyAppVersion=$Version (Join-Path $root "installer\Rapidapter.iss")
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Installer -> installer\Output\Rapidapter-Setup-$Version.exe"
    } else {
        Write-Warning "Inno Setup exited with code $LASTEXITCODE"
    }
} else {
    Write-Host ""
    Write-Host "Inno Setup not found - skipping installer compilation."
    Write-Host "  To build the installer: choco install innosetup"
    Write-Host "  Then re-run this script."
    Write-Host ""
    Write-Host "To install without the Inno Setup installer:"
    Write-Host "  Run Install-Rapidapter.ps1 from the dist\ folder."
}
