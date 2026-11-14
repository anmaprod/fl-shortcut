# Nom et couleur, Organiser — conception

Date : 2026-10-15 · Branche : `claude/relaxed-mayer-ndguzv` · macOS seulement (Windows plus tard).

## 1. Ce que l'utilisateur veut

- **Nom et couleur** : renommer et colorer l'élément sélectionné (piste du Mixer, canal du Channel rack, piste de la
  Playlist) depuis une macro, pour « les gens qui veulent s'organiser ». Le nom et la couleur sont choisis dans
  FL Shortcut, avec « la même palette de couleur que FL » : sa grille, son champ « # », et des couleurs récentes.
  « Il faut que ça repère ce qui est sélectionné, et si plusieurs choses sont sélectionnées ça ne fonctionne pas. »
- **Organiser** : « ça organise la session : les mélodies avec les mélodies, les drums ensemble et les FX ensemble ;
  une sorte d'IA qui analyse les sons, pas les noms ». Seulement la page ouverte (Mixer, Channel rack ou Playlist) :
  « le logiciel repère quelle page est ouverte et le fait ou non selon ce qu'il peut faire ».

### Décisions prises avec l'utilisateur

| Sujet | Décision |
|---|---|
| Nom | choisi d'avance dans FL Shortcut, écrit directement dans FL (aucune fenêtre) |
| Blocs | un seul bloc « Nom et couleur », nom et couleur facultatifs (au moins un) |
| Méthode | par le lien avec FL (script de FL étendu), pas par le clavier |
| Palette | grille et champ « # » de la fenêtre de couleur de FL ; rangée des couleurs récentes |
| Écoute | écoute réelle : chaque son joué sans être entendu, capté depuis FL seulement, classé sur le Mac |
| Organiser fait | regrouper (déplacer), colorer par famille, montrer le classement avant d'appliquer |
| Familles | 5 : Drums, Basse (808 compris), Mélodies, Voix, FX, plus « À vérifier » |

### Ce que l'API de FL permet (vérifié)

- Script : `mixer.setTrackName/Color`, `channels.setChannelName/Color`, `playlist.setTrackName/Color` (API 1) ;
  sélection : `mixer.isTrackSelected` (1), `channels.isChannelSelected` (1), `playlist.isTrackSelected` (12) ;
  `channels.midiNoteOn` (1, vélocité 0 = note off), `channels.getChannelType` (19), `channels.getTargetFxTrack` (1),
  `plugins.getPadInfo` (19, FPC), `mixer.getTrackPeaks` (1). Couleurs au format `0x--BBGGRR`.
- **Aucun** accès au son, ni au chemin des samples ; **aucune** fonction pour déplacer un canal ou une piste.
- Déplacer : Channel rack ⌥↑ / ⌥↓ (canal sélectionné, manuel de FL) ; Mixer : seulement « Move left / Move right »
  du menu de la piste (ou Maj + molette) ; Playlist : rien, et l'API ne dit pas quels clips sont sur quelle piste.
- Les couleurs récentes de FL ne sont ni dans l'API ni dans un fichier connu.

### Ajouts du 15/10 après-midi (2 vidéos de l'utilisateur)

« Pour les couleurs il faudra aussi des icônes (les mêmes que sur FL) : la personne choisit pour Mélodies une icône
et une couleur ; elle peut choisir de la mettre en fade ; ça fonctionne pareil sur Channel rack et Mixer ; il faut
sélectionner plusieurs pistes pour pouvoir faire un fade. »

- **Fade = « Gradient color… » de FL** (relevé sur la vidéo) : avec plusieurs pistes sélectionnées, la fenêtre
  « Gradient editor » montre deux cases **First** et **Last**, l'aperçu du dégradé entre elles, trois boutons
  (▶ copie First dans Last, ◀▶ échange, ◀ copie Last dans First), la roue de couleurs habituelle, Reset et Accept.
  Résultat mesuré sur 5 pistes : composantes rouge, vert et bleu en ligne droite de First (piste du haut) à Last
  (piste du bas). « Gradient color… » est grisé avec une seule piste sélectionnée.
- **Icônes** : « Change icon… » (menu de la piste du Mixer et de la Playlist ; « Rename, color and icon… », F2, pour
  les canaux) ouvre une grille de FL : 14 colonnes (Reset, Content, Instr, Solfège, Synth, Effect, Gear, Misc, Info,
  Number, Routing, Channel), 15 rangées de cases carrées, sous une barre de titres ; même taille dans le Mixer et la
  Playlist. **L'API de FL ne lit ni ne pose les icônes** (vérifié dans la doc des modules mixer, channels et
  playlist) : l'icône passe par la fenêtre de FL (voir §6 bis).
- **Couleurs : format** `0x--BBGGRR` d'après la doc ; le script passe toujours par `utils.RGBToColor` /
  `utils.ColorToRGB` de FL (ses propres fonctions, donc le même ordre que FL).

## 2. Contraintes (inchangées)

Jamais l'écran (ni capture ni lecture) ; Accessibilité et événements seulement. MIDI seulement pendant une action.
Rien ne tourne au repos. Très rapide, peu de mémoire. Style Liquid Glass. Textes et commentaires en français.
Swift 5.9, macOS 13 minimum (Organiser demande macOS 14.2, sinon message), pas de `@Observable`. Les étapes déjà
validées par l'utilisateur ne changent pas (minutages du menu de piste…). Vérifier fluidité, vitesse et mémoire sur
la CI avant tout pkg. Le nom tapé n'apparaît jamais dans les journaux.

## 3. Hors périmètre de cette version

- Regrouper le **Mixer** (déplacer ses pistes) : phase 2, après un essai du chemin « Move left / Move right » sur le
  FL de l'utilisateur. Cette version colore et montre le classement du Mixer.
- Organiser la **Playlist** : l'API ne dit pas ce que contient chaque piste. Message « Ouvre le Channel rack ou le
  Mixer ». Piste pour plus tard (idée de l'utilisateur) : quand tout est dans un seul pattern, « Split by channel »
  (menu Patterns de la barre des menus de macOS, si FL l'y montre) donne un pattern par canal, puis les pistes de la
  Playlist peuvent suivre le classement des canaux. À vérifier sur le FL de l'utilisateur.
- **Détecteur de carte son** (nouvelle demande) : quand une carte son est branchée, une macro la choisit en entrée et
  en sortie dans FL. Conçu à part, après l'étape 1.
- Les 10 couleurs récentes **de FL** : remplacées par « Couleurs du projet » (lues par le lien) et « Récentes »
  (choisies dans FL Shortcut).

## 4. Le lien avec FL étendu

Compatible avec le protocole v2 (PROTOCOL.md) : rien ne change pour les actions 1 à 40.

- **Commande avec données** = action **41** « data ». Annoncée dans le masque de capacités : un script ancien ne
  l'annonce pas : le bloc « Nom et couleur » reste dans la palette et s'arrête avec « mets à jour le lien avec FL :
  redémarre FL » (le cacher demanderait de suivre l'état du lien dans le créateur ; plus tard si utile).
- **Données appli → FL** : CC **96** = début (vide le tampon), puis CC **97** = unités de 7 bits (empaquetage
  7 bits comme en SysEx : 7 octets → 8 unités). 600 unités au plus, sinon refus. Puis la trame authentifiée
  habituelle (CC 104–111) avec l'action 41. Le MAC couvre les données :
  `HMAC-SHA256(clé, nonce ‖ seq ‖ 41 ‖ unités)`. Tampon vidé après chaque trame, acceptée ou non.
- **Opérations** (1er octet des données) :

| Code | Nom | Données | Effet |
|---|---|---|---|
| 1 | `nameColorSelected` | drapeaux (nom, couleur), RVB 3 octets, longueur, nom UTF-8 ≤ 64 caractères | page devant = Mixer, Channel rack ou Playlist ; exactement un élément sélectionné ; pose nom et/ou couleur |
| 2 | `list` | genre (1 canaux, 2 Mixer) | réponse : voir plus bas |
| 3 | `audition` | canal (2 octets), note, vélocité (0 = arrêt) | `channels.midiNoteOn` |
| 4 | `setColors` | genre, puis (index 2 octets, RVB 3 octets) × n, n ≤ 64 | pose plusieurs couleurs d'un coup |
| 5 | `selectOne` | genre, index | sélectionne cet élément seul (`selectOneChannel`, `setActiveTrack`) |
| 6 | `playSolo` | canal (2 octets) | 1er appel : mémorise sourdines, mode et position ; puis ce canal seul audible (les autres en sourdine), mode pattern, position 0, lecture |
| 7 | `stopRestore` | — | arrêt de la lecture ; sourdines, mode et position remis comme mémorisés (sans effet si rien n'est mémorisé) |
| 8 | `gradientSelected` | First RVB, Last RVB | page devant = Mixer, Channel rack ou Playlist ; au moins 2 éléments sélectionnés ; couleurs en ligne droite (rouge, vert, bleu) de First (premier sélectionné) à Last (dernier) |

- Les opérations 2 à 8 arrivent avec le script **v5**, annoncées par le bit de capacité **42** (le bit 41 seul =
  opération 1 seulement).
- **Raisons** en plus : 4 FL joue (opération 6), 7 « il faut au moins 2 éléments sélectionnés » (opération 8).
- `list` est paginée : `[2, genre, début]` → réponse `[genre, total, début, n, entrées…]`, 16 entrées au plus
  (noms coupés à 24 octets) ; l'appli redemande la suite.

- **Réponses FL → appli** : CC **112** = début (valeur = code de l'opération), CC **113** = unités de 7 bits
  (600 au plus), CC **114** = fin, suivie de 4 CC **115** portant un MAC de 28 bits
  `HMAC(clé, nonce ‖ seq de la commande (3) ‖ code ‖ unités)` : la réponse est liée à sa commande (pas de rejeu).
  Envoyée juste avant l'accusé 41. L'appli ignore toute réponse dont le MAC est faux ou qui ne suit pas sa commande.
- **Raison d'un refus** : CC **116** juste avant l'accusé 0 : 1 page non prise en charge, 2 rien de sélectionné,
  3 plusieurs éléments sélectionnés, 4 FL joue, 5 données invalides.
- **Liste des canaux** (réponse de `list` 1) : en-tête `[1, total (2), début (2), n, filtré]` puis pour chaque canal,
  dans l'ordre affiché : type (`getChannelType`, 0 si absent), piste du Mixer (`getTargetFxTrack`, 2 octets), couleur
  RVB (`utils.ColorToRGB`), longueur et nom UTF-8 coupé à 24 octets (pour l'aperçu seulement, jamais journalisé).
  « filtré » = 1 si le Channel rack affiche un groupe (le nombre affiché diffère du nombre global).
- **Liste du Mixer** (réponse de `list` 2) : même en-tête, puis pour chaque piste (master compris) : couleur RVB,
  longueur et nom coupé à 24 octets.
- Débit : 20 trames/s au plus, comme avant ; `setColors` regroupe les couleurs pour rester dessous.
- Le script FL passe à `SCRIPT_VERSION = 4` ; l'appli le met à jour avec la même clé (`updateInstalledIfNeeded`) et
  demande de le recharger dans FL une fois.

## 5. Bloc « Nom et couleur »

- Rubrique FL Studio de la palette. Réglages : **Nom** (texte, 64 caractères au plus, sans caractère de contrôle),
  **Couleur** (palette ci-dessous, ou « Ne pas changer »). Au moins l'un des deux, sinon le bloc est invalide.
- Exécution : opération 1 par le lien. Refus → la macro s'arrête avec un message clair : « Sélectionne une seule
  piste » (2 ou 3), « Ouvre le Mixer, le Channel rack ou la Playlist » (1). Sans lien avec FL → « Ce bloc demande le
  lien avec FL ».
- Ligne du bloc : « Nom et couleur · Kick ● ». Journal : `nameColor`, jamais le nom.
- Format JSON : `{"type":"nameColor","name":"Kick","color":"E0453A"}` (champs facultatifs) ; validé à l'import comme
  les autres blocs (longueur, caractères, hex de 6 chiffres).

### Dégradé (fade) et icône

- Réglage **Couleur** : « Une couleur » ou « Dégradé ». Dégradé : cases First et Last (chacune ouvre la fenêtre de
  couleur), aperçu du dégradé, ▶ ◀▶ ◀ comme dans FL. Exécution : opération 8 ; refus 7 → « Sélectionne au moins
  2 pistes pour un dégradé ». Le dégradé ne change pas le nom (comme dans FL) : Nom et Dégradé s'excluent.
- JSON : `{"type":"nameColor","color":"F2A0D8","fade":"C02890"}` (`fade` = Last ; demande `color`, refuse `name`).
- **Icône** (facultative) : grille des icônes de FL dans FL Shortcut, voir §6 bis. JSON `"icon":"c-r"` (colonne et
  rangée de la grille de FL, 0-indexées), journal `nameColor` sans détail.

### Palette (réutilisée par Organiser)

- Grille des couleurs de la fenêtre de couleur de FL, champ « # » (6 chiffres hexadécimaux), rangée « Couleurs du
  projet » (couleurs déjà posées, lues par `list` à l'ouverture de la palette quand le lien est là), rangée
  « Récentes » (10 dernières choisies dans FL Shortcut, gardées dans les préférences).
- Relevé sur les vidéos de l'utilisateur (fenêtre « Color selector » de FL) : roue à 16 secteurs (rouge en haut) et
  5 anneaux autour d'un disque gris (3 anneaux de couleurs relevées pixel à pixel, 2 anneaux sombres), curseur de
  luminosité, cases 0 à 9, « #RRGGBB », Hue (0–359), Saturation et Luminance (0–240), Red / Green / Blue, Reset,
  Accept. Recopiée dans `FLColorSelector.swift` ; les cases 0 à 9 sont les 10 dernières couleurs de FL Shortcut.

## 6. Organiser

### Lancement

- Nouveau bloc de macro « Organiser la page ouverte » (`BlockType.organize`, rubrique FL Studio) et modèle de macro
  « Organiser » dans la bibliothèque : l'utilisateur ne choisit que le raccourci, comme pour les autres macros (pas de
  nouveau genre de raccourci, donc rien à migrer). Le bloc ouvre l'Organiser et se termine aussitôt ; la suite se
  passe dans sa fenêtre. Aussi un élément « Organiser la page ouverte… » dans le menu de la barre des menus.
- Page devant (CC 117) : Channel rack → organiser ; Mixer → classer et colorer ; autre → message. FL qui joue →
  « Appuie sur Stop d'abord ». Script trop ancien → « Mets à jour le script ».
- Groupe filtré dans le Channel rack → « Affiche le groupe All » (les ⌥↑/⌥↓ suivent le groupe affiché).

### Écoute

1. Autorisation macOS « Audio système uniquement » (`NSAudioCaptureUsageDescription`), demandée la première fois.
   Refusée → message avec le bouton qui ouvre Réglages Système.
2. Capture du **seul processus de FL** : `CATapDescription(stereoMixdownOfProcesses:)` (pid → objet audio par
   `kAudioHardwarePropertyTranslatePIDToProcessObject`), `muteBehavior = .mutedWhenTapped` (l'utilisateur n'entend
   rien), périphérique agrégé privé, IOProc qui copie dans un tampon circulaire. Créé au début, détruit à la fin.
3. **Ta partie d'abord** (demande de l'utilisateur : « écouter directement ce que la personne a fait », un synthé
   peut servir de basse) : pour chaque canal (sauf automation et layer), opération 6 : ce canal seul en solo, mode
   pattern, lecture du pattern en cours depuis son début ; capture jusqu'à la fin du pattern, 4 s au plus ; puis
   opération 7 (arrêt). Le classement porte sur ce que tu as joué (hauteur médiane de ta partie, rythme…).
4. **Notes d'essai en secours** : si le canal reste silencieux (aucune note dans ce pattern), note grave C3
   (MIDI 48) 300 ms puis C5 (MIDI 60) 300 ms (FPC : ses deux premiers pads), puis attente que le son retombe sous
   −50 dBFS (1,2 s au plus). Le résultat est marqué « testé avec des notes d'essai » (confiance plus basse). Chaque
   note est coupée par l'opération 3 avec vélocité 0.
5. En fin d'écoute, et en cas d'arrêt (Échap, erreur, lien perdu) : opération 7, notes coupées ; solos, mode
   (pattern ou song) et position de lecture remis comme au départ.
6. Fenêtre de progression (style Liquid Glass) : « Écoute 12 / 30 », Échap pour arrêter.

### Classement

- **IA de macOS** : `SNClassifySoundRequest(classifierIdentifier: .version1)` (SoundAnalysis, sur le Mac, sans
  internet) sur chaque note. Table « étiquette → famille » dans le code (drum, bass_drum, snare_drum, hi_hat,
  cymbal… → Drums ; bass_guitar… → Basse ; piano, synthesizer, guitar, strings… → Mélodies ; singing, speech,
  choir… → Voix). Un test de la CI vérifie que chaque étiquette de la table existe dans `knownClassifications`.
- **Mesures du son** (Accelerate) : attaque et chute (temps jusqu'à −20 dB après le pic), hauteur et sa stabilité
  (autocorrélation), part d'énergie sous 200 Hz sur la note grave, bruit (platitude du spectre).
- **Fusion, dans l'ordre** :
  1. silence → À vérifier ;
  2. voix reconnue par l'IA → Voix ;
  3. son long, grave (fondamentale < 130 Hz) et stable → Basse (808 compris, même si l'IA dit « drum ») ;
  4. drums reconnus par l'IA, ou son court (< 250 ms) sans hauteur stable → Drums ;
  5. instrument reconnu, ou son tenu avec hauteur stable → Mélodies (Basse si grave, règle 3) ;
  6. son long sans hauteur stable (bruit, montée, impact) → FX ;
  7. confiance trop basse → À vérifier.
- **Mixer** : chaque piste prend la famille majoritaire des canaux qui y sont reliés ; aucune → « À vérifier ».

### Aperçu

- Fenêtre « Organiser le Channel rack » : familles dans l'ordre Drums, Basse, Mélodies, Voix, FX, À vérifier ;
  chaque son avec son nom actuel et sa famille en pastille colorée ; un clic sur la pastille change la famille ;
  couleur de chaque famille réglable (palette de la partie 5, réglage gardé). Boutons « Appliquer » et « Annuler ».
- Pour chaque famille : **une couleur ou un dégradé** (First → Last réparti sur les sons de la famille, dans leur
  ordre final) et **une icône** (grille de §6 bis, « aucune » par défaut). Réglages gardés dans les préférences
  (`organize.families`, JSON : couleur, fade, icône par famille). Valeurs de départ : Drums E0453A, Basse 8E5BE8,
  Mélodies 3FA7E0, Voix F2A93B, FX 4FC48E, À vérifier 8A8F98 ; aucune icône.

### Application

1. Instantané de l'ordre et des couleurs d'origine.
2. Couleurs : opération 4 (par paquets de 64).
3. Ordre (Channel rack) : le plan de déplacements est calculé d'avance (tri stable par famille, en gardant l'ordre
   d'origine dans chaque famille ; au plus n × (n − 1) / 2 pas) ; pour chaque canal à déplacer : opération 5 puis
   ⌥↑ autant de fois que nécessaire, envoyés à FL seul, 15 ms entre deux touches, Channel rack devant à chaque pas
   (sinon arrêt propre). Vérification finale par `list` : la famille de chaque position doit correspondre (couleurs).
4. « Revenir comme avant » (visible jusqu'à la prochaine action) : plan inverse, couleurs d'origine.

### Erreurs

Lien perdu, FL fermé, page changée, Échap : arrêt propre (notes coupées, capture détruite, rien de plus envoyé),
message ; ce qui a déjà été appliqué peut être annulé par « Revenir comme avant ».

## 6 bis. Icônes

- **Grille dans FL Shortcut** : même disposition que celle de FL (14 colonnes, mêmes titres, mêmes cases vides),
  dessinée avec des symboles de macOS (SF Symbols) proches de chaque icône de FL (pas les dessins de FL, qui
  appartiennent à Image-Line). Une case = `FLIcon(column:row:)`. La case Reset (0, 0) = « aucune icône ».
- **Pose dans FL** (aucune lecture de l'écran) : élément sélectionné (Organiser : opération 5 d'abord) → F2 → la
  fenêtre « Rename, color and icon » de FL s'ouvre (nouvelle fenêtre, liste des fenêtres) → clic sur le bouton de
  l'icône de cette fenêtre, **appris une fois** (« clique sur le bouton de l'icône, à gauche du nom » : relevé le 16/10, position gardée par rapport
  à la fenêtre, comme les autres clics appris) → la grille de FL s'ouvre (nouvelle fenêtre) → clic au centre de la
  case `(colonne + 0,5) × L / 14`, `titre + (rangée + 0,5) × L / 14`, avec `titre = H − 15 × L / 14` (L, H = taille de
  la fenêtre de la grille) → la grille se ferme → Entrée ferme la fenêtre du nom sans le changer.
- **À vérifier sur le FL de l'utilisateur** avant d'en dépendre : F2 sur le Channel rack et le Mixer, le bouton de
  l'icône dans la fenêtre du nom. Jusque-là l'icône est facultative : si une étape ne répond pas, la couleur reste
  posée et un message dit que l'icône n'a pas pu être mise.

## 7. Mémoire et vitesse

- Rien au repos : capture, modèle de SoundAnalysis et fenêtre créés au lancement d'Organiser, libérés à la fin
  (vérifié par la CI comme le créateur : objets vivants = 0).
- Cible : écoute ≈ 3 s par canal (ta partie, 4 s au plus ; 0,8 s avec les notes d'essai) ; classement < 50 ms par canal ; couleurs < 0,2 s ; déplacements ≈ 15 ms par pas.
- Tableau mémoire de la CI : nouvelle colonne « Organiser » (pic pendant le classement, puis après).

## 8. Tests

- Swift : empaquetage 7 bits et MAC avec données (vecteur commun avec le script) ; lecture des réponses et de leur
  MAC ; validation du bloc et de son JSON ; plan de déplacements (tri stable, nombre de pas, plan inverse) ; fusion
  du classement sur des mesures données ; table d'étiquettes ⊂ `knownClassifications`.
- Sons de synthèse (CI macOS) : kick, caisse claire, charleston, 808, basse, lead, nappe, montée de bruit, voix de
  synthèse (formants) ; le classement complet doit trouver la bonne famille pour au moins 8 sur 9, et le résultat de
  chacun est affiché dans le résumé de la CI.
- Script Python (job existant) : opérations 1 à 5 avec un faux FL (0, 1, 2 éléments sélectionnés ; page non prise en
  charge ; données trop longues ; MAC faux ; débit) ; vecteur commun.
- FL simulé : Channel rack avec ⌥↑/⌥↓ ; essai CI d'un plan de déplacements appliqué au clavier puis vérifié.

## 9. Livraison, dans l'ordre

1. Lien étendu (script v4 + appli) et bloc « Nom et couleur » avec une palette provisoire : champ « # » et
   « Récentes » seulement, la grille de FL arrivant à l'étape 2.
2. Palette de FL (dès la capture de l'utilisateur), « Couleurs du projet », « Récentes ».
3. Lien v5 (opérations 2 à 8, réponses signées) et dégradé dans le bloc « Nom et couleur ».
4. Organiser : écoute et classement, aperçu (couleur ou dégradé par famille), couleurs (Channel rack et Mixer),
   regroupement du Channel rack et « Revenir comme avant ».
5. Icônes : grille dans FL Shortcut (bloc et familles), pose dans FL par F2 (à vérifier sur le FL de l'utilisateur).
6. Phase 2 (après essai sur le FL de l'utilisateur) : regroupement du Mixer.

Chaque étape : CI verte (tests, essais, mémoire), puis pkg.
