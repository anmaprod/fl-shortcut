; Installeur Windows de FL Shortcuts (Inno Setup 6) : un seul fichier pour tout le monde.
; - Sans droits administrateur : installé pour l'utilisateur courant (%LOCALAPPDATA%\Programs\FL Shortcuts),
;   aucune fenêtre UAC, cohérent avec l'appli qui ne s'élève jamais (asInvoker, WIN-05).
; - x64 et ARM64 dans le même installeur : la bonne version est copiée selon le PC.
; - Raccourci dans le menu Démarrer, lancement au démarrage de Windows (case cochée par défaut, décochable),
;   désinstallation depuis le menu de l'icône ou Paramètres › Applications : plus aucune trace, comme le Mac
;   (raccourcis, macros, réglages, session du compte, journal, script dans FL : « --uninstall-cleanup » de l'app,
;   UninstallTraces). Une mise à jour garde tout.
;
; - loopMIDI (16/11, « le loopmidi installation de lien a été oublié pour win », choix « Installer avec l'appli ») :
;   case cochée si son pilote manque (x64), loopMIDI téléchargé sur le site de son auteur (jamais copié ici), reconnu à
;   son empreinte, puis son installeur lancé (barre de progression seule ; Windows demande l'autorisation). Pas de
;   réseau, refus ou fichier changé : FL Shortcuts s'installe quand même et son accueil propose « Installer loopMIDI ».
;   Mêmes valeurs que windows/FLShortcut.Core/LoopMidiDownload.cs (essai LoopMidiDownloadTests).
;
; Compilation (Windows) : iscc /DAppVersion=0.3.0 /DDistDir=..\..\dist windows\installer\FLShortcut.iss
; Le workflow GitHub (.github/workflows/build.yml) le fait à chaque compilation.

#if VER < EncodeVer(6,1,0)
  #error Inno Setup 6.1 ou plus est nécessaire (téléchargement de loopMIDI)
#endif

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
AppCopyright=© 2026 FL Shortcuts
; Infos de l'installeur complètes (08/11, antivirus) : éditeur, produit, description et version visibles.
VersionInfoVersion={#AppVersion}
VersionInfoCompany=FL Shortcuts
VersionInfoProductName=FL Shortcuts
VersionInfoProductVersion={#AppVersion}
VersionInfoDescription=Installation de FL Shortcuts
VersionInfoCopyright=© 2026 FL Shortcuts
#ifdef UseSign
; Signé quand la CI a un certificat de signature (secrets WIN_CERT_PFX_BASE64 et WIN_CERT_PASSWORD) : l'installeur et
; le désinstalleur portent la signature, ce que les antivirus et SmartScreen regardent d'abord.
SignTool=fls
SignedUninstaller=yes
#endif
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
fr.LoopMidiTask=Installer loopMIDI, gratuit, pour le lien avec FL Studio
en.LoopMidiTask=Install loopMIDI, free, for the link with FL Studio
fr.LoopMidiDownload=Téléchargement de loopMIDI
en.LoopMidiDownload=Downloading loopMIDI
fr.LoopMidiFrom=Depuis le site de son auteur, Tobias Erichsen.
en.LoopMidiFrom=From its author's website, Tobias Erichsen.
fr.LoopMidiInstalling=Installation de loopMIDI : clique Oui si Windows le demande.
en.LoopMidiInstalling=Installing loopMIDI: click Yes if Windows asks.

[Tasks]
Name: "startup"; Description: "{cm:StartupTask}"
Name: "desktop"; Description: "{cm:DesktopTask}"; Flags: unchecked
Name: "loopmidi"; Description: "{cm:LoopMidiTask}"; Check: LoopMidiMissing

[Files]
Source: "{#DistDir}\win-x64\*"; Excludes: "Windows.Devices.Midi2.dll,Windows.Devices.Midi2.pri"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs; Check: not IsArm64
Source: "{#DistDir}\win-arm64\*"; Excludes: "Windows.Devices.Midi2.dll,Windows.Devices.Midi2.pri"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs; Check: IsArm64
; Copie de l'API de Windows MIDI Services (21/11) : seulement sur Windows 11 25H2 et plus récent (MidiServicesWindows).
Source: "{#DistDir}\win-x64\Windows.Devices.Midi2.dll"; DestDir: "{app}"; Flags: ignoreversion; Check: (not IsArm64) and MidiServicesWindows
Source: "{#DistDir}\win-x64\Windows.Devices.Midi2.pri"; DestDir: "{app}"; Flags: ignoreversion; Check: (not IsArm64) and MidiServicesWindows
Source: "{#DistDir}\win-arm64\Windows.Devices.Midi2.dll"; DestDir: "{app}"; Flags: ignoreversion; Check: IsArm64 and MidiServicesWindows
Source: "{#DistDir}\win-arm64\Windows.Devices.Midi2.pri"; DestDir: "{app}"; Flags: ignoreversion; Check: IsArm64 and MidiServicesWindows

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
; Au démarrage de Windows : l'icône seule, sans fenêtre ni bulle (« --tray »), comme le Mac.
; Lancement au démarrage enregistré sous l'ancien nom : retiré (sinon l'appli démarrerait deux fois).
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: none; ValueName: "FL Shortcut"; Flags: deletevalue
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "FL Shortcuts"; ValueData: """{app}\FLShortcut.exe"" --tray"; Flags: uninsdeletevalue; Tasks: startup

[Run]
Filename: "{app}\FLShortcut.exe"; Description: "{cm:LaunchNow}"; Flags: nowait postinstall skipifsilent
; Mise à jour toute seule (AutoUpdateWin, /UPDATE=1) : l'appli revient dans la zone de notification, sans fenêtre.
Filename: "{app}\FLShortcut.exe"; Parameters: "--tray"; Flags: nowait runasoriginaluser; Check: IsUpdate

[UninstallRun]
; Fermer l'appli (zone de notification) avant de retirer ses fichiers, puis ses traces hors de son dossier
; (dans cet ordre : l'appli fermée ne réécrit plus ses réglages).
Filename: "{sys}\taskkill.exe"; Parameters: "/f /im FLShortcut.exe"; Flags: runhidden waituntilterminated; RunOnceId: "StopFLShortcut"
Filename: "{app}\FLShortcut.exe"; Parameters: "--uninstall-cleanup"; Flags: runhidden waituntilterminated; RunOnceId: "CleanFLShortcut"

[Code]
const
  // Mêmes valeurs que windows/FLShortcut.Core/LoopMidiDownload.cs.
  LoopMidiUrl = 'https://www.tobias-erichsen.de/wp-content/uploads/2020/01/loopMIDISetup_1_0_16_27.zip';
  LoopMidiSha256 = '975399eb76e2c5a1d553ecd8975ab361261ccab8fd9412b8060b19877cb4e0d5';
  LoopMidiSetupName = 'loopMIDISetup.exe';
  LoopMidiSetupArguments = '/passive /norestart';
  LoopMidiArchive = 'loopMIDISetup.zip';

var
  LoopMidiPage: TDownloadWizardPage;
  LoopMidiDownloaded: Boolean;

// Windows MIDI Services (21/11, « on va utiliser celui de win déjà pour essayer ») : Windows 11 25H2 ou plus récent a
// le service MIDI et ses ports « boucle » ; l'appli y crée elle-même son port, avec sa copie de l'API (posée seulement
// là, comme le demande l'accord de Microsoft pour sa préversion). Même limite que MidiServicesSupport.MinBuild (essai
// MidiServicesSupportTests).
function MidiServicesWindows: Boolean;
var
  Version: TWindowsVersion;
begin
  GetWindowsVersionEx(Version);
  Result := Version.Build >= 26200;
end;

// Le pilote de loopMIDI manque (il n'existe qu'en x64 : l'appli ARM64 ne s'en sert pas). Lu dans le vrai System32.
// Sur Windows 11 25H2 et plus récent, loopMIDI n'est plus proposé : Windows fait le port (l'accueil de l'appli
// propose encore « Installer loopMIDI » si ça ne marche pas).
function LoopMidiMissing: Boolean;
var
  Previous: Boolean;
begin
  Result := False;
  if IsArm64 or MidiServicesWindows then
    Exit;
  Previous := EnableFsRedirection(False);
  try
    Result := not FileExists(ExpandConstant('{sys}\teVirtualMIDI64.dll'));
  finally
    EnableFsRedirection(Previous);
  end;
end;

function OnLoopMidiProgress(const Url, FileName: String; const Progress, ProgressMax: Int64): Boolean;
begin
  Result := True;
end;

procedure InitializeWizard;
begin
  LoopMidiPage := CreateDownloadPage(CustomMessage('LoopMidiDownload'), CustomMessage('LoopMidiFrom'), @OnLoopMidiProgress);
end;

// « Installer » (la page des cases est la dernière) : loopMIDI téléchargé avant les fichiers, vérifié à son empreinte.
function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if (CurPageID <> wpSelectTasks) or WizardSilent then
    Exit;
  if not WizardIsTaskSelected('loopmidi') then
    Exit;
  LoopMidiPage.Clear;
  LoopMidiPage.Add(LoopMidiUrl, LoopMidiArchive, LoopMidiSha256);
  LoopMidiPage.Show;
  try
    try
      LoopMidiPage.Download;
      LoopMidiDownloaded := True;
    except
      // Pas de réseau, site changé, autre fichier ou « Abandonner » : FL Shortcuts s'installe quand même.
      Log('loopMIDI non téléchargé : ' + GetExceptionMessage);
    end;
  finally
    LoopMidiPage.Hide;
  end;
end;

function PowerShellQuoted(Text: String): String;
begin
  Result := Text;
  StringChangeEx(Result, '''', '''''', True);
end;

// L'archive ouverte par le tar de Windows (10 1803 et plus), PowerShell en secours.
function LoopMidiUnzipped(const Archive, Folder: String): Boolean;
var
  Code: Integer;
  Previous: Boolean;
begin
  Previous := EnableFsRedirection(False);
  try
    Result := Exec(ExpandConstant('{sys}\tar.exe'), '-xf "' + Archive + '" -C "' + Folder + '"', '', SW_HIDE,
      ewWaitUntilTerminated, Code);
    if Result then
      Result := Code = 0;
    if not Result then
    begin
      Result := Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
        '-NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "Expand-Archive -LiteralPath ''' +
        PowerShellQuoted(Archive) + ''' -DestinationPath ''' + PowerShellQuoted(Folder) + ''' -Force"', '', SW_HIDE,
        ewWaitUntilTerminated, Code);
      if Result then
        Result := Code = 0;
    end;
  finally
    EnableFsRedirection(Previous);
  end;
end;

procedure InstallLoopMidi;
var
  Archive, Folder, Setup: String;
  Code: Integer;
begin
  Archive := ExpandConstant('{tmp}\' + LoopMidiArchive);
  Folder := ExpandConstant('{tmp}\loopMIDI');
  Setup := Folder + '\' + LoopMidiSetupName;
  WizardForm.StatusLabel.Caption := CustomMessage('LoopMidiInstalling');
  WizardForm.FilenameLabel.Caption := '';
  if not ForceDirectories(Folder) then
  begin
    Log('loopMIDI : dossier temporaire non créé');
    Exit;
  end;
  if not LoopMidiUnzipped(Archive, Folder) then
  begin
    Log('loopMIDI : archive non ouverte');
    Exit;
  end;
  if not FileExists(Setup) then
  begin
    Log('loopMIDI : installeur absent de l''archive');
    Exit;
  end;
  // Installeur de loopMIDI (WiX) : il demande lui-même l'autorisation de Windows pour son pilote. Refusé ou annulé :
  // l'accueil de l'appli propose « Installer loopMIDI ».
  if Exec(Setup, LoopMidiSetupArguments, Folder, SW_SHOW, ewWaitUntilTerminated, Code) then
    Log(Format('loopMIDI : installeur terminé, code %d', [Code]))
  else
    Log('loopMIDI : installeur non lancé : ' + SysErrorMessage(Code));
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if (CurStep = ssPostInstall) and LoopMidiDownloaded then
    InstallLoopMidi;
end;

// Lancé par l'appli pour une mise à jour toute seule (AutoUpdateWin : /VERYSILENT … /UPDATE=1) : l'appli revient seule.
function IsUpdate: Boolean;
begin
  Result := ExpandConstant('{param:UPDATE|0}') = '1';
end;
