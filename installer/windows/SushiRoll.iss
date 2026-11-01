; Inno Setup script for the Windows installer.
; Built by CI (.github/workflows/ci.yml). To build locally after
; `flutter build windows --release`:
;   iscc /DAppVersion=0.1.0 /DSourceDir=..\..\build\windows\x64\runner\Release installer\windows\SushiRoll.iss

#ifndef AppVersion
  #define AppVersion "0.1.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\build\installer"
#endif

#define AppName "Sushi Roll - Universal Airdrop"
#define ShortName "Sushi Roll"
#define AppExe "sushi_roll.exe"
#define FirewallRule "Sushi Roll"

[Setup]
; Never change AppId: it's how upgrades find the existing install.
AppId={{DB4E9F7C-1183-49E5-9863-61788CF718FA}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#ShortName} {#AppVersion}
AppPublisher=drluciano
AppPublisherURL=https://github.com/drluciano/sushi-roll
DefaultDirName={autopf}\{#ShortName}
DefaultGroupName={#ShortName}
DisableProgramGroupPage=yes
UninstallDisplayName={#AppName}
UninstallDisplayIcon={app}\{#AppExe}
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
OutputDir={#OutputDir}
OutputBaseFilename=SushiRoll-Setup-{#AppVersion}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
; Admin so we can add the firewall rule. Users without admin rights can still
; pick "Install for me only" (the app then shows Windows' usual firewall prompt
; the first time it starts listening).
PrivilegesRequired=admin
PrivilegesRequiredOverridesAllowed=dialog
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
Name: "firewall"; Description: "Allow Sushi Roll through Windows Firewall (needed to receive files on Wi-Fi and Tailscale)"; GroupDescription: "Network:"; Check: IsAdminInstallMode

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#ShortName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#ShortName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
; Replace any rule from a previous install, then allow the app on every network
; profile (work and guest Wi-Fi are usually "Public"). The rule is scoped to
; this exe, so it covers the HTTP port (47100+) and multicast discovery (47101)
; without opening those ports to anything else.
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""{#FirewallRule}"""; Flags: runhidden; Tasks: firewall
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall add rule name=""{#FirewallRule}"" dir=in action=allow program=""{app}\{#AppExe}"" enable=yes profile=any"; Flags: runhidden; Tasks: firewall; StatusMsg: "Adding firewall rule..."
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#ShortName}}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""{#FirewallRule}"""; Flags: runhidden; RunOnceId: "RemoveFirewallRule"; Check: IsAdminInstallMode
