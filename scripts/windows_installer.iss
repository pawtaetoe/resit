; Inno Setup script for the reSIT Windows installer.
;
; Build the app first (flutter build windows --release), then:
;   iscc /DAppVersion=1.2.3 scripts\windows_installer.iss
; The installer is written to dist\resit-<version>-windows-setup.exe.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

[Setup]
; Fixed id so later versions upgrade this install instead of adding another.
AppId={{6B0D6E2C-4A6E-4C3B-9D7B-2F1C5E8A9D31}
AppName=reSIT
AppVersion={#AppVersion}
AppPublisher=reSIT
AppComments=Rooms, classes and results at SIT
DefaultDirName={autopf}\reSIT
DefaultGroupName=reSIT
DisableProgramGroupPage=yes
; Installs for the current user without admin rights by default; the user
; can choose an all-users install instead.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\dist
OutputBaseFilename=resit-{#AppVersion}-windows-setup
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\resit.exe
UninstallDisplayName=reSIT
Compression=lzma2
SolidCompression=yes
WizardStyle=modern

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; The whole Flutter release folder (resit.exe, DLLs, data\), plus the
; Visual C++ runtime DLLs the CI copies in beside it.
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\reSIT"; Filename: "{app}\resit.exe"
Name: "{autodesktop}\reSIT"; Filename: "{app}\resit.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\resit.exe"; Description: "{cm:LaunchProgram,reSIT}"; Flags: nowait postinstall skipifsilent
