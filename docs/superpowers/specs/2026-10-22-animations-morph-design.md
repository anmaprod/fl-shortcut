# Animations « morph » façon Apple — conception

Date : 2026-10-22 (relue et corrigée le même jour après une relecture indépendante) · Branche :
`claude/great-hopper-qihaiy` · macOS seulement (Windows en pause). Démos montrées au propriétaire : artifact
« Morphs FL Shortcuts » (A pastille → panneau, B gouttes de verre, C carte qui s'ouvre, D Magic Move).

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
| Blocs du créateur | le bloc attrapé se soulève, les autres s'écartent, il se pose avec un petit rebond (limites : §8) |
| Écoute de l'Organiser | pas de barres de son |
| Petits plus | reflet qui suit la souris, couleurs qui coulent, chiffres qui défilent (pas de retour du trackpad) |
| Sons | oui, très discrets |
| Livraison | tout d'un coup pour lui ; construit et poussé étape par étape (§12) |
| Façon de faire | « moteur de mouvement + morphs sur mesure » (approche 1 sur 3) |

## 2. Contraintes

- macOS 13 minimum : tout compile pour 13. Effets plus récents derrière `#available` (et `#if compiler(>=6.2)` pour
  les API de macOS 26, comme `GlassStyle.swift:280`). Sur macOS 13, pas de rappel de fin d'animation
  (`withAnimation(completion:)` est macOS 14) : minuteurs calculés par le moteur.
- Aucune copie de l'écran, même de nos propres fenêtres (règle du propriétaire ; aucune autorisation demandée).
- Mémoire : ~14 Mo menu seul, ~54 Mo fenêtre ouverte (mesure CI) ; budget +5 Mo au plus. Toute fenêtre de vol est
  retirée et libérée après usage (une fenêtre transparente grande comme l'écran coûterait des dizaines de Mo).
- « Réduire les animations » de macOS : fondu court (0,18 s), sans vol, sans rebond.
- Tout texte affiché a son anglais (`scripts/localisation.py`). Aucun nom de son ni texte tapé dans les journaux.
- Ce que les `List` (NSTableView) ne permettent pas, et qu'on ne fait donc pas : morph SwiftUI à travers elles,
  flou ou échelle d'une page de `List` (GlassStyle.swift:106-131 : titres en double vus au ralenti), ressort SwiftUI
  sur leurs insertions et suppressions (AppKit les anime lui-même), image et écart du glisser `.onMove` (dessinés par
  macOS), mouvement d'une ligne sans son fond de carte (`listRowBackground`).
- À garder intacts : `MenuBarExtra` et `MenuBarLabel` (`DebugSnapshot.swift:275-300`, seule vue toujours vivante qui
  sait ouvrir la fenêtre principale : `AccountLink.openEditor` à la fin de l'accueil, depuis la désinstallation et à
  la reprise ; `debug.open` et `debug.macro` des scripts CI) ; l'ordre des scènes (`FLShortcutApp.swift:38-58`) ;
  les cas de `Phase` de l'Organiser ; `OrganizerWindow.controller` vidé dès la fermeture ; le modèle du créateur
  libéré ; l'image de l'icône par état (`MenuBarIconTests`).
- Scripts CI (`scripts/mesure-interface.sh`) : liste des blocs = `List` (compte des lignes), fenêtre principale =
  scène `Window` (`AppKitWindow`), coordonnées de glisser inchangées, aucune fenêtre de vol visible au repos
  (`fits()`, `screenPoint`, `capture` prennent la première ou la dernière fenêtre).

## 3. Le moteur de mouvement (`MotionEngine.swift`)

Toutes les animations passent par lui ; aucune valeur de ressort ni de durée ailleurs dans le code.

- **Trois ressorts** (réponse multipliée par `DebugSnapshot.slowMotion`) :
  - *vif* `spring(response: 0.35, dampingFraction: 0.78)` : boutons, pastilles, gouttes qui rentrent, survol ;
  - *doux* `spring(response: 0.5, dampingFraction: 1)` : pages, menu, cartes, vols ;
  - *liquide* `spring(response: 0.55, dampingFraction: 0.62)` : gouttes de verre seulement.
  Aides existantes rattachées : `Motion.morph` → doux (au lieu de 0,8 s), `Motion.lift` → vif, `quickMorph` garde
  (0,35 ; 0,92) pour l'inspecteur, `smooth` (0,2 s) devient calculé (× ralenti) au lieu d'une constante.
  Tout ce qui échappait au ralenti (MenuReveal, StyledMenu, `MacroStepsPane.spring`, fondus `NSAnimationContext`,
  cadre de l'Organiser) passe par le moteur.
- **Durées, pures et testées** : `Motion.settle(response:damping:)` = temps pour que le ressort soit posé (même formule
  que la page de démo) ; sert aux minuteurs (macOS 13), aux enchaînements et aux sûretés. Les animations AppKit
  (cadre d'une fenêtre, fondu d'une fenêtre) gardent une courbe d'AppKit (pas de ressort) avec une durée du moteur.
- **Gel, règle pure et testée** : `MotionPolicy.mode(reduceMotion:slowMotion:surface:isKey:appActive:)` → `.full`,
  `.reduced` ou `.frozen`. Seule la fenêtre principale (et le créateur qu'elle contient) gèle, quand l'app n'est pas
  active et qu'elle n'est pas la fenêtre clé. Toujours vivantes, parce qu'elles servent pendant que FL ou les
  Réglages sont devant : le menu de l'icône, l'Organiser, le guide des autorisations, le badge de pause, la bulle
  d'aide, la barre d'enregistrement, les vols lancés par un clic. Ralenti actif : jamais `.reduced` (comme
  aujourd'hui, pour filmer le vrai mouvement).
- **Gel appliqué** à la racine de la fenêtre principale (`MotionGate`) : transaction sans animation et
  `disablesAnimations = true` (coupe aussi les `.animation(_:value:)` internes) ; reflet coupé. Dégel dès que la
  fenêtre redevient clé. Les indicateurs qui tournent du système (attente réseau : Communauté, compte, aide,
  inspecteur, désinstallation) restent tels quels : ils ne s'affichent que pendant une attente, dans nos fenêtres.
- **Reflet qui suit la souris** (`glassHighlight()`) : `onContinuousHover`, dégradé radial blanc très léger
  (`plusLighter`) découpé à la forme ; seulement pendant le survol ; coupé si gelé ou réduit. Sur les boutons de
  verre, les cartes de la Communauté, des Macros et des familles, les lignes `cardRow`.
- **Couleurs qui coulent** : changement de teinte (page, famille, icône, dégradé) animé en doux ; lavis de fond de
  page en 0,6 s (au lieu de 0,9).
- **Chiffres qui défilent** : `.contentTransition(.numericText())` (macOS 13) sur les nombres que l'app dessine
  elle-même (résumés de page, compteurs de l'Organiser, Communauté). Les badges de la barre latérale, dessinés par
  macOS, restent instantanés.
- **Sons** (`InterfaceSound.swift`) : sons du Mac (`NSSound(named:)`, une copie par lecture pour pouvoir se
  superposer), volume 0,15 ; absents du Mac → silence. Seulement dans les fenêtres de l'app et à la fin de
  l'Organiser :
  - carte qui s'ouvre et créateur qui s'ouvre « Pop » ; carte et créateur qui se ferment « Bottle » ;
  - goutte qui se détache « Tink » ;
  - Organiser terminé (rangement ou retour réussi) « Glass » : FL vient d'être arrêté par l'Organiser.
  Le menu de l'icône et les fenêtres qui s'ouvrent depuis lui restent muets (FL est souvent devant et peut jouer).
  Règle pure : `InterfaceSound.allowed(event:enabled:systemSounds:appActive:organiserBusy:)` — réglage de l'app
  activé, réglage macOS « Effets sonores de l'interface » activé, app active pour les sons de fenêtre, jamais pendant
  l'écoute, le rangement ou le retour de l'Organiser. Réglage « Sons de l'interface » dans le menu ⋯ (à côté de
  « Effet Liquid Glass »), clé `interfaceSounds`, activé par défaut.

## 4. La couche de vol (`FlightLayer.swift`)

Un seul mécanisme pour ce qui vole d'un endroit à un autre dans une fenêtre (icône, titre, touche, carte).

- **Cadres lus par AppKit** (`frameProbe(id:)`, `NSViewRepresentable`) : rectangle réel de la vue, lignes de `List`
  comprises. Un cadre est oublié quand sa vue quitte la fenêtre (cellules de `List` réutilisées).
- **Couche** : vue SwiftUI au-dessus de tout le contenu de la fenêtre (`.overlay` à la racine, `.ignoresSafeArea()`,
  sans clic). Conversion pure et testée vers la couche par `NSView.convert` entre la vue mesurée et la vue de la
  couche (pas de retournement par la hauteur de la fenêtre : faux sous une barre d'outils ou un titre).
- **Un vol** : une copie part de l'élément de départ (qui reste visible) et va jusqu'à l'élément d'arrivée (caché
  jusqu'à l'atterrissage), avec le ressort doux. Contenus possibles : icône (symbole, teinte, taille), texte (police),
  touche, fond de carte ; la copie est dessinée à la taille d'arrivée et mise à l'échelle depuis celle de départ.
  Cadres lus au moment du vol, après la mise en page, sur l'état final (aucun décalage d'apparition en cours à
  l'arrivée). Jamais vers la barre d'outils (AppKit, au-dessus de la couche).
- **Interruption** : un nouveau vol vers ailleurs repart de la position courante ; deux vols du même élément ne
  coexistent jamais (le second remplace le premier).
- **Sûreté** : un vol se termine au plus tard à 2 s × ralenti de son départ, quoi qu'il arrive ; aucun élément ne
  reste caché. Cadre manquant, mode réduit ou gelé : pas de vol, simple apparition.

## 5. Le menu de l'icône (`MenuBubble.swift` + `MenuPanel.swift`)

On garde le menu de SwiftUI (`MenuBarExtra` en fenêtre) : l'icône, l'ouverture, la fermeture, `openWindow`, les
objets d'environnement et les commandes CI restent les siens. On rend seulement sa fenêtre transparente pour y
dessiner notre propre bulle.

- **Fenêtre** (déjà reçue par `MenuPanel.attach`) : à chaque ouverture, fond transparent, pas d'ombre système ; la
  vue de fond posée par macOS (`NSVisualEffectView` dans la hiérarchie de la fenêtre) est masquée. Notre contenu a
  une marge transparente autour de la bulle pour son ombre.
- **Repli automatique** : si cette vue de fond n'est pas trouvée, si la fenêtre n'a pas la forme attendue, ou si
  `defaults write app.flshortcut.FLShortcut legacyMenu -bool YES` : le menu d'aujourd'hui, inchangé (bulle de macOS,
  contenu qui se déploie). Jamais de menu cassé.
- **Bulle** : pastille de verre de la taille de l'icône, partant de l'icône (son cadre à l'écran, lu par
  `statusButton`, même quand macOS décale le menu près d'un bord) → bulle du menu (ressort doux) ; les lignes
  arrivent l'une après l'autre (reprise de `menuRevealRow`) quand la bulle est presque posée (temps du moteur).
  Hauteur du contenu qui change pendant l'ouverture (alerte, échec de macro) : la bulle suit, en doux.
- **Fermeture** : celle d'aujourd'hui (`MenuPanel.close` : lignes d'abord, puis le reste, puis `performClick`), avec
  la bulle qui rentre dans l'icône au lieu du fondu de toute la fenêtre.
- **Verre** : macOS 26 et plus avec « Effet Liquid Glass » activé : verre de macOS ; premier pas du plan, vérifier sur
  la CI qu'il reprend ce qu'il y a derrière la fenêtre ; sinon bulle opaque. Avant macOS 26, verre coupé ou « Réduire
  la transparence » : bulle opaque (fond de fenêtre du système et lueur de marque), jamais un voile plat.
- Accessibilité, survol des lignes, activation de l'app : inchangés (c'est toujours le menu de SwiftUI).

## 6. Les fenêtres qui sortent du clic (`WindowLauncher.swift`)

- **Fenêtre de vol** : fenêtre sans bord, transparente, sans clic (`ignoresMouseEvents`), niveau `.popUpMenu`,
  `[.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]`, à la taille du trajet seulement, une par
  vol, retirée et libérée à la fin ; exclue des rapports et captures de `DebugSnapshot`. Dedans, la vue de la couche
  de vol : une bulle de verre qui va du cadre de départ (ligne cliquée du menu, bouton) au cadre de la fenêtre et
  emporte l'icône et le titre de la ligne jusqu'en haut de la fenêtre.
- **Pas de vol** (ouverture normale de macOS) si : la fenêtre est déjà ouverte, réduite dans le Dock, en plein écran
  ou sur un autre espace ; le départ et l'arrivée sont sur deux écrans différents ; mode réduit.
- **Fenêtres créées par l'app** (Organiser, accueil, désinstallation, guide des autorisations) : créées tout de suite
  invisibles (`alphaValue = 0` avant d'être montrées), la bulle vise leur cadre ; à l'atterrissage, la fenêtre
  apparaît (0,12 s) pendant que la bulle s'efface.
- **Fenêtre principale** (scène `Window` de SwiftUI, qu'on ne peut pas cacher avant sa première image) : la bulle vise
  le dernier cadre connu de la fenêtre (mémorisé à chaque déplacement ou redimensionnement ; première fois : taille
  par défaut centrée sur l'écran) ; `openWindow` n'est appelé qu'à l'atterrissage ; la bulle reste en place jusqu'à
  ce que la fenêtre soit visible (1 s au plus), puis s'efface (0,15 s). Si la fenêtre s'ouvre ailleurs que prévu, la
  bulle s'efface sans viser.
- **Fermeture par l'utilisateur** (bouton rouge, ⌘W, « Fermer ») : la fenêtre disparaît, une bulle part de son cadre
  et rentre dans l'icône de la barre des menus (même écran seulement). Fermeture décidée par l'app (fin de l'accueil,
  qui ouvre la fenêtre principale) : son fondu actuel, pas de bulle. Le contrôleur de l'Organiser est vidé tout de
  suite : la bulle ne garde que des cadres.
- **Sans départ** (ouverte par l'app : lancement, retour après une autorisation, `AppResume`) : elle sort de l'icône
  de la barre des menus, là où elle rentre en se fermant. Icône invisible (barre des menus masquée, plein écran) :
  animation d'ouverture de macOS (`animationBehavior = .documentWindow`) ; sinon `.none`, la bulle faisant
  l'animation. Pas d'échelle maison (impossible sur une fenêtre AppKit).
- **États, purs et testés** : `LaunchState` (repos, vol, attente de la fenêtre, apparition, fermeture). Double clic,
  fermeture pendant l'ouverture, fenêtre qui n'arrive pas : jamais de bulle restée à l'écran ni de fenêtre invisible.
- Badge de pause, bulle d'aide, barre d'enregistrement : leur fondu, avec la durée du moteur.
- **Créateur de macros** (il vit dans la fenêtre principale) : il s'ouvre depuis la ligne de la macro (couche de vol,
  démo C) et y retourne si la ligne est visible ; sinon le fondu actuel.

## 7. La fenêtre principale

- **Changement de page** (démo D) : l'icône de la ligne choisie vole jusqu'à l'icône d'en-tête de la page. La page
  arrive du flou au net sans se déplacer ni changer d'échelle (pour que l'atterrissage soit exact), le lavis de fond
  coule. L'ancienne page part tout de suite (pas de titres en double). Le titre de la barre d'outils change sans
  transition (AppKit). Pas de lignes qui montent une à une (leur fond de carte ne suivrait pas).
- **Listes** : chaque ajout, suppression, déplacement ou filtrage passe par `withAnimation` : AppKit fait glisser,
  replier et déplier les lignes (son animation à lui, pas notre ressort), au lieu de sauter. Au-delà de 60 lignes
  changées d'un coup (`ListMotion.animates(changes:)`, pur et testé), changement direct.
- **Cartes au lieu des feuilles** (`cardPresenter`) : `EditSheet`, `CatalogEditSheet`, `GuideSheet`,
  `MacroTemplatesSheet` et les feuilles de la Communauté deviennent des cartes de verre qui grandissent depuis
  l'élément cliqué (sinon depuis le centre) ; pour un raccourci, le nom et la touche volent jusqu'en haut de la carte.
  Derrière : voile de verre dépoli légèrement assombri. Règles :
  - fermeture par une action donnée par le présentateur (`cardDismiss`), qui remplace tous les
    `@Environment(\.dismiss)` de ces vues (EditorView, MacroLibraryView, CommunityView) ;
  - vraie modale : tout le contenu derrière `.disabled(true)` et `.accessibilityHidden(true)` (ses raccourcis clavier,
    dont les `.defaultAction` des pages, ne répondent plus), boutons de la barre d'outils désactivés, recherche
    couverte, focus posé dans la carte (`defaultFocus`) ;
  - la fenêtre ne se ferme pas pendant une carte (`.closable` retiré le temps de la carte : bouton rouge et ⌘W
    inactifs) ;
  - Échap = bouton `.cancelAction` de la carte (jamais un moniteur à part : l'enregistrement d'une touche garde Échap),
    Entrée = bouton `.defaultAction`, clic sur le voile = Annuler ;
  - hauteur au plus celle de la fenêtre moins les marges, contenu qui défile au-delà (guide 640×540, fiche de la
    Communauté 540×580, modèles 540×470) ;
  - une carte demandée pendant qu'une autre se ferme attend la fin de la fermeture (fiches qui se suivent, signalement
    après la fiche) ; fermeture idempotente ; aucun modèle retenu.
- Notifications et toasts : naissance depuis la pastille de statut (déjà `glassID`), ressorts du moteur.

## 8. Le créateur de macros

- **Bloc déplacé dans la liste** : pendant le glisser, l'image du bloc et l'écart des autres sont ceux de macOS
  (`.onMove` ; le remplacer casserait l'ordre des blocs, la palette et l'essai CI). À la pose, le bloc s'éclaire
  brièvement de sa couleur (fond de sa carte, vif). C'est la seule limite au choix « il se soulève ».
- **Bloc ajouté d'un clic dans la palette** : il vole de la palette à sa place (la ligne de la palette reste
  visible), la liste s'ouvre pour l'accueillir. Ajouté en glissant : pas de vol (il est déjà où on l'a lâché).
- **Gouttes de verre** (démo B), barre du bas (`actionBar`) : sans bloc choisi, la goutte « Ajouter » seule ; avec un
  bloc choisi, « Dupliquer » et « Supprimer » en sortent (liquide) et y rentrent (vif). macOS 26 avec verre :
  `GlassEffectContainer` + `glassEffectID` (fusion native). Avant macOS 26 ou verre coupé : gouttes dessinées
  (`Canvas`, flou + seuil alpha) pilotées par une progression animée ; positions pures et testées
  (`DropLayout.positions(count:progress:width:)`). Fenêtre étroite : le repli `ViewThatFits` actuel (icônes seules),
  gouttes comprises. Les boutons restent de vrais boutons (clic, ⌘D, ⌫, VoiceOver) posés sur les gouttes ; un bouton
  caché n'a plus de raccourci (il n'y a alors pas de bloc à dupliquer ou supprimer). Son « Tink » au détachement.
  La CI (macOS 26) teste les deux chemins : verre activé et verre coupé.
- **Inspecteur** : quand on choisit un bloc à la souris, son icône vole de la ligne jusqu'en haut de l'inspecteur ;
  aux flèches du clavier, pas de vol (fondu rapide actuel).

## 9. L'Organiser

- **Écoute** : compteur qui défile (« 3 sur 12 »), progression dessinée par l'app (capsule qui glisse en doux, à la
  place de la barre du système), une pastille par famille qui apparaît au premier son classé, son nombre qui
  défile. Les nombres sont ceux de l'aperçu : la session signale la famille définitive de chaque son (sons reconnus
  à leur nom dès le départ ; sons écoutés après les règles `keeps` et synthé de mélodies, appliquées son par son),
  jamais un nom. Test : somme des pastilles = familles de l'aperçu.
- **Attentes** (FL qui enregistre, FL qui ouvre la copie) : `WaitingPulse`, l'icône qui clignote (`symbolEffect`
  répété) et les indicateurs qui tournent de l'Organiser sont remplacés par un compteur de secondes (mis à jour une
  fois par seconde).
- **Aperçu** : dans l'ordre, la fenêtre prend sa hauteur (courbe d'AppKit), puis les pastilles deviennent les cartes
  des familles (`matchedGeometryEffect`, vue SwiftUI pure ; ces éléments ne prennent ni `pageMorph` ni `morphIn`).
  Une couleur changée coule sur tous les sons de la famille ; « Dégradé » se forme en glissant.
- **Organiser** (démo A) : le bouton devient sur place la pastille de progression (étape en cours), puis la fenêtre
  se resserre autour d'elle ; à la fin, la pastille devient « ✓ N sons rangés » (N = sons classés, le nombre de
  l'aperçu ; son « Glass »), puis l'écran du résultat, chiffres qui défilent. Erreur : l'écran d'erreur actuel, sans
  son.
- **« Revenir comme avant »** : le bouton devient la pastille « Retour en arrière… », puis l'écran « remis comme
  avant » actuel. Les cas de `Phase` ne changent pas.

## 10. Vérification (chasse aux bugs)

- **Tests unitaires** : `MotionPolicy` (chaque surface, actif ou non, clé ou non), `Motion.settle`,
  `InterfaceSound.allowed`, conversion de la couche de vol, `LaunchState` (double clic, fermeture pendant
  l'ouverture, fenêtre absente, deux écrans), présentateur de cartes (file d'attente, fermeture idempotente, Échap,
  fenêtre non fermable), `ListMotion.animates`, `DropLayout.positions`, compteur de secondes, familles de l'écoute =
  familles de l'aperçu.
- **Interruptions** : chaque animation repart de sa position courante ; aucun vol ni bulle au-delà de sa sûreté.
- **Ralenti ×10 sur la CI** : nouvelles commandes de capture sans clic réel (`menu`, `vol`, `carte`, `gouttes` +
  « lent ») et prises d'images en rafale dans `scripts/mesure-interface.sh` : menu (ouverture, fermeture), fenêtre
  depuis une ligne, changement de page, carte, créateur, gouttes (verre activé et coupé), phases de l'Organiser
  (écrans de démo existants). Chaque image est relue (sauts, clignotements, doublons, bords coupés).
- **Mémoire** : mesure CI existante, +5 Mo au plus ; aucune fenêtre de vol restante au repos.
- **Relecture** indépendante à chaque étape, puis de toute la branche.
- **Liste de contrôle pour le Mac du propriétaire** : une ligne par animation (quoi ouvrir, quoi regarder).
- **Limites connues** : la CI tourne sur macOS 26, le propriétaire sur macOS 27 ; les chemins de macOS 13 à 25
  compilent mais ne sont pas filmés.

## 11. Hors périmètre

Retour du trackpad ; sons faits sur mesure ; remplacement des `List` et de `.onMove` ; menu de l'icône écrit de zéro ;
Windows ; fenêtres système (`NSAlert`, Ouvrir/Enregistrer) et popovers de couleur et d'icône.

## 12. Livraison, dans l'ordre

0. Accès GitHub rétabli (lecture de la CI et de ses images) : sans lui, aucune étape n'est vérifiable.
1. Moteur (ressorts, durées, gel, ralenti partout, sons, reflet, chiffres, couleurs).
2. Couche de vol.
3. Menu de l'icône (premier pas : bulle transparente et verre vérifiés sur la CI ; repli automatique).
4. Fenêtres qui sortent du clic.
5. Fenêtre principale (pages, listes, cartes).
6. Créateur de macros (pose, palette, gouttes, inspecteur).
7. Organiser.
8. Captures CI au ralenti, docs (HISTORIQUE, CLAUDE.md), relecture finale, liste de contrôle.

Chaque étape : son commit, ses tests, poussée sur la branche ; la suivante ne commence qu'une fois la CI de la
précédente lue et verte (compilation, tests, images). Le propriétaire reçoit l'ensemble à la fin.
