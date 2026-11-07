# Windows à l'identique du Mac (Communauté, Mon compte, Aide, style suisse) — plan

> Demande du propriétaire (03/11, capture de l'app Windows chez un ami) : « le logiciel n'est pas le même que la
> dernière version du mac » → « OUI » pour tout rattraper. La référence est l'app Mac telle qu'elle est (code et
> photos de la CI `FLShortcuts-mac-mesure`), pas une nouvelle maquette.

**But :** l'app Windows a les mêmes pages, les mêmes textes et le même aspect que l'app Mac.

**Architecture :** comme pour les macros et l'Organiser, la logique va dans le cœur testable
`windows/FLShortcut.Core` (miroir des fichiers Swift, mêmes règles, mêmes essais en xUnit), l'interface dans
`windows/FLShortcut.App` (WinUI 3 en code, pièces communes dans `MacLook.cs`). Le serveur ne change pas (Supabase :
`supabase/*.sql`, déjà utilisé par le Mac).

**Outils :** C# 12 / .NET 8, WinUI 3 (Windows App SDK 1.6), xUnit ; la CI seule compile l'app (`dotnet test` du cœur
tourne sur Linux).

## Règles qui valent pour chaque étape

- Textes : ceux du Mac, mot pour mot, par `Loc.T` (anglais déjà dans `Resources/en.lproj/Localizable.strings` ; un
  texte nouveau → `python3 scripts/localisation.py generer`).
- Jamais de nom de son, de piste, de pseudo, d'e-mail ni de texte tapé dans le journal (`AppLog`) : mots fixes et
  nombres.
- Jamais de clé secrète dans le dépôt : l'adresse du serveur et la clé publique (anon) viennent des secrets de la CI
  (`FLS_SUPABASE_URL`, `FLS_SUPABASE_ANON_KEY`), écrites dans l'app à la compilation (comme `build.sh` les écrit dans
  l'Info.plist du Mac) ; sans elles, les pages disent « pas de serveur » comme le Mac.
- Session du compte : chiffrée pour l'utilisateur Windows (DPAPI, `ProtectedData`, déjà référencé), fichier dans
  `%LOCALAPPDATA%\FL Shortcuts`, jamais en clair.
- HTTPS seulement ; tout ce qui vient du serveur est relu (tailles bornées) avant d'être montré ou importé (un partage
  passe par l'import des macros existant).
- Chaque étape : son commit, la CI verte, ses photos Windows (`--photos`) relues avant de passer à la suivante.
- JAMAIS retirer la barre de titre d'une fenêtre WinUI déjà créée ; JAMAIS `SetDefaultDllDirectories` (CLAUDE.md).

## Étapes

### W-S1 Style suisse : pièces communes et pages existantes
Référence : `Sources/FLShortcut/GlassStyle.swift` (`Swiss`, `swissLabel`, `swissTitle`, `swissRule`, `SwissSwitch`,
`SwissButtonBody`, `SwissSegmented`, `SwissPicker`, `swissField`), `SwissDialog.swift`, CLAUDE.md « Style suisse ».
- `MacLook.cs` : fond noir, texte blanc, traits fins #333/#222, coins carrés partout, titres gras, libellés en petites
  capitales espacées, boutons rectangulaires en capitales (principal blanc plein ; survol : bordé → blanc plein texte
  noir, principal → noir bordé ; danger rouge #FF3B1F), interrupteur suisse, survol = blanc plein texte noir.
- Appliqué à : fenêtre principale (barre de gauche, cartes, recherche), Macros et créateur, Organiser et son tuto,
  menu de l'icône, questions (`ContentDialog` → fenêtre suisse), accueil.
- Photos CI : principale*, macros-*, organiser-*, menu-icone, comparées à celles du Mac.

### W-S2 Aide
Référence : `HelpView.swift`, `Support.swift` (FAQ, `SupportRules`, `SupportDiagnostic`, `ProblemLog`).
- Cœur : FAQ (questions et réponses du Mac, celles propres au Mac adaptées à Windows), recherche sans accents,
  réponses en étapes (`HelpEntry.steps`), règles du message, diagnostic Windows (versions, FL ouvert/reconnu/admin,
  mode léger, nombres de raccourcis et de macros ; rien de personnel), envoi à `support_requests` sans compte.
- Page : grande recherche, questions en carte, « Écrire à l'équipe », « Revoir le guide » ; « Signaler ce problème… »
  du menu de l'icône après une macro ratée (comme le Mac).

### W-S3 Compte : cœur (client du serveur)
Référence : `CommunityClient.swift`, `CommunityStore.swift`, `AccountBackup.swift`, `supabase/inscription.sql`,
`sauvegarde.sql`, `profil.sql`.
- Inscription (pseudo libre vérifié, code du mail), connexion, mot de passe oublié, session rafraîchie et chiffrée,
  déconnexion ; pseudo modifiable, photo (256 px JPEG sans métadonnées, envoi/retrait) ; sauvegarde des raccourcis et
  macros (`save_backup`, choix entre deux versions), suppression du compte. Essais xUnit avec un faux serveur
  (comme `SupportTests` du Mac).

### W-S4 Page Mon compte
Référence : `AccountView.swift`, `AccountAuthViews.swift`, `EditProfileSheet.swift`, `ProfilePhoto.swift`.
- Écrans connexion / inscription / code / oubli, carte du profil (photo, Modifier le profil), sauvegarde, choix des
  versions, Supprimer mon compte ; capsule du compte en haut à droite avec la photo.

### W-S5 Communauté
Référence : `CommunityView.swift`, `CommunityStore.swift`.
- Liste (recherche, Tout / Macros / Raccourcis / Les miens), cartes, fiche, Ajouter (macro → bibliothèque, raccourcis
  → profil, relus avant), Partager, Signaler (partage, photo), page d'un auteur, membres ; barre de gauche :
  « Partager › Communauté », « Compte et aide › Mon compte, Aide ».

### W-S6 Fin
CLAUDE.md et HISTORIQUE à jour, modes d'emploi Windows (`docs/telechargement/`), photos CI de chaque écran,
installeur pour les amis du propriétaire.
