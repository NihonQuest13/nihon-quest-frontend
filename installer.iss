; ===================================================================
; Script Inno Setup AMÉLIORÉ pour "Nihon Quest"
; ===================================================================
; AJOUTS :
; - Uninstaller propre et complet.
; - Installation dans le dossier Documents de l'utilisateur par défaut.
; - Option pour créer une icône sur le bureau (case à cocher).
; - Option pour lancer l'application à la fin de l'installation.
; - Vérification si l'application est en cours d'exécution avant la désinstallation.
; ===================================================================

#define MyAppName "Nihon Quest"
#define MyAppVersion "4.22"
#define MyAppPublisher "Jykoda"
#define MyAppExeName "NihonQuest.exe"

[Setup]
AppId={{C9A7E1F2-9F0C-4C1E-8D2A-5B6C7D8E9F0A}}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
; CORRECTION : Retour à l'installation dans le dossier Documents de l'utilisateur
DefaultDirName={userdocs}\{#MyAppName}
DisableProgramGroupPage=yes
OutputDir=release
OutputBaseFilename=NihonQuest_Setup_{#MyAppVersion}
SetupIconFile=assets\logo.ico
UninstallDisplayIcon={app}\flutter\nihon_quest.exe
Compression=lzma 
SolidCompression=yes
WizardStyle=modern
; CORRECTION : Les droits administrateur ne sont plus requis pour ce dossier
PrivilegesRequired=lowest

; Section pour les langues (Français par défaut)
[Languages]
Name: "french"; MessagesFile: "compiler:Default.isl"

; Section pour les tâches optionnelles (icône sur le bureau)
[Tasks]
Name: "desktopicon"; Description: "Créer une icône sur le bureau"; GroupDescription: "Raccourcis:"; Flags: checkablealone

[Files]
; 1. Copie le LANCEUR
Source: "release\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion

; 2. Copie l'application FLUTTER et ses assets
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}\flutter"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "assets\videos\*"; DestDir: "{app}\flutter\data\flutter_assets\assets\videos"; Flags: ignoreversion recursesubdirs createallsubdirs


; 3. Copie le contenu du dossier .dist du BACKEND
Source: "release\backend\main.dist\*"; DestDir: "{app}\backend"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
; Icône du menu Démarrer (toujours créée)
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\flutter\nihon_quest.exe"
; Icône du bureau (créée seulement si la tâche "desktopicon" est cochée)
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\flutter\nihon_quest.exe"; Tasks: desktopicon

; Section pour exécuter l'application après l'installation
[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Lancer {#MyAppName}"; Flags: nowait postinstall skipifsilent

; Section pour une désinstallation propre
[UninstallDelete]
Type: filesandordirs; Name: "{app}"
Type: files; Name: "{autoprograms}\{#MyAppName}.lnk"
Type: files; Name: "{autodesktop}\{#MyAppName}.lnk"

; Code Pascal pour vérifier si l'application est en cours d'exécution avant la désinstallation
[Code]
function IsAppRunning(): Boolean;
begin
  // 'FLUTTER_RUNNER_WIN32_WINDOW' est le nom de classe de la fenêtre principale d'une app Flutter
  Result := FindWindowByClassName('FLUTTER_RUNNER_WIN32_WINDOW') <> 0;
end;

function InitializeUninstall(): Boolean;
begin
  if IsAppRunning() then
  begin
    MsgBox('{#MyAppName} est en cours d''exécution.'#13#10'Veuillez fermer l''application avant de continuer la désinstallation.', mbError, MB_OK);
    Result := False;
  end
  else
  begin
    Result := True;
  end;
end;
