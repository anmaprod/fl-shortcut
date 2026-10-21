# FL Shortcuts — à lire avant de travailler

- Réponds en français, en tutoyant le propriétaire (musicien, pas développeur). Textes de l'app, commentaires et
  commits en français. Priorité macOS ; Windows en pause (compilé seulement pour un tag `v*`).
- Branche la plus récente : **`claude/great-hopper-qihaiy`** (en avance de 138 commits sur `claude/relaxed-mayer-ndguzv`).
  Pas de nouvelle PR sans demande (anmaprod/fl-shortcut#1 existe). Un push lance la CI ; ne pas la relancer à la main
  sans demande. Dernière CI verte : commit 7f45bea (443 tests Mac).
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
  - analyse : sons classés par leur nom ou écoutés (clip audio : sa note C5), patterns et chanson entière joués à leur
    tempo (JAMAIS accéléré : refusé par le propriétaire), FL dit ce qui joue (relevé continu) ; un nom déjà donné par
    l'Organiser est revérifié à l'écoute ; le diagnostic donne les sons de chaque pattern et piste (numéros) ;
  - classement réglé (arpège → mélodie, drum loop → Drums, hi-hat par ses aigus ; 3 notes nettes ou plus → mélodie,
    jamais drums ni FX ; un canal au nom d'un synthé de mélodies, ZENOLOGY, Serum… → jamais drums ni FX) ;
  - « Organiser » : sons sans note supprimés (⌥ + Suppr de FL), Channel rack, Mixer (un bus par famille, son sur le
    Master relié à une piste libre, pistes inutiles remises à neuf), patterns et Playlist dans le même ordre (menu
    « Move up » de chaque piste), mêmes noms partout ; « Revenir comme avant » défait tout sauf les suppressions ;
  - IA de macOS sur une fenêtre de 1 s (son court complété) ; « Voix » seulement si l'IA entend une voix ; écoute
    toujours au tempo d'origine (vérifié, sinon arrêt) ; règle de chaque son dans le diagnostic (`c4:melodie+ia`) ;
  - Playlist, un son par piste et les clips d'un même son (mêmes sons joués) réunis sur sa piste
    (`OrganizerClipMover.swift`) : chaque clip retrouvé dans la fenêtre de FL au nom de son pattern au moment de le
    déplacer, sélectionné seul (⌘D, ⌘ + clic), monté/descendu (⇧↑/⇧↓), vérifié en relisant la fenêtre, sinon remis ;
    sans l'autorisation d'écran : l'ancien découpage (pattern entier : op 26, ⇧C, ⇧↓) ; puis les pistes rangées par
    famille (« Move up »). FL n'a aucune commande pour sélectionner les clips d'une seule piste (manuel lu).
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
- Réunion des clips : ⌘ + clic sélectionne-t-il bien un seul clip ? Les noms des clips (abrégés « M..3 ») sont-ils lus ?
- La suppression par ⌥ + Suppr et le rangement de la Playlist par « Move up » (si ça échoue, l'app le dit).
- Un son par piste : ⇧C sélectionne-t-il bien les clips du pattern ouvert par le script ? (sinon, tout remonte et
  l'app le dit) ; le bouton « Arrangement » lu dans le titre de la Playlist.
- Questions sans réponse : lire la fenêtre Playlist pour un « split by channel » ? l'accueil manquant venait-il d'une
  installation sans désinstallation ?
