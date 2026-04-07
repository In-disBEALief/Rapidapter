; Rapidapter.iss
; Inno Setup script for Rapidapter.
;
; Build manually:
;   ISCC.exe /DMyAppVersion=1.0.0 installer\Rapidapter.iss
;
; Or just run Build-Rapidapter.ps1 which calls this automatically.

#ifndef MyAppVersion
  #define MyAppVersion "0.0.0-dev"
#endif

#define MyAppName    "Rapidapter"
#define MyAppPublisher "beal.digital"
#define MyAppURL     "https://beal.digital"
#define MyAppExeName "Rapidapter.exe"

; Source files are expected in dist\ (output of Build-Rapidapter.ps1)
#define SourceDir "..\dist"

[Setup]
AppId={{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={commonappdata}\{#MyAppName}
DisableDirPage=yes
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=Output
OutputBaseFilename=Rapidapter-Setup-{#MyAppVersion}
SetupIconFile={#SourceDir}\rapidapter.ico
Compression=lzma
SolidCompression=yes
WizardStyle=modern
; Require admin so the installer can write to ProgramData and create shortcuts
PrivilegesRequired=admin
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
; Main executable
Source: "{#SourceDir}\{#MyAppExeName}";  DestDir: "{app}"; Flags: ignoreversion

; Icon (used by shortcuts)
Source: "{#SourceDir}\rapidapter.ico";   DestDir: "{app}"; Flags: ignoreversion

; Runtime assets
Source: "{#SourceDir}\assets\*";         DestDir: "{app}\assets"; Flags: ignoreversion recursesubdirs

; Default presets -- only installed if presets.json doesn't already exist
; (preserves user presets across upgrades)
Source: "{#SourceDir}\presets.json";     DestDir: "{app}"; Flags: ignoreversion onlyifdoesntexist

[Icons]
; Start Menu shortcut - exe handles its own elevation via manifest
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\rapidapter.ico"

; Desktop shortcut (optional - user can choose during install)
Name: "{userdesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\rapidapter.ico"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional icons:"

[UninstallDelete]
; Remove presets on uninstall (Inno Setup leaves files it didn't install
; but presets.json may have been created by the app itself)
Type: files; Name: "{app}\presets.json"