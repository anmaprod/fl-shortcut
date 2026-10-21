# FL Shortcuts — à lire avant de travailler

- Réponds en français, en tutoyant le propriétaire (musicien, pas développeur). Textes de l'app, commentaires et
  commits en français. Priorité macOS ; Windows en pause (compilé seulement pour un tag `v*`).
- Branche la plus récente : **`claude/great-hopper-qihaiy`** (en avance de 138 commits sur `claude/relaxed-mayer-ndguzv`).
  Pas de nouvelle PR sans demande (anmaprod/fl-shortcut#1 existe). Un push lance la CI ; ne pas la relancer à la main
  sans demande. Dernière CI verte : commit 7f45bea (443 tests Mac).
- Tout texte affiché doit avoir son anglais (la CI échoue sinon) : `python3 scripts/localisation.py generer trad.json`.
- Historique, décisions et échecs : `docs/contexte/HISTORIQUE.md` ; lien avec FL (script v14) : `PROTOCOL.md`.

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
- **Organiser v5** (`Sources/FLShortcut/Organizer*.swift`, `SoundFeatures.swift`, `SoundFamilies.swift`, script FL v14) :
  - analyse : sons classés par leur nom ou écoutés (clip audio : sa note C5), patterns et chanson entière joués en
    accéléré, FL dit ce qui joue (relevé continu) ; un nom déjà donné par l'Organiser est revérifié à l'écoute ;
  - classement réglé (arpège → mélodie, drum loop → Drums, hi-hat par ses aigus) ;
  - « Organiser » : sons sans note supprimés (⌥ + Suppr de FL), Channel rack, Mixer (un bus par famille, son sur le
    Master relié à une piste libre, pistes inutiles remises à neuf), patterns et Playlist dans le même ordre (menu
    « Move up » de chaque piste), mêmes noms partout ; « Revenir comme avant » défait tout sauf les suppressions.

## Pas encore vérifié sur le vrai FL
- La suppression par ⌥ + Suppr et le rangement de la Playlist par « Move up » (si ça échoue, l'app le dit).
- Questions sans réponse : lire la fenêtre Playlist pour un « split by channel » ? l'accueil manquant venait-il d'une
  installation sans désinstallation ?
