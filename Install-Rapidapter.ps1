# Install-Rapidapter.ps1
# Installs Rapidapter and creates a Start Menu shortcut.
# Run from the dist\ folder (after building) for the .exe version,
# or from the repo root for the .ps1 version.

param(
    [string]$InstallDir     = "$env:ProgramData\Rapidapter",
    [string]$ExeName        = "Rapidapter.exe",
    [string]$ScriptName     = "Rapidapter.ps1",
    [string]$IconName       = "rapidapter.ico",
    [string]$AssetsDir      = "assets",
    [string]$PresetsName    = "presets.json",
    [switch]$DesktopShortcut
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Assert-Admin {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
               ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) { throw "Please run this installer as Administrator." }
}

function Set-ShortcutRunAsAdmin([string]$lnkPath) {
    # Toggle the "Run as administrator" flag in the .lnk binary.
    $bytes = [IO.File]::ReadAllBytes($lnkPath)
    $bytes[0x15] = $bytes[0x15] -bor 0x20
    [IO.File]::WriteAllBytes($lnkPath, $bytes)
}

Assert-Admin

$here      = Split-Path -Parent $MyInvocation.MyCommand.Path
$srcExe    = Join-Path $here $ExeName
$srcScript = Join-Path $here $ScriptName
$srcIcon   = Join-Path $here $IconName
$srcAssets = Join-Path $here $AssetsDir
$srcPresets = Join-Path $here $PresetsName

# Determine whether we are installing the compiled .exe or the .ps1 script.
$useExe = Test-Path $srcExe

if (-not $useExe -and -not (Test-Path $srcScript)) {
    throw "Neither $ExeName nor $ScriptName found next to the installer: $here"
}
if (-not (Test-Path $srcIcon))   { throw "Missing $IconName next to installer: $srcIcon" }
if (-not (Test-Path $srcAssets)) { throw "Missing assets folder next to installer: $srcAssets" }

# 1) Copy files to stable install location
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

if ($useExe) {
    Copy-Item -Force $srcExe (Join-Path $InstallDir $ExeName)
} else {
    Copy-Item -Force $srcScript (Join-Path $InstallDir $ScriptName)
}
Copy-Item -Force $srcIcon (Join-Path $InstallDir $IconName)
Copy-Item -Recurse -Force $srcAssets (Join-Path $InstallDir $AssetsDir)

# Copy default presets only if none exist yet (preserve user's saved presets).
$destPresets = Join-Path $InstallDir $PresetsName
if ((Test-Path $srcPresets) -and -not (Test-Path $destPresets)) {
    Copy-Item -Force $srcPresets $destPresets
}

# 2) Create Start Menu shortcut
$startMenuDir = Join-Path $env:ProgramData "Microsoft\Windows\Start Menu\Programs"
$shortcutPath = Join-Path $startMenuDir "Rapidapter.lnk"
$installedIcon = Join-Path $InstallDir $IconName

$wsh = New-Object -ComObject WScript.Shell
$sc  = $wsh.CreateShortcut($shortcutPath)

if ($useExe) {
    # Point directly at the exe - no powershell.exe wrapper needed.
    $sc.TargetPath       = Join-Path $InstallDir $ExeName
    $sc.Arguments        = ""
    $sc.WindowStyle      = 1  # Normal window
} else {
    # Wrap the .ps1 in powershell.exe with a hidden console window.
    $psExe = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
    $installedScript = Join-Path $InstallDir $ScriptName
    $sc.TargetPath       = $psExe
    $sc.Arguments        = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$installedScript`""
    $sc.WindowStyle      = 7  # Minimized (hides the console)
}

$sc.WorkingDirectory = $InstallDir
$sc.IconLocation     = "$installedIcon,0"
$sc.Description      = "Rapidapter - quick IPv4 profile switcher"
$sc.Save()

# 3) Mark shortcut "Run as administrator"
Set-ShortcutRunAsAdmin $shortcutPath

# 4) Optional Desktop shortcut
if ($DesktopShortcut) {
    $desktopPath = Join-Path ([Environment]::GetFolderPath("Desktop")) "Rapidapter.lnk"
    Copy-Item -Force $shortcutPath $desktopPath
}

$installedTarget = if ($useExe) { $ExeName } else { $ScriptName }
Write-Host "Installed Rapidapter ($installedTarget) to: $InstallDir"
Write-Host "Start Menu shortcut: $shortcutPath"
if ($DesktopShortcut) { Write-Host "Desktop shortcut created." }
