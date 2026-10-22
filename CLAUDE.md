# FL Shortcuts — à lire avant de travailler

- Réponds en français, en tutoyant le propriétaire (musicien, pas développeur). Textes de l'app, commentaires et
  commits en français. Priorité macOS ; Windows en pause (compilé seulement pour un tag `v*`).
- Branche la plus récente : **`claude/great-hopper-qihaiy`** (en avance de 138 commits sur `claude/relaxed-mayer-ndguzv`).
  Pas de nouvelle PR sans demande (anmaprod/fl-shortcut#1 existe). Un push lance la CI ; ne pas la relancer à la main
  sans demande. Derniers tests Mac verts : commit efa3fee (488 tests, lancés par le propriétaire sur son Mac).
- Tout texte affiché doit avoir son anglais (la CI échoue sinon) : `python3 scripts/localisation.py generer trad.json`.
- Historique, décisions et échecs : `docs/contexte/HISTORIQUE.md` ; lien avec FL (script v15) : `PROTOCOL.md`.

## Règles du propriétaire
- Pas de lecture de l'écran, sauf pour retrouver un bouton à son nom ou son image, dans la seule fenêtre de FL, au
  moment du clic, avec l'autorisation « Enregistrement de l'écran ».
- Jamais de nom de son, de piste ou de texte tapé dans les journaux ni le diagnostic (nombres seulement).
- Essais sur un projet de test seulement. Jamais de clé secrète Supabase ni de clé privée dans le dépôt. Pas
  d'identifiant de modèle dans les commits. Le bouton s'appelle « Organiser » (pas « Tout organiser »).

## Déjà fait (ne pas refaire)
- Raccourcis, créateur de macros, compte et sauvegarde en ligne, Communauté, aide, désinstallation : voir HISTORIQUE.
- Langue du Mac : toute l'app en anglais (`Resources/en.lproj`), français par défaut.
- Trousseau : un seul élément pour la clé du script et la session du compte (une seule demande d'accès).
- Fenêtre principale sans bande sous la barre d'outils ; accueil remontré si l'autorisation clavier manque.
- **Organiser v5** (`Sources/FLShortcut/Organizer*.swift`, `SoundFeatures.swift`, `SoundFamilies.swift`, script FL v15) :
  - analyse sur le fichier du projet (PROTOCOL.md §9, `FLP*.swift`, `OrganizerProject*.swift`) : FL enregistre (⌘S),
    le .flp est lu ; sons de chaque pattern et de chaque piste d'après les notes et les clips (plus rien de deviné :
    ni relevé des patterns, ni chanson jouée, ni piste écoutée) ; chaque son classé par son nom ou écouté seul dans son
    pattern, à son tempo (JAMAIS accéléré : refusé par le propriétaire) ; rien n'est touché si le fichier n'est pas le
    projet ouvert ou a une forme inattendue ; le diagnostic donne les sons de chaque pattern et piste (numéros) ;
  - classement réglé (arpège → mélodie, drum loop → Drums, hi-hat par ses aigus ; 3 notes nettes ou plus → mélodie,
    jamais drums ni FX ; un canal au nom d'un synthé de mélodies, ZENOLOGY, Serum… → jamais drums ni FX) ;
  - « Organiser » : sons sans note supprimés (⌥ + Suppr de FL), Channel rack, Mixer (un bus par famille, son sur le
    Master relié à une piste libre, pistes inutiles remises à neuf), patterns et Playlist dans le même ordre, mêmes noms
    partout, le tout dans une copie « <nom>_2.flp » (voir Playlist) ;
  - IA de macOS sur une fenêtre de 1 s (son court complété) ; « Voix » seulement si l'IA entend une voix ; tempo du
    projet jamais changé ; règle de chaque son dans le diagnostic (`c4:melodie+ia`) ;
  - Playlist rangée dans une copie « <nom>_2.flp » (comme « Save new version » de FL ; puis _3…) à côté de l'original : chaque clip sur la piste de ses
    sons (les mêmes sons, la même piste ; un clip qui en chevaucherait un autre : une piste de plus dessous ; patterns
    vides en bas), pistes dans l'ordre des familles ; FL ouvre la copie (reconnue à un nom de pattern posé pour ça,
    remis aussitôt), le reste s'y fait par le script, FL l'enregistre. L'original ne bouge jamais : « Revenir comme
    avant » le rouvre (tout revient, suppressions comprises). Plus aucune lecture de l'écran pour la Playlist ; l'ancien
    code (réunion des clips lus dans la fenêtre, patterns descendus, « Move up ») ne sert plus que sans fichier (tests).
  - aperçu : couleur ou dégradé de chaque famille en haut, résumé et choix dessous, dans la même zone qui défile.
- Interface : survol coloré du menu de l'icône (`menuHover` : contour de sa couleur, grandit, ombre) voulu par le
  propriétaire partout : barre latérale (`sidebarHover`), lignes des pages, Macros, modèles, Communauté, Aide,
  palette, blocs, bouton d'enregistrement, « Menu de FL » du créateur ;
  « Mes raccourcis » = raccourcis changés + créés, jamais de macro (macro d'exemple ⌃R retirée) ; plus aucune note
  sous les blocs des macros ; « Menu de FL » en tête des blocs FL Studio de la palette ; recherche qui lâche la main
  au premier clic ailleurs ; « Cliquer sur… » › Playlist : tout le menu « Arrangement » (bouton retrouvé à son nom).

- « Quitter et rouvrir » (macOS, après une autorisation) : la copie relancée attend l'ancienne au lieu de partir
  (`SingleInstance`, clé `quittingPID`) ; l'app reprend là où on en était si relancée moins de 2 min après
  (`AppResume.swift` : accueil et son écran, panneau des autorisations, fenêtre principale, page, macro, Organiser).
- Aspect : les versions d'avant sont fabriquées par GitHub avec Xcode 26.6 (kit macOS 26). Le Mac du propriétaire
  a Xcode 27 : avec le kit 27, macOS 27 dessine l'app autrement (boutons en rectangle arrondi…). `build.sh` prend
  alors tout seul le kit 26 des outils en ligne de commande (`--build-system native`, une architecture à la fois : l'outil d'Xcode inscrivait
  « sdk 13.0 ») et vérifie le kit inscrit (`vtool`). Ne pas « corriger » l'aspect en code.

## Pas encore vérifié sur le vrai FL
- Organiser sur le fichier : ⌘S enregistre-t-il le projet ? Son fichier est-il retrouvé (titre de la fenêtre de FL,
  Spotlight, dossiers habituels) ? FL ouvre-t-il la copie rangée sans rien demander, et le script lit-il la marque ?
- La suppression par ⌥ + Suppr (si ça échoue, l'app le dit).
- Questions sans réponse : l'accueil manquant venait-il d'une installation sans désinstallation ?
