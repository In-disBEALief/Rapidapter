# Uninstall-Rapidapter.ps1
# Removes files and shortcuts created by Install-Rapidapter.ps1.
# Not needed if you installed via the Inno Setup installer -- use
# Windows Settings > Apps > Installed Apps instead.

param(
    [string]$InstallDir = "$env:ProgramData\Rapidapter",
    [switch]$KeepPresets
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { throw "Please run this uninstaller as Administrator." }

$startMenuShortcut = Join-Path $env:ProgramData "Microsoft\Windows\Start Menu\Programs\Rapidapter.lnk"
$desktopShortcut   = Join-Path ([Environment]::GetFolderPath("Desktop")) "Rapidapter.lnk"

if (-not (Test-Path $InstallDir) -and -not (Test-Path $startMenuShortcut)) {
    Write-Host "Rapidapter does not appear to be installed at: $InstallDir"
    exit 0
}

# Optionally preserve presets.json
$presetsPath = Join-Path $InstallDir "presets.json"
$savedPresets = $null
if ($KeepPresets -and (Test-Path $presetsPath)) {
    $savedPresets = Get-Content $presetsPath -Raw
    Write-Host "Preserving presets.json..."
}

if (Test-Path $InstallDir)         { Remove-Item -Recurse -Force $InstallDir }
if (Test-Path $startMenuShortcut)  { Remove-Item -Force $startMenuShortcut }
if (Test-Path $desktopShortcut)    { Remove-Item -Force $desktopShortcut }

if ($savedPresets) {
    # Re-create a bare folder just for the presets
    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
    $savedPresets | Set-Content (Join-Path $InstallDir "presets.json") -Encoding UTF8
    Write-Host "Presets saved to: $presetsPath"
}

Write-Host "Rapidapter uninstalled."