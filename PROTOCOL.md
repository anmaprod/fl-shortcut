# Protocole FL Shortcuts ↔ script FL Studio (v2)

Contrat unique entre l'appli (Mac `Sources/FLShortcut`, Windows à venir) et le script `Resources/device_FLShortcut.py`.
Toute modification de ce fichier doit être répercutée des deux côtés. Origine des exigences : `audit/01` (SEC-01/02/05/10), `audit/02` (REL-xx), `audit/04` (compatibilité).

## 1. Transport

- Messages **Control Change uniquement** (pas de SysEx : bugs FL 26.1.x, audit 04).
- **Appli → FL** : canal MIDI 16 (statut `0xBF`), sur la source virtuelle « FL Shortcuts Link » créée par l'appli
  (« FL Shortcuts » avant : le nouveau nom fait voir à FL un appareil neuf, sans ancien réglage gardé).
- **FL → Appli** : `device.midiOutMsg` sur le canal 16, vers la destination virtuelle « FL Shortcuts Link » créée par l'appli. L'entrée et la sortie doivent porter le **même numéro de port** et le Controller type « FL Shortcuts ».
- **Liaison automatique** : l'en-tête du script (`# supportedDevices=FL Shortcuts Link,FL Shortcuts`) fait relier le script par FL à l'appareil qu'il trouve en démarrant. L'appli garde donc ses ports dès que le lien est installé (sans aucun trafic), pour que FL les trouve à son lancement ; elle n'explique le réglage à la main que si FL ne répond pas.
- uniqueID CoreMIDI : **aléatoire par installation** (stocké dans les préférences), jamais une constante (SEC-02).

## 2. Secret partagé

- À l'installation du script, l'appli génère une clé aléatoire de **16 octets** (générateur cryptographique) et l'écrit dans le script installé : le texte `__FLSHORTCUT_KEY__` n'apparaît **qu'une seule fois**, sur la ligne `KEY_HEX = "__FLSHORTCUT_KEY__"`, et doit être remplacé par **32 caractères hexadécimaux minuscules**. Toute autre valeur fait refuser toutes les commandes.
- La clé est aussi stockée côté appli (Mac : Trousseau de préférence, sinon fichier 0600 dans Application Support).
- Le script ne lit **aucun fichier** : la clé est une constante du script.
- Réinstaller le script = nouvelle clé.
- Clé présente mais script disparu de FL (`Settings/Hardware/FL Shortcuts/device_FLShortcut.py` absent : FL ne propose
  pas le Controller type « FL Shortcuts ») : l'appli le réécrit **avec la même clé**, au lancement et à l'ouverture de
  l'Organiser, dans le dossier enregistré ou celui de FL par défaut ; jamais par-dessus un script modifié.

## 3. Annonce du script (FL → appli)

Envoyée en réponse à un PING (le script démarre **endormi** et n'envoie rien avant), et chaque fois que le nonce change. Suite de CC, dans cet ordre :

| CC | Valeur |
|---|---|
| 120 | 1 = HELLO (début de trame) |
| 121–124 | nonce de session, 4 × 7 bits, aléatoire (`random.randrange(128)`) |
| 125 | version d'API FL (`general.getVersion()`, plafonnée à 127) |
| 126 | version du protocole (= 2) |
| 90–95 | masque de capacités : 6 × 7 bits = 42 bits. Le CC `90+k` porte les bits `7k…7k+6`. Le bit `j` de sa valeur correspond à l'action `id = 7k + j + 1` (ex. action 1 = bit 0 du CC 90, action 8 = bit 0 du CC 91, action 38 = bit 2 du CC 95). Si la clé n'est pas installée, le masque vaut 0 |
| 120 | 127 = fin de trame |

Autres messages FL → appli :
- **CC 117** = fenêtre FL active (0 Mixer, 1 Channel Rack, 2 Playlist, 3 Piano Roll, 4 Browser, 5 plugin, 127 inconnue), envoyé à chaque changement (depuis `OnRefresh`/`OnIdle`, au plus toutes les 100 ms).
- **CC 118** = battement de cœur (valeur 0/1 alternée) toutes les ~2 s.
- **CC 120 = 64** (script v8), une seule fois au démarrage, non authentifié : FL a posé le script sur une autre entrée
  que « FL Shortcuts Link » (`device.getName()`, API 7 : Controller type choisi sur la ligne d'une carte son ou d'un
  clavier). Les messages de l'appli n'arrivent alors jamais au script ; il le dit aussi dans la barre d'aide de FL.
  L'appli ne le reçoit que si sa sortie partage le Port de cette entrée ; elle l'affiche dans l'Organiser (attente
  de FL) jusqu'au prochain HELLO. Simple indication à l'écran : rien d'autre n'en dépend.
- **CC 119** = accusé d'exécution : valeur = id de l'action exécutée avec succès, ou 0 si la trame a été rejetée (MAC faux, rejeu, trame mélangée, débit dépassé, id inconnu, action indisponible) ou si l'action n'a pas pu s'exécuter (aucune piste ou aucun canal sélectionné, erreur FL).
- Les PING trop fréquents (plus de 4 par seconde) sont ignorés.

## 4. Commande authentifiée (appli → FL)

L'appli envoie une trame de 8 CC, dans cet ordre :

| CC | Valeur |
|---|---|
| 104, 105, 106 | numéro de séquence sur 21 bits (poids fort d'abord) |
| 107 | id d'action (1–42 : table §6, et 41 = commande avec données, §7) |
| 108–111 | MAC sur 28 bits (poids fort d'abord) |

**Calcul du MAC** : `HMAC-SHA256(clé, nonce[4] ‖ seq_hi ‖ seq_mid ‖ seq_lo ‖ action)`. On prend les 4 premiers octets en big-endian, on décale de 4 bits vers la droite (28 bits), puis on découpe en 4 × 7 bits.

**Règles côté script** (toutes obligatoires) :
- Rejeter si le MAC est faux ou si `seq <= dernier_seq` (anti-rejeu).
- Rejeter les trames incomplètes ou mélangées : un CC 104 réinitialise la trame en cours.
- Limiter le débit à **20 actions/s maximum**.
- Seuls les ids de la table §6 sont acceptés, plus l'action 41 (commande avec données, §7).
- Les CC/canaux inconnus ne sont **pas** marqués `handled`, sauf ceux du protocole.

**PING** : appli → FL, CC 103, non authentifié. Le script se réveille, génère un **nouveau nonce**, remet `dernier_seq` à 0 et renvoie HELLO.
- `1` : réveil durable (mode MIDI complet) : battements et fenêtre active comme avant.
- `2` : réveil bref (macros) : le script se rendort `AWAKE_FOR` = 8 s après le dernier message reçu.

**Sommeil** : au chargement et après un réveil bref, `OnIdle` et `OnRefresh` s'arrêtent à leur première ligne, rien n'est envoyé, et seules les PING sont écoutées (les trames sont ignorées). FL ne fait donc aucun travail pour FL Shortcuts entre deux macros. L'appli fait un PING au lancement et quand elle n'a plus de battement depuis 6 s. Puis elle numérote ses trames à partir de 1.

**Vecteur de test** (à reproduire des deux côtés dans les tests) :

```
clé    = 000102030405060708090a0b0c0d0e0f
nonce  = [17, 42, 99, 5]
seq    = 300
action = 12
message = [17, 42, 99, 5, 0, 2, 44, 12]
MAC    = [87, 59, 101, 12]
```

HMAC côté script : `import hmac, hashlib` s'ils existent, **sinon** un SHA-256/HMAC en Python pur embarqué dans le script (l'interpréteur de FL peut être réduit).

## 5. Statut affiché par l'appli

- **Relié** : HELLO reçu et battement depuis moins de 6 s.
- **Lien inactif** : FL est au premier plan mais aucun HELLO ou battement. Dans ce cas, l'appli **ne capture pas** les raccourcis « Action dans FL » : la touche passe telle quelle à FL (REL : ne pas avaler sans effet).
- **FL fermé** : aucun processus FL.

## 6. Table des actions

Ids figés : ne jamais renuméroter, seulement ajouter. Fonctions API et versions minimales : voir `audit/04_compatibilite_versions.md`.

| id | clé | libellé |
|---|---|---|
| 1 | play | Lecture / Pause |
| 2 | stop | Stop |
| 3 | rec | Lancer le REC |
| 4 | metro | Métronome |
| 5 | count | Décompte |
| 6 | loop | Enregistrement en boucle |
| 7 | wait | Attendre une note |
| 8 | marker | Poser un marqueur |
| 9 | arm | Armer la piste (Mixer sélectionnée) |
| 10 | tap | Tap tempo |
| 11 | newpat | Nouveau pattern + Piano Roll |
| 12 | clone | Cloner le pattern |
| 13 | pnext | Pattern suivant |
| 14 | pprev | Pattern précédent |
| 15 | chnext | Instrument suivant |
| 16 | chprev | Instrument précédent |
| 17 | snap | Grille suivante |
| 18 | quant | Quantize rapide |
| 19 | presetnext | Preset suivant |
| 20 | presetprev | Preset précédent |
| 21 | mute | Mute piste Mixer sélectionnée |
| 22 | solo | Solo piste Mixer sélectionnée |
| 23 | unsolo | Retirer tous les solos |
| 24 | bypass | Bypass des effets de la piste (bascule) |
| 25 | mono | Master en mono (bascule) |
| 26 | trnext | Piste Mixer suivante |
| 27 | trprev | Piste Mixer précédente |
| 28 | volup | Volume piste +0,5 dB |
| 29 | voldn | Volume piste −0,5 dB |
| 30 | pl | Ouvrir la Playlist |
| 31 | cr | Ouvrir le Channel Rack |
| 32 | pr | Ouvrir le Piano Roll |
| 33 | mx | Ouvrir le Mixer |
| 34 | br | Ouvrir le Browser |
| 35 | plmx | Playlist ↔ Mixer |
| 36 | undo | Annuler |
| 37 | redo | Rétablir |
| 38 | save | Sauvegarder |
| 39 | armon | Armer la piste (si éteinte) : ne désarme jamais |
| 40 | recon | Allumer le REC (si éteint) : ne l'éteint jamais |

**Fenêtre de contexte** : le filtrage « Partout / Piano Roll / Playlist / Mixer » est fait par l'appli, à partir du CC 117. Le script n'a pas à le connaître.

## 7. Commande avec données (script v4)

Action **41**, hors de la table §6 : elle porte des données. Annoncée par le bit 41 du masque de capacités (§3) ;
un script plus ancien ne l'annonce pas, et l'appli n'envoie alors rien de tout cela.

- **Appli → FL** : CC **96** (valeur ignorée) = début, vide le tampon ; puis un CC **97** par unité de 7 bits ;
  puis la trame authentifiée habituelle (§4) avec l'action 41. **600 unités** au plus : au-delà, les données sont
  jetées et la trame est refusée. Une unité sans CC 96 est ignorée. Le tampon ne sert qu'à la trame qui le suit, et
  il est vidé à chaque trame, PING ou mise en sommeil. Endormi, le script ignore les CC 96 et 97.
- **MAC** : `HMAC-SHA256(clé, nonce[4] ‖ seq_hi ‖ seq_mid ‖ seq_lo ‖ 41 ‖ unités)`, tronqué comme au §4.
- **Empaquetage 7 bits** : les octets sont pris par groupes de 7 ; chaque groupe donne une unité d'en-tête (bit j =
  bit 7 de l'octet j du groupe), puis les 7 bits bas de chaque octet (le dernier groupe peut être plus court).
- **Opérations** (1er octet des données) :

| Opération | Données | Effet |
|---|---|---|
| op 1 : nom et couleur | drapeaux (bit 0 nom, bit 1 couleur), R, G, B, n, nom UTF-8 (n octets, 64 caractères au plus, aucun caractère de contrôle) | page devant (Mixer, Channel rack, Playlist ; Playlist : API 12) ; exactement un élément sélectionné ; pose le nom et/ou la couleur (`utils.RGBToColor`). Le nom n'apparaît dans aucun message de FL |

- **Raison d'un refus** : CC **116** envoyé juste avant l'accusé 0 (CC 119) : 1 page non prise en charge, 2 rien de
  sélectionné, 3 plusieurs éléments sélectionnés, 5 données invalides ou refusées par FL, 6 page prise en charge
  mais pas par cette version de FL (Playlist avant l'API 12). Une trame refusée avant
  exécution (MAC faux, rejeu, débit) n'a pas de raison.
- Le débit de 20 trames par seconde (§4) compte aussi ces trames.

**Vecteur de test** (mêmes valeurs des deux côtés) :

```
clé     = 000102030405060708090a0b0c0d0e0f
nonce   = [17, 42, 99, 5]
seq     = 300
données = [1, 3, 0xE0, 0x45, 0x3A, 4, 'K', 'i', 'c', 'k']      (nom « Kick », couleur E0453A)
unités  = [4, 1, 3, 96, 69, 58, 4, 75, 0, 105, 99, 107]
MAC     = [116, 112, 71, 62]
```

## 8. Organiser et dégradé (script v5, Playlist : script v6)

Opérations 2 à 12 de la commande avec données (§7), annoncées par le bit **42** du masque de capacités (le bit 41
seul = opération 1 seulement). Un script qui annonce 42 a aussi `utils.ColorToRGB` et `utils.RGBToColor` de FL.
Les opérations 9 à 12 (script v6) n'ont pas de bit à elles : un script v5 les refuse avec la raison 5 sans rien
toucher, et l'appli demande alors de redémarrer FL (le script mis à jour n'est lu qu'au lancement de FL).

- **Réponse FL → appli** (opération 2) : CC **112** = début (valeur = opération), un CC **113** par unité de 7 bits
  (empaquetage du §7, **600 unités** au plus), CC **114** = fin, puis 4 CC **115** =
  `mac28(HMAC-SHA256(clé, nonce[4] ‖ seq_hi ‖ seq_mid ‖ seq_lo de la commande ‖ opération ‖ unités))`. Envoyée juste
  avant l'accusé 41 : liée à sa commande, elle ne peut pas être rejouée pour une autre. L'appli ignore une réponse au
  MAC faux, incomplète, ou qui ne suit pas sa commande.
- Index sur 2 octets, poids fort d'abord. Genre : 1 = canaux du Channel rack, 2 = pistes du Mixer, 3 = pistes de
  la Playlist (index 0 = piste 1 de FL ; l'API de la Playlist compte depuis 1).

| Opération | Données | Effet |
|---|---|---|
| op 2 : liste | genre, début (2) | réponse `[genre, total (2), début (2), n, filtré]` puis n entrées (16 au plus). Canal : `[type, piste du Mixer (2), R, G, B, longueur, nom]` (type 0 avant l'API 19) ; piste du Mixer : `[R, G, B, longueur, nom]` ; piste de la Playlist : `[sélectionnée, R, G, B, longueur, nom]` (sélectionnée = 0 avant l'API 12). Noms UTF-8 coupés à 24 octets sans couper un caractère, pour l'aperçu seulement. filtré = 1 si le Channel rack montre un groupe |
| op 3 : note d'essai | canal (2), note, vélocité | `channels.midiNoteOn` ; vélocité 0 = arrêt |
| op 4 : couleurs | genre, n, (index (2), R, G, B) × n | n ≤ 64 ; tout est vérifié avant de poser la première couleur |
| op 5 : sélection | genre, index (2) | cet élément seul sélectionné (`selectOneChannel` API 8 ; Mixer `setActiveTrack` API 27, sinon `deselectAll` + `selectTrack`) |
| op 6 : écoute d'un canal | canal (2) | FL qui joue sans écoute en cours → raison 4, rien n'est touché. 1er appel : mémo des sourdines de tous les canaux, du mode (pattern / song) et de la position. Puis ce canal seul audible (on ne bascule que les sourdines qui doivent changer), mode pattern, position 0, lecture |
| op 7 : fin de l'écoute | — | arrêt, sourdines, mode et position remis comme au mémo, mémo vidé ; **sans effet** sans mémo (la lecture de l'utilisateur n'est jamais coupée). Aussi fait par le script quand il se rendort ou est déchargé |
| op 8 : dégradé | First R, G, B, Last R, G, B | page devant (comme l'op 1) ; tous les éléments sélectionnés, du premier au dernier ; composante k = `int(a + (b − a) × k / (n − 1) + 0,5)`, comme « Gradient color… » de FL. 0 sélectionné → raison 2, 1 seul → raison 7 |
| op 9 : page devant | — | réponse `[code]` : le code de la page devant (§3, CC 117 : 0 Mixer, 1 Channel rack, 2 Playlist, 3 Piano roll, 4 Browser, 5 plugin, 127 aucune). L'appli le demande avant d'organiser : en mode léger, rien n'est su de FL avant le réveil |
| op 10 : noms | genre (3 seulement), n, (index (2), longueur, nom UTF-8) × n | 1 ≤ n ≤ 16, nom de 1 à 32 octets ; tout est vérifié (index, longueurs, UTF-8, aucun octet en trop) avant de poser le premier nom (`playlist.setTrackName`) |
| op 11 : écoute d'une piste de la Playlist | piste (2) | comme l'op 6 pour la Playlist : FL qui joue sans écoute en cours → raison 4. 1er appel : mémo des sourdines de toutes les pistes, du mode et de la position (une écoute du Channel rack en cours est d'abord remise comme avant, et inversement). Puis cette piste seule audible, mode song, position 0, lecture. Réponse `[mesures (2)]` : longueur de la chanson (`transport.getSongLength`, API 3 ; 0 si inconnue) |
| op 12 : position | pour mille (2) | position de la chanson (`setSongPos`, 0 à 1000 ‰), seulement pendant une écoute de la Playlist (sinon raison 5). L'appli parcourt la chanson jusqu'à ce que la piste sonne |
| op 13 : mute / solo d'un canal | 0 mute ou 1 solo, index (2) | bascule le mute (`muteChannel`) ou le solo (`soloChannel`) de ce canal du Channel rack, comme son bouton ; index hors du Channel rack : raison 5. Bloc « Cliquer sur… » › Mute ou Solo d'un canal (son numéro) : ni clic ni touche ; sans le lien, les touches 1 à 0 de FL jusqu'au canal 10 seulement ; script v7 |

- **Raisons** en plus (CC 116) : 4 FL joue déjà, 7 au moins 2 éléments sélectionnés pour un dégradé. Une fonction
  de FL absente pour une opération → raison 6.
- L'API de FL ne permet ni de déplacer une piste de la Playlist, ni de lire ou poser son icône, ni de lister ses
  clips : la Playlist est colorée et renommée, jamais réordonnée.
- Les noms des sons et des pistes n'apparaissent jamais dans les messages de FL : une erreur ne donne que son type.

**Vecteur de test de la réponse** (mêmes valeurs des deux côtés) :

```
clé     = 000102030405060708090a0b0c0d0e0f
nonce   = [17, 42, 99, 5]
seq     = 300 (seq de la commande)
op      = 2
données = [1, 0, 2, 0, 0, 0, 0]                 (liste des canaux : total 2, début 0, aucune entrée)
unités  = [0, 1, 0, 2, 0, 0, 0, 0]
MAC     = [89, 95, 58, 61]
```
