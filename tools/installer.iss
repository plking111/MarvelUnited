; 漫威联合 安装脚本 (Inno Setup)
#define MyAppName "漫威联合"
#define MyAppVersion "3.10"
#define MyAppExeName "MarvelUnited.exe"

[Setup]
AppId={{8E5C4A2B-3D1F-4C6A-9B7E-A1B2C3D4E5F6}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher=Marvel United
DefaultDirName={autopf}\MarvelUnited
DisableDirPage=no
DisableProgramGroupPage=yes
OutputDir=F:\桌游相关\漫威联合\电子游戏
OutputBaseFilename=漫威联合安装程序_v3.10
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\{#MyAppExeName}
PrivilegesRequired=admin
SetupIconFile=F:\桌游相关\漫威联合\电子游戏\MarvelUnitedGame\icon.ico

[Languages]
Name: "chinesesimplified"; MessagesFile: "F:\桌游相关\漫威联合\Inno Setup 7\Languages\ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加任务：";

[Files]
Source: "F:\桌游相关\漫威联合\电子游戏\MarvelUnitedGame\build\MarvelUnited.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "F:\桌游相关\漫威联合\电子游戏\MarvelUnitedGame\build\MarvelUnited.pck"; DestDir: "{app}"; Flags: ignoreversion
Source: "F:\桌游相关\漫威联合\电子游戏\MarvelUnitedGame\build\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs
Source: "F:\桌游相关\漫威联合\电子游戏\MarvelUnitedGame\build\使用说明.txt"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "立即运行 {#MyAppName}"; Flags: nowait postinstall skipifsilent
