#define MyAppName "Veylor"
#define MyAppVersion "0.4.2"
#define MyAppExeName "veylor.exe"

[Setup]
AppId=Veylor.Desktop
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher=Veylor
DefaultDirName={localappdata}\Programs\Veylor
DefaultGroupName=Veylor
DisableProgramGroupPage=yes
OutputDir=dist
OutputBaseFilename=Veylor-v0.4.2-Setup-Windows-x64
Compression=lzma2
SolidCompression=yes
PrivilegesRequired=lowest
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\{#MyAppExeName}
SetupIconFile=windows\runner\resources\app_icon.ico
CloseApplications=yes
RestartApplications=no
SetupLogging=yes

[Languages]
Name: "brazilianportuguese"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"

[Tasks]
Name: "desktopicon"; Description: "Criar atalho na Área de Trabalho"; GroupDescription: "Atalhos adicionais:"; Flags: unchecked

[Files]
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Veylor"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\Veylor"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Abrir Veylor"; Flags: nowait postinstall skipifsilent
