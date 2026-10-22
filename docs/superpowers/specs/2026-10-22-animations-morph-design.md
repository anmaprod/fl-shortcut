# Animations « morph » façon Apple — conception

Date : 2026-10-22 · Branche : `claude/great-hopper-qihaiy` · macOS seulement (Windows en pause).
Démos montrées au propriétaire : artifact « Morphs FL Shortcuts » (A pastille → panneau, B gouttes de verre, C carte
qui s'ouvre, D Magic Move).

## 1. Ce que le propriétaire veut

« Des très belles animations type Apple, vraiment bossées comme Apple […] mais mieux qu'Apple », « que tout soit beau
et facile », « ultra bien travaillé SANS BUG ET SANS DÉFAUTS ». Ce qui le gêne aujourd'hui : pages qui changent
sèchement, fenêtres qui surgissent, listes qui sautent, « tout est un peu plat ».

### Décisions prises avec lui

| Sujet | Décision |
|---|---|
| Démos | les quatre (A, B, C, D), chacune à sa place |
| Zones | menu de l'icône, fenêtre principale, créateur de macros, Organiser |
| Caractère | mix : petit rebond sur les petites choses, doux sans rebond sur les grandes |
| Vitesse | comme Apple, environ une demi-seconde |
| Légèreté | le plus beau quand l'app est devant ; rien ne bouge pendant qu'on travaille dans FL |
| Menu de l'icône | naît de l'icône en pastille et grandit jusqu'au menu (démo A) |
| Fenêtres | sortent de l'endroit cliqué et y retournent |
| Blocs du créateur | le bloc attrapé se soulève, les autres s'écartent, il se pose avec un petit rebond |
| Écoute de l'Organiser | pas de barres |
| Petits plus | reflet qui suit la souris, couleurs qui coulent, chiffres qui défilent (pas de retour du trackpad) |
| Sons | oui, très discrets |
| Livraison | tout d'un coup (construit et vérifié étape par étape, poussé ensemble) |
| Façon de faire | « moteur de mouvement + morphs sur mesure » (approche 1 sur 3) |

## 2. Contraintes

- macOS 13 minimum : tout compile pour 13 ; les effets plus récents derrière `#available` (vrai Liquid Glass :
  macOS 26 ; le reste a un équivalent plus simple).
- Aucune copie de l'écran, même de nos propres fenêtres (règle du propriétaire ; pas d'autorisation demandée).
- Mémoire : aujourd'hui ~14 Mo menu seul, ~54 Mo fenêtre ouverte (mesure CI) ; budget +5 Mo au plus. Aucune
  animation infinie (les deux qui existent, dans l'Organiser, disparaissent).
- « Réduire les animations » de macOS : tout devient un fondu court (0,18 s), sans vol ni rebond.
- Tout texte affiché a son anglais (`scripts/localisation.py`). Aucun nom de son ni de texte tapé dans les journaux.
- Les listes restent des `List` (NSTableView) : elles ne suivent ni le flou ni l'échelle d'une page entière
  (GlassStyle.swift:106-131, titres en double vus au ralenti sur la CI) ; aucun morph SwiftUI à travers elles.
- Tests existants à garder : `OrganizerWindowTests` (cas de `Phase`, fermeture idempotente, contrôleur libéré),
  `MacroCreatorWindowTests` (modèle libéré), `MenuBarIconTests` (image de l'icône par état).
- Scripts CI (`scripts/mesure-interface.sh`) : la liste des blocs reste une `List` (compte des lignes), la fenêtre
  principale reste une scène `Window` (classe `AppKitWindow`), coordonnées de glisser inchangées.

## 3. Le moteur de mouvement (`MotionEngine.swift`)

Toutes les animations passent par lui ; aucune valeur de ressort ailleurs dans le code.

- **Trois ressorts** (réponse multipliée par `DebugSnapshot.slowMotion`) :
  - *vif* `spring(response: 0.35, dampingFraction: 0.78)` : boutons, pastilles, blocs, lignes, survol ;
  - *doux* `spring(response: 0.5, dampingFraction: 1)` : pages, fenêtres, menu, cartes, vols ;
  - *liquide* `spring(response: 0.55, dampingFraction: 0.62)` : gouttes de verre seulement.
  Les aides existantes s'y rattachent : `Motion.morph` → doux (au lieu de 0,8 s), `Motion.lift` → vif,
  `quickMorph` garde (0,35 ; 0,92) pour le contenu de l'inspecteur, `smooth` (0,2 s) pour les petits changements d'état.
  Tout ce qui échappait au ralenti (MenuReveal, StyledMenu, `MacroStepsPane.spring`, fondus `NSAnimationContext`,
  `setFrame` de l'Organiser) passe par le moteur.
- **Règle de mouvement, pure et testée** : `MotionPolicy.mode(reduceMotion:slowMotion:surface:appActive:)` →
  `.full`, `.reduced` ou `.frozen`. `surface` : `.window` (fenêtres de l'app), `.menu`, `.organiser`, `.flight`.
  Gel : une fenêtre de l'app quand l'app n'est pas active (FL ou une autre app devant). Le menu de l'icône,
  l'Organiser (il flotte au-dessus de FL) et les vols lancés par un clic jouent toujours. Ralenti actif : jamais
  `.reduced` (comme aujourd'hui, pour filmer le vrai mouvement).
- **Gel appliqué à la racine** de chaque fenêtre (`MotionGate`) : la transaction perd son animation ; le reflet et les
  vols sont coupés. L'état actif vient de `NSApplication.didBecomeActive/didResignActive`.
- **Reflet qui suit la souris** (`glassHighlight()`) : `onContinuousHover`, dégradé radial blanc très léger
  (`plusLighter`) découpé à la forme du verre ; seulement pendant le survol, rien sinon ; coupé si gelé ou réduit.
  Sur les boutons de verre, les cartes de la Communauté, des Macros et des familles, les lignes `cardRow`.
- **Couleurs qui coulent** : tout changement de teinte (page, famille, icône, dégradé) passe par une animation douce ;
  le lavis de fond de page coule en 0,6 s (au lieu de 0,9).
- **Chiffres qui défilent** : `.contentTransition(.numericText())` sur les nombres que l'app dessine elle-même
  (résumés de page, compteurs de l'Organiser, Communauté). Les badges de la barre latérale, dessinés par macOS,
  restent instantanés.
- **Sons** (`InterfaceSound.swift`) : sons du Mac (`NSSound(named:)`), volume 0,15 ; absents du Mac → silence.
  Ouverture d'un menu, d'une carte ou d'une fenêtre « Pop » ; fermeture « Bottle » ; goutte qui se détache « Tink » ;
  Organiser terminé « Glass ». Règle pure : `InterfaceSound.allowed(enabled:appActive:organiserBusy:)` — seulement si
  l'app est active (donc jamais quand FL est devant) et jamais pendant l'écoute, le rangement ou le retour en arrière
  de l'Organiser. Réglage « Sons de l'interface » dans le menu ⋯ (à côté de « Effet Liquid Glass »), clé
  `interfaceSounds`, activé par défaut.

## 4. La couche de vol (`FlightLayer.swift`)

Un seul mécanisme pour tout ce qui vole d'un endroit à un autre (icône, titre, touche, carte).

- **Cadres lus par AppKit** (`frameProbe(id:)`, `NSViewRepresentable`) : rectangle de la vue dans la fenêtre et à
  l'écran, quelle que soit la façon dont SwiftUI l'héberge (lignes de `List` comprises).
- **Couche par fenêtre** : vue SwiftUI posée au-dessus de toute la fenêtre (`.overlay` à la racine, sans clic),
  qui dessine les éléments en vol. Conversion pure et testée des coordonnées de fenêtre (origine en bas) vers la
  couche (origine en haut) : `FlightGeometry.local(_:in:)`.
- **Un vol** : élément de départ et d'arrivée cachés pendant le vol, copie dessinée qui va de l'un à l'autre avec
  le ressort doux, puis l'élément d'arrivée réapparaît. Interruptible : un nouveau vol vers ailleurs repart de la
  position courante. Cadre manquant (élément hors écran, page de recherche) : pas de vol, simple apparition.
- **Nettoyage garanti** : chaque vol se termine au plus tard 2 s après son départ, quoi qu'il arrive (minuteur de
  sûreté) ; aucun élément ne reste caché.
- Couche à l'écran (entre le menu et les fenêtres) : voir §6, même vue SwiftUI dans une fenêtre transparente.

## 5. Le menu de l'icône (`MenuBubble.swift`)

`MenuBarExtra` est remplacé par un `NSStatusItem` et une fenêtre à nous, transparente, où l'app dessine sa bulle.

- **Fenêtre** : `NSPanel` sans bord, transparente, sans ombre système (l'ombre est dessinée), niveau `.popUpMenu`,
  `[.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]`, peut devenir clé (Échap, clavier), ne rend
  pas l'app active. Contenu actuel (`MenuContent`, largeur 300) inchangé.
- **Placement, pur et testé** : `MenuPlacement.frame(icon:size:visible:margin:)` — sous l'icône, centré sur elle,
  gardé dans l'écran de l'icône (marge 8). La pastille part de l'icône même quand le menu est décalé par le bord.
- **Ouverture** : pastille de verre de la taille de l'icône, juste sous elle → bulle du menu (ressort doux) ; les
  lignes apparaissent l'une après l'autre quand la bulle a fait ~60 % du chemin (reprise de `menuRevealRow`).
- **Fermeture** : lignes parties vite (vif), bulle rentrée dans l'icône (doux), puis la fenêtre est retirée. Si une
  ligne a été choisie, sa fenêtre part de cette ligne (§6).
- **Se ferme** au clic ailleurs (moniteurs global et local), à Échap, au nouveau clic sur l'icône, au changement
  d'espace ou d'app ; rouvre la fenêtre de l'app qui était devant (comportement actuel de `MenuPanel`).
- **Verre** : `glassEffect` sur macOS 26, matériau sur les plus anciens. Icône : mêmes images par état
  (`MenuBarIconTests`). VoiceOver : la bulle est lue comme un menu, l'icône a son nom.
- **Repli de sûreté** : `defaults write app.flshortcut.FLShortcut legacyMenu -bool YES` remet l'ancien
  `MenuBarExtra` (`MenuBarExtra(isInserted:)`), au cas où un Mac se comporterait mal.

## 6. Les fenêtres qui sortent du clic (`WindowLauncher.swift`)

- **Bulle fantôme** : fenêtre transparente sans bord, au-dessus de tout, avec la même vue que la couche de vol :
  une bulle de verre qui va du cadre de départ (ligne cliquée du menu, bouton) au cadre de la fenêtre, et emporte
  l'icône et le titre de la ligne jusqu'au haut de la fenêtre.
- **Ouverture** : la vraie fenêtre est créée tout de suite, invisible (`alphaValue = 0`, `animationBehavior = .none`)
  pendant que la bulle vole ; son cadre est lu dès qu'elle existe, puis la bulle vise ce cadre. À ~85 % du vol, la
  fenêtre apparaît (0,12 s) et la bulle s'efface ; la fenêtre fantôme est retirée.
- **Fermeture** : la fenêtre disparaît d'un coup, une bulle part de son cadre et rentre dans l'icône de la barre
  des menus.
- **Sans départ** (ouverte par l'app : lancement, retour après une autorisation, `AppResume`) : légère croissance
  depuis son centre (0,96 → 1) avec fondu.
- **États, purs et testés** : `LaunchState` (repos, vol, apparition, fermeture). Double clic, fermeture pendant
  l'ouverture, fenêtre qui n'arrive pas en 1 s : jamais de bulle restée à l'écran ni de fenêtre invisible (sur
  délai, la fenêtre est montrée normalement).
- Fenêtres concernées : principale (scène `Window`, lue par `WindowReader`), Organiser (`NSPanel`), accueil,
  désinstallation, guide des autorisations. Le badge de pause, la bulle d'aide et la barre d'enregistrement gardent
  leur fondu.
- **Créateur de macros** (il vit dans la fenêtre principale) : il s'ouvre depuis la ligne de la macro (couche de
  vol de la fenêtre, comme la démo C) et y retourne ; sans ligne visible, fondu actuel.

## 7. La fenêtre principale

- **Changement de page** : l'icône de la ligne choisie vole jusqu'à l'icône d'en-tête de la page (cachée pendant le
  vol) ; le titre se fond en place ; les 8 premières lignes montent l'une après l'autre (vif, 30 ms d'écart),
  seulement à l'arrivée sur la page (jamais quand une ligne réapparaît en défilant) ; le lavis de fond coule.
  L'ancienne page part toujours tout de suite (pas de titres en double).
- **Listes** : chaque ajout, suppression, déplacement ou filtrage animé avec le ressort vif (identifiants stables) ;
  ligne supprimée repliée, nouvelle dépliée. Règle pure `ListMotion.style(changes:)` : au-delà de 60 lignes
  changées d'un coup, simple fondu.
- **Cartes au lieu des feuilles** (`cardPresenter`) : `EditSheet`, `CatalogEditSheet`, `GuideSheet`,
  `MacroTemplatesSheet` et les feuilles de la Communauté deviennent des cartes de verre qui grandissent depuis
  l'élément cliqué (sinon depuis le centre) ; nom et touche volent jusqu'en haut de la carte. Derrière, un voile de
  verre dépoli et un léger assombrissement (le flou d'une page de `List` n'est pas possible). Clic à côté, Échap ou
  « Annuler » : retour dans l'élément ; Entrée : bouton par défaut. Modale pour VoiceOver, la page derrière ne prend
  plus de clic. Fermeture idempotente, carte libérée (pas de modèle retenu).
- Notifications et toasts : naissance depuis la pastille de statut (déjà `glassID`), ressorts du moteur.

## 8. Le créateur de macros

- **Bloc déplacé dans la liste** : premier pas du plan, vérifier si macOS accepte une image « soulevée » (plus grande,
  ombre douce, légèrement penchée comme `PaletteDragPreview`) pour le glisser d'une `List`. Sinon : image de macOS
  pendant le glisser. Dans les deux cas : les autres blocs s'écartent (vif) et le bloc posé fait un petit rebond
  (1,03 → 1).
- **Bloc ajouté depuis la palette** (clic ou glisser) : il vole de la palette à sa place (couche de vol), la liste
  s'ouvre pour l'accueillir.
- **Gouttes de verre** (démo B), barre du bas : sans bloc choisi, une goutte « Ajouter » ; avec un bloc choisi,
  Dupliquer, Supprimer et Essayer en sortent (liquide) et y rentrent. macOS 26 : `GlassEffectContainer` +
  `glassEffectID` (fusion native). Plus ancien : gouttes dessinées (`Canvas`, flou + seuil alpha) pilotées par une
  progression animée ; positions pures et testées (`DropLayout.positions(count:progress:)`). Les boutons restent de
  vrais boutons (clic, clavier, VoiceOver) posés sur les gouttes. Son « Tink » au détachement.
- **Inspecteur** : en changeant de bloc, l'icône du bloc vole de la ligne jusqu'en haut de l'inspecteur ; le
  contenu garde son fondu rapide.

## 9. L'Organiser

- **Écoute** : compteur qui défile (« 3 sur 12 »), progression qui glisse, une pastille par famille qui apparaît au
  premier son rangé, son nombre qui défile. La session signale la famille de chaque son classé (nombre seulement).
- **Plus d'animation infinie** : `WaitingPulse` et l'icône qui clignote (`symbolEffect` répété) sont retirés ; pendant
  les attentes, un compteur de secondes (mis à jour une fois par seconde) dit que ça avance.
- **Aperçu** : les pastilles des familles deviennent les cartes des familles (`matchedGeometryEffect` : vue SwiftUI
  pure, sans `List`) ; une couleur changée coule sur tous les sons de la famille ; « Dégradé » se forme en glissant.
- **Organiser** (démo A) : le bouton devient la pastille de progression (étape en cours), puis « ✓ N sons rangés »
  (son « Glass »), puis l'écran du résultat, chiffres qui défilent. « Revenir comme avant » : même mouvement à
  l'envers. Les cas de `Phase` ne changent pas.
- Changements de taille de la fenêtre : ressort doux du moteur (ralenti compris).

## 10. Vérification (chasse aux bugs)

- **Tests unitaires** : `MotionPolicy`, `InterfaceSound.allowed`, `MenuPlacement` (écrans multiples, bords, Dock),
  `FlightGeometry`, `LaunchState` (double clic, fermeture pendant l'ouverture, délai), présentateur de cartes
  (ouverture, fermeture idempotente, Échap), `ListMotion.style`, `DropLayout.positions`, compteur de secondes.
- **Interruptions** : chaque animation repart de sa position courante ; aucun vol ni bulle ne dépasse 2 s.
- **Ralenti ×10 sur la CI** : nouvelles commandes de capture (`menu`, `fenetre`, `carte`, `gouttes`, `vol` + « lent »)
  et prises d'images en rafale dans `scripts/mesure-interface.sh` : menu (ouverture, fermeture), fenêtre depuis une
  ligne, changement de page, carte, créateur, gouttes, phases de l'Organiser (écrans de démo existants). Chaque
  image est relue (sauts, clignotements, doublons, bords coupés). Il faut que la session puisse lire GitHub
  (aujourd'hui en échec : reconnexion demandée au propriétaire).
- **Mémoire** : mesure CI existante, +5 Mo au plus.
- **Relecture** indépendante à chaque étape, puis de toute la branche.
- **Liste de contrôle pour le Mac du propriétaire** : une ligne par animation (quoi ouvrir, quoi regarder).

## 11. Hors périmètre

Retour du trackpad ; sons faits sur mesure ; remplacement des `List` ; Windows ; animations des fenêtres système
(`NSAlert`, panneaux Ouvrir/Enregistrer) et des popovers de couleur et d'icône (système).

## 12. Livraison, dans l'ordre

1. Moteur (ressorts, règle, gel, ralenti partout, sons, reflet, chiffres, couleurs).
2. Couche de vol.
3. Menu de l'icône (+ repli `legacyMenu`).
4. Fenêtres qui sortent du clic.
5. Fenêtre principale (pages, listes, cartes).
6. Créateur de macros (glisser, palette, gouttes, inspecteur).
7. Organiser.
8. Captures CI au ralenti, docs (HISTORIQUE, CLAUDE.md), relecture finale, liste de contrôle.

Chaque étape : son commit, ses tests, la CI verte (compilation macOS) avant la suivante ; tout est poussé sur la
branche, le propriétaire reçoit l'ensemble.
