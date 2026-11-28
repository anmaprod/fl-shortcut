# Communauté : suivre des créateurs, page d'une personne, ajouts et étoiles

Validé par le propriétaire le 11/11 (« fait la communauté je valide »), en trois parties : écrans, serveur, app.
Demande d'origine : « rendre la communauté encore mieux, encore plus belle visuellement et beaucoup plus intuitive…
suivre des gens par leur travail de macro… les pages des gens… montre leur travail… pas trop d'infos… simple et bien »,
puis « des notes pour chaque macro… l'ordinateur calcule une moyenne tout seul et met en avant les gens qui ont les
meilleures moyennes selon le nombre de téléchargements ». Maquette : artefact privé `1EFC8zLVn5ATRWAnQMBZrB`, planche
« Communaute » (écran B · Vitrine et page d'une personne).

Mac ET Windows, la même chose. Style suisse des trois thèmes (Noir, Papier, Orange). Tout texte a son anglais.

## 1. Écrans

### Accueil « vitrine »
- En haut : la recherche, puis les onglets **Pour toi** · **Abonnements** (point rouge s'il y a du nouveau) ·
  **Les plus ajoutées** · **Les miens**.
- **Pour toi** :
  1. « De tes abonnements » : les 3 derniers partages des gens suivis (rangée cachée si on ne suit personne) ;
  2. « Créateurs à suivre » : 5 ronds (photo ou initiale), pseudo, bouton Suivre ;
  3. « Les plus ajoutées » : les 3 premières, numérotées 01, 02, 03 ;
  4. chaque rangée a « Tout voir » (ouvre l'onglet qui va avec ; « Créateurs à suivre » n'en a pas) ;
  5. dessous, les nouveautés en cartes, comme aujourd'hui.
- **Abonnements** : tous les partages des gens suivis, les plus récents d'abord. Vide : « Tu ne suis personne. ».
- **Les plus ajoutées** : partages par nombre d'ajouts, à égalité par la note du créateur.
- **Les miens** : comme aujourd'hui.
- Chaque carte : « ★ 4,6 · Ajoutée 312 fois » (pas d'étoile sans note ; « Ajoutée 0 fois » jamais écrit : rien).
- Le pseudo et la photo mènent PARTOUT à la page de la personne (cartes, fiche, rangées).

### Page d'une personne
- Elle prend la place de la liste, avec ← pour revenir.
- Titre : son pseudo en grand (minuscules + point carré, comme les titres de pages) ; à droite **Suivre** (bouton
  principal) ou **Abonné** (bordé ; un clic arrête de suivre). Jamais pour soi-même.
- Dessous : sa photo en grand (ou son initiale) et « N abonnés ». Rien d'autre (pas de bio, pas de date).
- « Son travail » : ses partages en cartes, tri **Les plus ajoutées** / **Les plus récentes**.

### Noter
- Dans la fiche d'un partage (page posée au-dessus) : ligne « Ta note » avec 5 étoiles à cliquer (pleines à l'encre,
  vides en gris), seulement si on l'a ajouté et que ce n'est pas le sien. Un nouveau clic change la note.
- Juste après « Ajouter à mes macros » (ou « Utiliser ces raccourcis ») : le message en bas propose « Noter », qui
  ouvre la fiche.

### Point rouge
- Sur « Communauté » dans la barre de gauche et sur l'onglet « Abonnements » quand un partage d'une personne suivie est
  plus récent que la dernière ouverture de l'onglet « Abonnements » (heure gardée sur l'ordinateur, réglage local).
- Calculé sur l'ordinateur : au lancement (compte connecté), à l'ouverture de la Communauté, puis toutes les 30 min.

## 2. Serveur : `supabase/communaute-suivre.sql` (étape 12 du README, après schema.sql et profil.sql)

Peut être recollé sans risque. Essais dans `supabase/tests/communaute-suivre.sql` (lancés par `run.sh`).

- `follows (follower_id, followee_id, created_at)`, clé sur les deux, suppression en cascade avec le profil.
  Règles : on ne lit que SES abonnements ; on s'abonne et se désabonne en son nom ; jamais à soi-même.
- `profiles.follower_count` tenu par le serveur (déclencheur), jamais modifiable depuis l'app. On voit seulement le
  nombre d'abonnés des autres, jamais la liste.
- `adds (share_id, user_id, created_at)` : un ajout par personne et par partage, jamais pour son propre partage ;
  `shares.add_count` tenu par le serveur. Appel `record_add(p_share)` : rien si déjà fait ou si c'est le sien ; rend le
  nombre d'ajouts.
- `ratings (share_id, user_id, stars 1–5, updated_at)` : seulement après un ajout, jamais le sien, une note par
  personne, modifiable. `shares.rating_sum` et `shares.rating_count` tenus par le serveur. Appel
  `rate_share(p_share, p_stars)`. On ne lit que ses propres ajouts et notes.
- Note d'un créateur : moyenne bayésienne de TOUTES les notes de ses partages, `(3 × 3,5 + somme) / (3 + nombre)` :
  1 note à 5 ★ ≈ 3,9 ; 1 000 notes à 4 ★ = 4,0. Sert à « Créateurs à suivre » et à départager « Les plus ajoutées ».
- Appels : `followed_shares(p_limit)` (partages des gens suivis), `creators_to_follow(p_limit)` (5 créateurs ayant
  publié, pas soi ni ceux qu'on suit, meilleure note d'abord puis plus d'ajouts), `most_added(p_kind, p_limit)`.
  Les partages rendus gardent la forme de la table (l'app y joint le pseudo comme aujourd'hui).
- Anti-spam : 200 abonnements et 200 notes par heure et par compte au plus.
- Tout est réservé aux comptes connectés (rôle « authenticated »), comme le reste de la Communauté.

## 3. App (Mac : CommunityView/Store/Client + barre de gauche ; Windows : CommunityPage.cs, Community.cs, MainShell)

- Tant que le fichier SQL n'est pas collé, l'app garde la Communauté d'aujourd'hui, sans étoiles ni Suivre, sans
  erreur : la colonne manquante est reconnue et la lecture repart avec les anciennes colonnes.
- Photos : gardées sur l'ordinateur une fois lues (moins d'envois du serveur), relues si elles changent.
- Essais : lecture des réponses du serveur (nouvelles colonnes, repli), texte « ★ 4,6 · Ajoutée 312 fois », point rouge,
  note bayésienne recalculée par l'app pour l'affichage si besoin.
- Photos de la CI : vitrine, page d'une personne, fiche avec la note (Mac et Windows, sons d'exemple).
