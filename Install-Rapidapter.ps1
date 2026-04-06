# Install-Rapidapter.ps1
# Installs Rapidapter and creates a Start Menu shortcut that runs hidden as admin.

param(
    [string]$InstallDir  = "$env:ProgramData\Rapidapter",
    [string]$ScriptName  = "Rapidapter.ps1",
    [string]$IconName    = "rapidapter.ico",
    [string]$AssetsDir   = "assets",
    [switch]$DesktopShortcut
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Assert-Admin {
    $isAdmin = ([Security.Principal.WindowsPrincipal] `
        [Security.Principal.WindowsIdentity]::GetCurrent() `
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) { throw "Please run this installer as Administrator." }
}

function Set-ShortcutRunAsAdmin([string]$lnkPath) {
    # Toggle the "Run as administrator" flag in the .lnk file.
    # This is a known, widely-used technique: set bit 0x20 at byte 0x15.
    $bytes = [IO.File]::ReadAllBytes($lnkPath)
    $bytes[0x15] = $bytes[0x15] -bor 0x20
    [IO.File]::WriteAllBytes($lnkPath, $bytes)
}

Assert-Admin

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$srcScript = Join-Path $here $ScriptName
$srcIcon   = Join-Path $here $IconName
$srcAssets = Join-Path $here $AssetsDir

if (-not (Test-Path $srcScript)) { throw "Missing $ScriptName next to installer: $srcScript" }
if (-not (Test-Path $srcIcon))   { throw "Missing $IconName next to installer: $srcIcon" }
if (-not (Test-Path $srcAssets)) { throw "Missing assets folder next to installer: $srcAssets" }

# 1) Copy files to stable location
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
Copy-Item -Force $srcScript (Join-Path $InstallDir $ScriptName)
Copy-Item -Force $srcIcon   (Join-Path $InstallDir $IconName)
Copy-Item -Recurse -Force $srcAssets (Join-Path $InstallDir $AssetsDir)

$installedScript = Join-Path $InstallDir $ScriptName
$installedIcon   = Join-Path $InstallDir $IconName

# 2) Create Start Menu shortcut
$startMenuDir = Join-Path $env:ProgramData "Microsoft\Windows\Start Menu\Programs"
$shortcutPath = Join-Path $startMenuDir "Rapidapter.lnk"

$psExe = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"

$wsh = New-Object -ComObject WScript.Shell
$sc  = $wsh.CreateShortcut($shortcutPath)
$sc.TargetPath = $psExe
$sc.Arguments  = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$installedScript`""
$sc.WorkingDirectory = $InstallDir
$sc.IconLocation = "$installedIcon,0"
$sc.WindowStyle = 7  # minimized (console should be hidden anyway)
$sc.Description = "Rapidapter - quick IPv4 profile switcher"
$sc.Save()

# 3) Mark shortcut "Run as administrator"
Set-ShortcutRunAsAdmin $shortcutPath

# 4) Optional Desktop shortcut
if ($DesktopShortcut) {
    $desktopPath = Join-Path ([Environment]::GetFolderPath("Desktop")) "Rapidapter.lnk"
    Copy-Item -Force $shortcutPath $desktopPath
}

Write-Host "Installed Rapidapter to: $InstallDir"
Write-Host "Start Menu shortcut: $shortcutPath"
if ($DesktopShortcut) { Write-Host "Desktop shortcut created." }
