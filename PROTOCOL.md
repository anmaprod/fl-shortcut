# Protocole FL Shortcut ↔ script FL Studio (v2)

Contrat unique entre l'appli (Mac `Sources/FLShortcut`, Windows à venir) et le script `Resources/device_FLShortcut.py`.
Toute modification de ce fichier doit être répercutée des deux côtés. Origine des exigences : `audit/01` (SEC-01/02/05/10), `audit/02` (REL-xx), `audit/04` (compatibilité).

## 1. Transport

- Messages **Control Change uniquement** (pas de SysEx : bugs FL 26.1.x, audit 04).
- **Appli → FL** : canal MIDI 16 (statut `0xBF`), sur la source virtuelle « FL Shortcut » créée par l'appli.
- **FL → Appli** : `device.midiOutMsg` sur le canal 16, vers la destination virtuelle « FL Shortcut » créée par l'appli. Dans *MIDI Settings*, l'entrée et la sortie « FL Shortcut » doivent porter le **même numéro de port** (l'appli guide l'utilisateur).
- uniqueID CoreMIDI : **aléatoire par installation** (stocké dans les préférences), jamais une constante (SEC-02).

## 2. Secret partagé

- À l'installation du script, l'appli génère une clé aléatoire de **16 octets** (générateur cryptographique) et l'écrit dans le script installé : le texte `__FLSHORTCUT_KEY__` n'apparaît **qu'une seule fois**, sur la ligne `KEY_HEX = "__FLSHORTCUT_KEY__"`, et doit être remplacé par **32 caractères hexadécimaux minuscules**. Toute autre valeur fait refuser toutes les commandes.
- La clé est aussi stockée côté appli (Mac : Trousseau de préférence, sinon fichier 0600 dans Application Support).
- Le script ne lit **aucun fichier** : la clé est une constante du script.
- Réinstaller le script = nouvelle clé.

## 3. Annonce du script (FL → appli)

Envoyée à `OnInit`, en réponse à un PING, et chaque fois que le nonce change. Suite de CC, dans cet ordre :

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
- **CC 119** = accusé d'exécution : valeur = id de l'action exécutée avec succès, ou 0 si la trame a été rejetée (MAC faux, rejeu, trame mélangée, débit dépassé, id inconnu, action indisponible) ou si l'action n'a pas pu s'exécuter (aucune piste ou aucun canal sélectionné, erreur FL).
- Les PING trop fréquents (plus de 4 par seconde) sont ignorés.

## 4. Commande authentifiée (appli → FL)

L'appli envoie une trame de 8 CC, dans cet ordre :

| CC | Valeur |
|---|---|
| 104, 105, 106 | numéro de séquence sur 21 bits (poids fort d'abord) |
| 107 | id d'action (1–42, voir §6) |
| 108–111 | MAC sur 28 bits (poids fort d'abord) |

**Calcul du MAC** : `HMAC-SHA256(clé, nonce[4] ‖ seq_hi ‖ seq_mid ‖ seq_lo ‖ action)`. On prend les 4 premiers octets en big-endian, on décale de 4 bits vers la droite (28 bits), puis on découpe en 4 × 7 bits.

**Règles côté script** (toutes obligatoires) :
- Rejeter si le MAC est faux ou si `seq <= dernier_seq` (anti-rejeu).
- Rejeter les trames incomplètes ou mélangées : un CC 104 réinitialise la trame en cours.
- Limiter le débit à **20 actions/s maximum**.
- Seuls les ids de la table §6 sont acceptés.
- Les CC/canaux inconnus ne sont **pas** marqués `handled`, sauf ceux du protocole.

**PING** : appli → FL, CC 103 = 1, non authentifié. Le script génère alors un **nouveau nonce**, remet `dernier_seq` à 0 et renvoie HELLO. L'appli fait un PING au lancement et quand elle n'a plus de battement depuis 6 s. Puis elle numérote ses trames à partir de 1.

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

**Fenêtre de contexte** : le filtrage « Partout / Piano Roll / Playlist / Mixer » est fait par l'appli, à partir du CC 117. Le script n'a pas à le connaître.
