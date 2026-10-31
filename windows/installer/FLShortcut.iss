; Installeur Windows de FL Shortcuts (Inno Setup 6) : un seul fichier pour tout le monde.
; - Sans droits administrateur : installé pour l'utilisateur courant (%LOCALAPPDATA%\Programs\FL Shortcuts),
;   aucune fenêtre UAC, cohérent avec l'appli qui ne s'élève jamais (asInvoker, WIN-05).
; - x64 et ARM64 dans le même installeur : la bonne version est copiée selon le PC.
; - Raccourci dans le menu Démarrer, lancement au démarrage de Windows (case cochée par défaut, décochable),
;   désinstallation depuis Paramètres › Applications. Le profil et les réglages de l'utilisateur sont conservés.
;
; Compilation (Windows) : iscc /DAppVersion=0.3.0 /DDistDir=..\..\dist windows\installer\FLShortcut.iss
; Le workflow GitHub (.github/workflows/build.yml) le fait à chaque compilation.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef DistDir
  #define DistDir "..\..\dist"
#endif

[Setup]
AppId={{6B0C1E3A-7F2D-4C1B-9E55-2F3A8D1C4B70}
AppName=FL Shortcuts
AppVersion={#AppVersion}
AppVerName=FL Shortcuts {#AppVersion}
AppPublisher=FL Shortcuts
AppComments=Raccourcis personnalisés pour FL Studio. Outil indépendant, non affilié à Image-Line.
DefaultDirName={autopf}\FL Shortcuts
DefaultGroupName=FL Shortcuts
DisableDirPage=yes
DisableProgramGroupPage=yes
DisableReadyPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible or arm64
ArchitecturesInstallIn64BitMode=x64compatible or arm64
MinVersion=10.0.17763
OutputDir={#DistDir}
OutputBaseFilename=FLShortcuts-Windows-Setup
SetupIconFile=..\FLShortcut.App\Assets\FLShortcut.ico
UninstallDisplayIcon={app}\FLShortcut.exe
UninstallDisplayName=FL Shortcuts
WizardStyle=modern
Compression=lzma2/max
SolidCompression=yes
; L'appli tourne dans la zone de notification : elle est fermée automatiquement avant une mise à jour.
CloseApplications=force
RestartApplications=no

[Languages]
Name: "fr"; MessagesFile: "compiler:Languages\French.isl"
Name: "en"; MessagesFile: "compiler:Default.isl"

[CustomMessages]
fr.StartupTask=Lancer FL Shortcuts au démarrage de Windows (recommandé : il attend discrètement FL Studio)
en.StartupTask=Start FL Shortcuts with Windows (recommended: it quietly waits for FL Studio)
fr.DesktopTask=Créer une icône sur le Bureau
en.DesktopTask=Create a desktop icon
fr.LaunchNow=Lancer FL Shortcuts maintenant
en.LaunchNow=Launch FL Shortcuts now

[Tasks]
Name: "startup"; Description: "{cm:StartupTask}"
Name: "desktop"; Description: "{cm:DesktopTask}"; Flags: unchecked

[Files]
Source: "{#DistDir}\win-x64\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs; Check: not IsArm64
Source: "{#DistDir}\win-arm64\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs; Check: IsArm64

[InstallDelete]
; Une mise à jour remplace l'appli entière (fichiers d'une ancienne version du runtime retirés).
Type: filesandordirs; Name: "{app}\*"
; Raccourcis à l'ancien nom de l'appli (« FL Shortcut », avant « FL Shortcuts »).
Type: files; Name: "{autoprograms}\FL Shortcut.lnk"
Type: files; Name: "{autodesktop}\FL Shortcut.lnk"

[Icons]
Name: "{autoprograms}\FL Shortcuts"; Filename: "{app}\FLShortcut.exe"
Name: "{autodesktop}\FL Shortcuts"; Filename: "{app}\FLShortcut.exe"; Tasks: desktop

[Registry]
; Lancement au démarrage enregistré sous l'ancien nom : retiré (sinon l'appli démarrerait deux fois).
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: none; ValueName: "FL Shortcut"; Flags: deletevalue
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "FL Shortcuts"; ValueData: """{app}\FLShortcut.exe"""; Flags: uninsdeletevalue; Tasks: startup

[Run]
Filename: "{app}\FLShortcut.exe"; Description: "{cm:LaunchNow}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
; Fermer l'appli (zone de notification) avant de retirer ses fichiers.
Filename: "{sys}\taskkill.exe"; Parameters: "/f /im FLShortcut.exe"; Flags: runhidden; RunOnceId: "StopFLShortcut"
