# Audit 05 : UX des raccourcis clavier dans FL Remap

*Point de vue d'un chercheur UX spécialisé dans les interfaces clavier et les logiciels musicaux. Rédigé le 8 octobre 2026.*

**Question.** Comment aider de vrais utilisateurs de FL Studio, débutants comme pros, à apprendre, retenir et utiliser les raccourcis ? Que faut-il faire en priorité dans FL Remap ?

**Méthode.** Je me suis appuyé sur trois types de preuves :
- la recherche HCI publiée ;
- les guides des plateformes (Apple, Microsoft, W3C) ;
- la documentation des DAW concurrents et des fils de discussion réels (forum Image-Line 2011-2026, Ableton).

Chaque affirmation renvoie à une source listée à la fin. Quand une source n'a pas pu être lue en entier, c'est signalé. Les chiffres viennent des articles eux-mêmes, et non de citations de seconde main.

---

## 0. Ce que montre l'état actuel de FL Remap

J'ai relu `Model.swift`, `EventTap.swift`, `EditorView.swift` et `KeyNames.swift`. Les constats ci-dessous concernent directement l'UX des raccourcis.

| Constat | Pourquoi c'est un problème (preuve en §1 et §3) |
|---|---|
| Le profil par défaut utilise `⌃←` et `⌃→` (pattern précédent / suivant). | Sur macOS, ce sont les raccourcis système pour changer de Space (Mission Control). Apple déconseille aussi Control comme modificateur pour cette raison. |
| `⌃1` à `⌃5` sont utilisés pour les fenêtres. | Ils peuvent entrer en conflit avec « Passer au bureau N » de Mission Control si l'utilisateur a activé plusieurs bureaux. Il faut au minimum détecter ce cas. |
| `Tab` et `0` seuls sont remappés, et `EventTap` les avale dès que FL est au premier plan. | Ces touches ne s'écrivent plus quand on renomme une piste, qu'on tape un tempo ou qu'on joue au clavier avec « Typing keyboard to piano ». C'est exactement le cas que vise WCAG 2.1.4 (raccourcis à un seul caractère). `Tab` remplace aussi la fonction native de FL (cycler entre les fenêtres imbriquées). |
| L'interrupteur global `⌃⌥⌘F` demande 4 touches, fonctionne comme un mode verrouillé et ne donne aucun retour à l'écran, sauf l'icône de la barre des menus. | Les modes verrouillés produisent plus d'erreurs de mode que les modes maintenus (Sellen et al.). Quatre touches sont aussi difficiles à faire d'une seule main. |
| L'éditeur n'a ni recherche, ni catégories, ni détection des conflits avec macOS ou avec FL. Seuls les doublons internes sont signalés. | Reaper, Logic, Bitwig et Studio One proposent tous une recherche et vérifient ce qu'une touche fait déjà. |
| Dans `EditorView`, `Toggle("")` et `Picker("")` sont combinés à `.labelsHidden()`. | VoiceOver ne lit aucun libellé. FL Studio lui-même n'est pas utilisable avec un lecteur d'écran (Image-Line), donc l'outil qui l'entoure doit au moins être accessible. |
| Les touches sont enregistrées par position physique uniquement. | Le README reconnaît déjà qu'un profil AZERTY partagé s'affiche mal en QWERTY. Logic propose les deux modes (étiquette et position). |
| Le masque de l'event tap ne contient que `keyDown` et `keyUp`. | Sans `flagsChanged`, on ne peut pas détecter qu'un modificateur est maintenu, ce qui est nécessaire pour l'aide-mémoire « hold-to-reveal ». |

---

## 1. Les 10 principes les plus solides, avec leurs preuves

### P1. Savoir qu'un raccourci existe ne suffit pas : il faut combler activement l'écart
- **Lane, Napier, Peres et Sándor (2005)** ont interrogé 251 utilisateurs expérimentés de Word. La plupart utilisaient rarement les raccourcis et préféraient les barres d'icônes, alors qu'une seconde étude (9 sujets) montrait que les raccourcis étaient la méthode la plus rapide.
- **Tak, Westendorp et van Rooij (2013)**, dans *Interacting with Computers* (3 expériences), montrent que le manque de connaissance n'explique pas à lui seul la faible utilisation. Sous pression temporelle, les gens n'utilisent pas la méthode qu'ils savent être la plus rapide : ils se contentent de ce qui est « assez bon » (*satisficing*). En revanche, un outil d'aide à l'apprentissage augmente l'usage.
- **Cockburn, Gutwin, Scarr et Malacria (2014)**, revue publiée dans *ACM Computing Surveys*, décrivent le même phénomène : les utilisateurs restent sur des méthodes lentes. Ils proposent quatre leviers : la répétition, le passage à une modalité plus performante, l'élargissement du vocabulaire et la transformation des tâches.

**Pour FL Remap.** Une liste de raccourcis ne suffit pas. L'application doit intervenir au moment où l'utilisateur agit.

### P2. Montrer les raccourcis au moment de l'intention, pendant qu'on maintient un modificateur
- **ExposeHK (Malacria, Bailly, Harrison, Cockburn et Gutwin, CHI 2013).** Tant qu'on maintient le modificateur, les raccourcis s'affichent sur les commandes. Résultats :
  - barres d'outils (36 participants) : 94 % d'usage des raccourcis, contre 50 % avec un retour audio et 35 % avec des infobulles ;
  - menus : 99 % d'usage (93 % dès le premier bloc), contre 64 % avec un retour audio ;
  - préférence : 67 à 89 % des participants classent ExposeHK en premier selon l'étude.
- Le résumé de presse indique un usage des raccourcis environ 4 fois plus élevé chez les amateurs après quelques minutes.
- Le mécanisme fonctionne parce que maintenir le modificateur est déjà le premier geste du raccourci : l'utilisateur répète physiquement le geste expert.

### P3. Rappeler les raccourcis avec des notifications calmes et en montrant le gain
- **Grossman, Dragicevic et Balakrishnan (CHI 2007).** Dans l'expérience principale (42 participants), l'usage des raccourcis passe de 28,9 % (contrôle) à 66,6 % avec le retour audio et à 72,8 % quand les menus sont désactivés. Dans le groupe contrôle, 7 participants sur 14 n'ont jamais utilisé de raccourci. Le retour purement visuel (texte qui clignote ou s'efface) n'a pas aidé et a été mal noté : 50 % d'usage au pilote, contre 57 % pour le contrôle.
- **Skillometers (Malacria, Scarr, Cockburn, Gutwin et Grossman, UIST 2013).** Une fenêtre éphémère affiche le temps des 6 dernières sélections (rouge pour la souris, vert pour le raccourci) et une estimation du temps perdu. Avec 24 participants, l'usage moyen des raccourcis passe de 28 % à 50 %. À la 10e répétition, il atteint 80 % contre 42 %.
- **Blur (Scarr, Cockburn, Gutwin et Quinn, CHI 2011, « Dips and ceilings »).** Des notifications calmes, superposées à des applications non modifiées, provoquent un passage précoce et durable vers les commandes rapides. Elles réduisent aussi la baisse de performance pendant la transition (*dip*).
- **Raursø et al. (HCII 2020, 10 participants).** Des suggestions affichées après chaque clic sont jugées utiles. En revanche, les animations (secousses, couleurs) agacent, et les participants réclament de pouvoir régler les suggestions.

### P4. Se concentrer sur les commandes fréquentes : peu de raccourcis, bien choisis
- Grossman et al. constatent que les commandes fréquentes sont mieux apprises, avec une distribution de type Zipf.
- Les Apple HIG recommandent de définir peu de raccourcis personnalisés, réservés aux actions les plus courantes. Trop de raccourcis rendent l'application plus difficile à apprendre et multiplient les conflits.
- Malacria et al. recensent en moyenne 55 raccourcis par application Mac (entre 15 et 112). C'est déjà beaucoup à retenir.

**Pour FL Remap.** Un profil par défaut d'environ 10 raccourcis vaut mieux que 40.

### P5. Les moyens mnémotechniques aident à se souvenir, mais ils entrent vite en collision
- **IconHK (Giannisakis, Bailly, Malacria et Chevalier, CHI 2017), 12 participants.** Intégrer la lettre du raccourci dans l'icône fait passer le rappel de 54 % (contrôle) à 87-88 %. Après 72 heures, il reste à 100 %, contre 71-73 % pour le contrôle. Le contrôle est la seule condition où le rappel diminue avec le temps.
- **HotStrokes (Cui et al., CHI 2019)** désigne le caractère arbitraire de l'association commande-touche comme l'obstacle principal.
- **Appert et Zhai (CHI 2009).** Avec des associations arbitraires, les participants retiennent 4 raccourcis clavier sur 14, contre 11,6 sur 14 pour les gestes. Les auteurs notent aussi que la première lettre crée vite des collisions : avec seulement Couper, Copier, Coller, Enregistrer et Imprimer, on en a déjà deux.
- Ils citent **Odell et al. (2004)** : des raccourcis numériques regroupés (1, 2, 3) étaient plus efficaces que des initiales.

**Règle de conception.** Pour les commandes fréquentes, utiliser des groupes spatiaux (chiffres, pavé de la main gauche). Pour les commandes rares, utiliser une lettre mnémotechnique (rappel plutôt que vitesse).

### P6. La mémoire spatiale est puissante si les positions ne bougent jamais
- **CommandMaps (Scarr, Cockburn, Gutwin et Bunt, CHI 2012, prix du meilleur article).** Une interface à plat et spatialement stable n'est pas plus lente pour les novices, et elle est significativement plus rapide que les menus et le Ruban pour les utilisateurs expérimentés.
- ExposeHK s'appuie explicitement sur la mémoire spatiale des emplacements.

**Pour FL Remap.** L'aide-mémoire doit avoir la forme d'un clavier, avec des positions fixes. Les raccourcis apparentés doivent être voisins.

### P7. Main gauche sur le clavier, main droite sur la souris : chaque main a son rôle
- **Kabbash, Buxton et Sellen (CHI 1994), 12 sujets.** La technique asymétrique où la main non dominante prépare le cadre et la main dominante agit (Toolglass) est la plus rapide : 2,43 s contre 2,89 à 2,96 s. La main gauche est active 83 % du temps. Les auteurs montrent aussi qu'une technique à deux mains mal conçue peut être pire qu'une technique à une main. Leur cadre théorique est le modèle de Guiard.
- Sur le forum Image-Line (mars 2026), un utilisateur se plaint que F9 et Shift+P soient trop loin de la main gauche. Il demande des raccourcis en bas à gauche du clavier, sans Shift.

**Pour FL Remap.** La main gauche choisit le contexte (fenêtre, outil, mode) et la souris fait le geste précis. Il faut un profil miroir pour les gauchers.

### P8. La cohérence et le transfert : ne pas casser ce que les gens savent déjà
- Les Apple HIG demandent de ne pas réutiliser un raccourci standard pour une action sans rapport, et de ne pas ajouter un modificateur à un raccourci existant pour une autre commande. Microsoft publie également une table d'accélérateurs communs à respecter.
- WCAG 2.1.4 mentionne que les personnes ayant certains troubles cognitifs bénéficient de raccourcis remappés pour correspondre à ceux d'autres applications.
- Studio One propose des schémas de raccourcis d'autres DAW (Pro Tools, Cubase…). Pour Production Expert et le blog Pro Tools User, c'est ce qui facilite la migration.
- **Bailly et al. (853 répondants)** montrent que la plupart des gens ont découvert les raccourcis grâce à une autre personne (professeur, camarade, famille), et rarement grâce aux infobulles. Pour FL, ce rôle social est surtout tenu par les tutoriels vidéo, qui enseignent les touches natives (F5 à F9, B, P, C…). Les remplacer revient à casser ce transfert.

### P9. Préférer les modes maintenus aux modes verrouillés
- **Sellen, Kurtenbach et Buxton (1992).** Un mode maintenu (une pédale tenue) produit significativement moins d'erreurs de mode qu'un mode verrouillé, que celui-ci soit activé au clavier ou à la pédale. Il donne aussi des tâches plus rapides et a été préféré par 11 sujets sur 15. Le retour visuel plein écran n'explique que 4 à 5 % des erreurs, contre 11 à 16 % pour la méthode de changement de mode.
- Ableton Live 12 suit ce principe : maintenir certains raccourcis environ 500 ms les rend momentanés.

**Pour FL Remap.** L'aide-mémoire et les modes temporaires doivent fonctionner tant que la touche est maintenue. L'interrupteur global verrouillé doit être doublé d'un retour très visible.

### P10. Fonctionner sur toutes les dispositions de clavier, pour tous les corps, et pouvoir tout désactiver
- **Microsoft (Raymond Chen)** : ne jamais utiliser Ctrl+Alt comme modificateur, car c'est AltGr sur de nombreuses dispositions. En allemand, Ctrl+Alt+Q produit `@`, et un bug réel lançait un publipostage quand l'utilisateur tapait « đ ».
- **kbdlayout.info** : éviter la ponctuation, Alt seul (accélérateurs de menus) et Ctrl+Alt, et choisir consciemment entre l'identité de la touche et sa position.
- **Apple HIG** : avec un modificateur autre que Command, n'utiliser que des lettres, car certaines dispositions ont besoin des modificateurs pour produire des caractères.
- **WCAG 2.1.4** : un raccourci à un seul caractère doit pouvoir être désactivé, remappé avec un modificateur, ou n'être actif que lorsque la commande a le focus. Cela protège les utilisateurs de la dictée vocale et les personnes qui appuient sur des touches par erreur.
- **Sticky Keys (macOS)** permet de taper les modificateurs l'un après l'autre. C'est utile pour une seule main, l'arthrite, les tremblements ou les TMS (AbilityNet).
- **Modèle KLM** : un appui de touche prend 0,2 à 0,28 s pour un tapeur moyen, et jusqu'à 1,2 s pour quelqu'un qui ne connaît pas le clavier. Chaque modificateur supplémentaire ajoute du temps et un risque d'erreur. Les HIG suggèrent un ou deux modificateurs au maximum.

---

## 2. Ce qu'observent les vrais utilisateurs de FL Studio

| Observation | Source |
|---|---|
| FL Studio ne permet toujours pas de personnaliser les raccourcis (version 2026.1.7 du 28 septembre 2026). La demande existe depuis au moins 2011 (profils façon GIMP). Un membre de l'équipe a répondu en avril 2026 que la fonction était « en développement », sans date. | Forum Image-Line (2011, 2020-2024, 2026) ; notes de version |
| Les utilisateurs contournent le problème avec AutoHotkey (Windows), Key Manager ou Hammer (Mac). | Forum Image-Line (2021, 2024, 2025) |
| Les plaintes concrètes portent sur : Rétablir = Ctrl+Alt+Z au lieu de Ctrl+Shift+Z ; Playlist et Mixer sur F5/F9, loin de la main gauche ; mute de clips = Alt+M ; outil crayon peu accessible. Les utilisateurs demandent des touches en bas à gauche sans Shift, et les équivalents Ableton (`Tab`, `0`). | Forum Image-Line, mars et juin 2026 |
| Sur Mac, les touches F exigent `fn`, sauf réglage système. | Base de connaissances Image-Line n°683 |
| Pattern suivant/précédent (`+`/`−`) et plusieurs commandes de transport dépendent du pavé numérique. Sur MacBook, il faut un clavier externe. | Forum Image-Line 2019 ; manuel FL |
| `⌘Espace` (pause) entre en conflit avec Spotlight. `⌘A` (arpégiateur) entre en conflit avec Tout sélectionner de macOS. | Forum Image-Line 2013 et 2020 |
| Les raccourcis à une lettre ne marchent pas quand « Typing keyboard to piano » est actif (`⌘T`). | Manuel FL |
| La barre d'aide (Hint bar) décrit la commande survolée. Elle affiche parfois la lettre de l'outil, mais pas systématiquement le raccourci. | Manuel FL ; RouteNote |
| Les raccourcis que les tutoriels présentent comme « essentiels » sont : Espace, F5/F6/F7/F9, `⌘S`, `⌘R` (export), `L`, `R`, les outils B/P/C/D/S/T, `⌘B` (dupliquer) et `⌘L` (router vers le mixer). | Manuel FL ; TutorialTactic ; RouteNote |
| Un utilisateur de Mac arrivé d'un autre DAW (juillet 2025) demande « aller au début », du zoom et du défilement au clavier, et trouve que c'est « beaucoup à absorber ». | Forum Image-Line |
| FL Studio n'est pas utilisable avec un lecteur d'écran, selon Image-Line. | Base de connaissances Image-Line n°606 |

Je n'ai pas pu consulter Reddit directement (le proxy a refusé la requête). Les éléments ci-dessus viennent donc surtout du forum officiel et des guides de tutoriels.

**Conséquence stratégique.** Si Image-Line livre un jour son propre éditeur de raccourcis, FL Remap perdra son intérêt pour le simple remappage. Il restera différenciant sur quatre points : l'apprentissage (aide-mémoire, rappels), les actions sans raccourci natif via MIDI, les jeux de raccourcis inspirés d'autres DAW et le profil pour portables.

---

## 3. Ce que font les DAW concurrents

| DAW | Mécanisme | Ce qui marche / ce que les utilisateurs en disent |
|---|---|---|
| **Ableton Live** | Key Map Mode : les éléments assignables deviennent rouges, on clique dessus puis on appuie sur une touche. Un Mapping Browser liste les assignations. Live 12 ajoute la navigation au clavier, des raccourcis momentanés (maintien d'environ 500 ms) et Shift pour les raccourcis à une lettre quand le clavier MIDI d'ordinateur est actif. | L'assignation se fait directement dans l'interface (on montre, puis on appuie). En revanche, les raccourcis de base ne sont pas remappables : une demande ouverte en juin 2026 cite AutoHotkey et Live Enhancement Suite comme contournements. |
| **Logic Pro** | Fenêtre Key Commands : recherche, filtres Used/Unused, Learn par étiquette ou par position (distingue le pavé numérique de la rangée de chiffres), copie en texte pour impression, préréglages, import/export. Ctrl-clic sur un élément de menu ouvre la fenêtre avec cette commande sélectionnée. | Le filtre « Unused » sert à découvrir les commandes sans raccourci. Le choix étiquette/position règle le problème des dispositions de clavier. |
| **Pro Tools** | Commands Keyboard Focus (bouton a…z) : un mode explicite où les lettres deviennent des commandes à une touche. Le pavé numérique a plusieurs modes pour le transport. | Sound On Sound parle d'une période d'adaptation difficile et conseille des autocollants, une feuille imprimée ou un second clavier. |
| **Reaper** | Liste d'actions avec filtre, sections (Main, MIDI Editor, Media Explorer…) où une même touche fait des choses différentes, actions personnalisées (macros), recherche par touche (« quelle action ? »), avertissement de conflit, fichier `.ReaperKeyMap`, export HTML imprimable, extension SWS. | C'est le modèle de référence pour les raccourcis contextuels. Sound On Sound conseille de sauvegarder sa configuration avant de la modifier. |
| **Bitwig** | Dashboard › Shortcuts : recherche par nom d'action ou par touche assignée, jeux de raccourcis, raccourcis propres à un projet. Les commandes visent le panneau qui a le focus, indiqué par une teinte. | Le focus visible rend le contexte explicite. Le Verr. Maj envoie des notes et casse les raccourcis : un piège documenté. |
| **Studio One** | Schéma de raccourcis importé d'autres DAW (Pro Tools, Cubase…), recherche, appui sur une touche pour voir son assignation, export. | Production Expert et le blog Pro Tools User jugent l'import utile aux nouveaux venus. Un auteur préfère pourtant apprendre les raccourcis natifs. Sound On Sound conseille de placer les commandes fréquentes près de la main libre. |
| **Cubase** | Dialogue Key Commands avec recherche, préréglages et macros. | La page du manuel n'a pas pu être lue (contenu chargé en JavaScript). Ce point n'est donc pas vérifié ici. |

**Points communs à retenir.**
1. Une recherche par nom et par touche.
2. Une vérification de conflit au moment de l'assignation.
3. Des jeux de raccourcis importables et exportables.
4. Une assignation possible depuis l'endroit où l'on se trouve (Ableton, Logic).
5. Un export imprimable.
6. Des raccourcis par contexte (Reaper, Bitwig).

---

## 4. Fonctionnalités à ajouter, classées par impact et par effort

L'impact concerne l'utilisateur réel. L'effort est estimé pour le code actuel (Swift, CGEventTap, script MIDI).

### Impact élevé, effort faible : à faire maintenant
1. **Corriger le profil par défaut** (voir §6) : supprimer `⌃←`/`⌃→` et les touches seules `Tab` et `0`, et ne plus doubler les raccourcis natifs de FL. *(P8, P10, conflits Spaces)*
2. **Vérifier les conflits au moment de l'assignation.** Il faut une table embarquée de trois listes :
   - les raccourcis système macOS (`⌘Q/W/H/M/Tab/Espace/,`, `⌃↑/↓/←/→`, `⌃Espace`, `⌃⌘Q`, `⌥⌘Échap`, `⇧⌘3/4/5`, Fn+A/C/D/E/N/Q…) ;
   - les raccourcis « Passer au bureau N », s'ils sont activés (lisibles dans `com.apple.symbolichotkeys`) ;
   - les raccourcis natifs de FL, par fenêtre (manuel FL).

   Le message doit être explicite, par exemple : « ⌃→ : macOS l'utilise pour changer de bureau » ou « S : FL l'utilise déjà pour Solo dans le Mixer ». *(Reaper, Studio One, HIG)*
3. **Avertir pour les touches sans modificateur.** Afficher une alerte à l'enregistrement d'une touche seule (lettre, chiffre, Tab), et proposer d'ajouter ⌃ ou de limiter le raccourci à une fenêtre. *(WCAG 2.1.4)*
4. **Afficher un retour quand l'interrupteur global change d'état.** Un petit panneau « FL Remap désactivé » doit rester visible tant que c'est le cas, et l'icône de la barre des menus doit être plus contrastée. *(P9, Sellen)*
5. **Ajouter des libellés d'accessibilité** aux `Toggle` et `Picker` de l'éditeur (`.accessibilityLabel`) et tester avec VoiceOver. *(P10)*
6. **Permettre l'import et l'export d'un profil** (fichier `.flremap` en JSON) pour sauvegarder et partager. *(Reaper, Logic, Bitwig ; P8, découverte sociale)*

### Impact élevé, effort moyen : prochaine version
7. **Aide-mémoire en maintenant ⌃ (≈ ExposeHK).** Après environ 400 à 600 ms de ⌃ seul maintenu dans FL, afficher un panneau flottant non activant en forme de clavier, dans la disposition réelle (AZERTY, QWERTZ…). Il montre les raccourcis ⌃ de l'utilisateur, groupés par couleur (fenêtres, transport, édition), avec les raccourcis natifs de FL en filigrane. Le panneau disparaît au relâchement. Le délai évite de gêner les experts qui enchaînent vite.

   Techniquement, il faut ajouter `flagsChanged` au masque de l'event tap et utiliser un `NSPanel` avec `.nonactivatingPanel`. *(P2, P6, P9 ; ExposeHK 94-99 %)*
8. **Préréglage « Portable / MacBook ».** Des équivalents sans `fn` ni pavé numérique pour F5 à F9, `+`/`−` (pattern), `*` et `/` (mesure suivante/précédente) et le 0 du pavé (avance rapide), grâce aux remaps « Autre raccourci » qui envoient la vraie touche F ou du pavé numérique. *(Plaintes forum : touche fn, pavé numérique)*
9. **Jeux de raccourcis « venus d'ailleurs ».**
   - **Ableton** : `Tab`, `0`, `⌘⇧Z`, `⌘E` pour couper au curseur si c'est faisable.
   - **Logic.**
   - **Studio One** : F2/F3 pour Éditeur/Console.
   - **Pro Tools.**
   - **FL Windows → Mac**, pour ceux qui changent de plateforme.

   Chaque jeu doit indiquer clairement ce qu'il remplace dans FL. *(Studio One ; P8)*
10. **Recherche et catégories dans l'éditeur.** Recherche par nom d'action ou par appui sur une touche (« que fait ⌃D ? »), groupes Fenêtres / Transport / Patterns / Mixer, et filtre « actions sans raccourci ». *(Logic Used/Unused, Reaper, Bitwig)*
11. **Export d'un aide-mémoire imprimable.** PDF A4 et PNG en fond d'écran, générés dans la disposition de l'utilisateur, avec code couleur, plus une planche d'autocollants pour les touches utilisées. *(Pro Tools/SOS, export HTML de Reaper ; P6.)* Cet export a moins d'effet que l'aide-mémoire au maintien, parce qu'un document à consulter exige de la motivation (Raursø).

### Impact élevé, effort élevé : feuille de route
12. **Rappel discret façon Blur ou Skillometer.** Le script FL signale les changements de fenêtre active (`OnRefresh` avec le drapeau de focus) via un port MIDI de retour. Si la fenêtre a changé sans qu'une touche correspondante soit passée par l'event tap, on en déduit un clic. FL Remap affiche alors, en bas de l'écran pendant 3 s : « Mixer → ⌃4 ». Règles :
    - au maximum un rappel par commande et par session ;
    - jamais pendant la lecture ou l'enregistrement ;
    - bouton « ne plus montrer » ;
    - aucune animation.

    Ajouter un compteur hebdomadaire dans le menu, par exemple « 42 raccourcis utilisés, environ 46 s gagnées », en s'appuyant sur le KLM (environ 1,1 s pour pointer contre environ 0,2 s par touche). *(P3 ; Skillometers 28 → 50 %, Grossman 28,9 → 66,6 %, Raursø)*

    Pas de son : le retour audio de Grossman est ce qui fonctionnait le mieux en laboratoire, mais dans un DAW il couvrirait la musique.
13. **Raccourcis par fenêtre FL (contextuels).** Une même touche fait des choses différentes dans la Playlist, le Piano Roll ou le Mixer. Le script connaît la fenêtre focalisée (`ui.getFocused`) : il peut soit renvoyer l'information à l'application, soit recevoir un CC générique et choisir lui-même l'action. Dans l'éditeur, on peut ajouter une colonne « Où » (Partout / Playlist / Piano Roll / Mixer / Channel Rack). *(Reaper, Bitwig)*
14. **Suspension automatique pendant la saisie de texte.** Si on peut détecter qu'une boîte de renommage ou un champ de saisie de FL est au premier plan (via l'API Accessibility : titre ou rôle de fenêtre, à vérifier), on laisse passer toutes les touches sans modificateur. *(WCAG 2.1.4 ; P9)*
15. **Déclencheurs sans clavier.** Accepter en entrée une note MIDI, une pédale ou un bouton de contrôleur, déjà présents dans le pipeline MIDI. C'est utile pour les personnes qui utilisent une seule main, ont une mobilité réduite ou souffrent de TMS. *(Reaper, Logic, Bitwig acceptent le MIDI ; Sellen : la pédale maintenue est le meilleur mode)*

### Impact moyen, effort faible
16. **Profil miroir pour gauchers** (souris à gauche, raccourcis regroupés à droite autour de 7-0 et U-P). *(P7)*
17. **Mode « Apprentissage » des premiers jours.** Pendant 7 jours, l'aide-mémoire s'ouvre plus vite (environ 250 ms), les rappels sont actifs, et une liste « Tes 5 raccourcis de la semaine » ne présente que 5 commandes à la fois (Zipf). Ensuite, l'ensemble se met en retrait automatiquement. *(P3, P4)*
18. **Mémoriser à la fois l'étiquette et la position de chaque touche** (comme Logic). Par défaut, l'étiquette sert pour les lettres mnémotechniques et la position pour les chiffres et les groupes spatiaux. À l'import d'un profil venant d'une autre disposition, on propose une conversion. *(P5, P10)*
19. **Vérifier la compatibilité avec Sticky Keys et Slow Keys**, puis le documenter. *(P10)*

---

## 5. Ce qu'il ne faut PAS faire (pièges documentés)

1. **Avaler des touches sans modificateur partout** (`0`, `Tab`, lettres). Cela casse la saisie de noms et de tempo ainsi que le mode clavier-piano. C'est le cas visé par WCAG 2.1.4, et c'est le cas du profil actuel.
2. **Utiliser `⌃` + flèches, `⌃Espace` ou `⌃↑`/`⌃↓` sur Mac** (Spaces, source de saisie, Mission Control). Plus généralement, ne pas utiliser Control sans vérifier les conflits (Apple HIG).
3. **Utiliser Ctrl+Alt sur Windows** : c'est AltGr, qui produit `@`, `€`, `{`… (Raymond Chen, kbdlayout.info). Éviter aussi Alt+lettre (accélérateurs de menus), Win+… (réservé au système) et Ctrl+Shift (changement de disposition de clavier).
4. **Utiliser la ponctuation ou les lettres instables entre dispositions** dans un profil commun. A/Q, Z/W, M, Y/Z et `; , . - =` changent de place entre QWERTY, AZERTY et QWERTZ.
5. **Réaffecter des standards** à une action sans rapport (`⌘Q/W/H/M/S/Z/C/V`), ou ajouter un modificateur à un standard pour une autre commande (Apple HIG).
6. **Remplacer les raccourcis natifs que les tutoriels enseignent** (Espace, F5-F9, B/P/C/D/S/T, `⌘S`, `⌘R`, L, R) dans le profil par défaut. Cela coupe le transfert social et vidéo. Ce genre de remplacement doit rester un choix explicite dans un jeu « Ableton » ou similaire. *(P8, Bailly et al.)*
7. **Mettre trop de raccourcis dans le profil par défaut.** Plus de raccourcis signifie plus de conflits et un apprentissage plus difficile (HIG, Zipf).
8. **Rendre les rappels intrusifs** : animations, couleurs criardes, rappels permanents ou rappels pendant l'enregistrement (Raursø). Le retour visuel « après coup » sous forme de simple texte a déçu dans Grossman et al.
9. **Empêcher d'utiliser la souris pour forcer l'apprentissage.** Les menus désactivés fonctionnaient en laboratoire (72,8 %), mais FL Remap ne peut ni ne doit bloquer FL : le coût de frustration en usage réel n'est pas mesuré, et les participants n'aimaient pas le délai imposé (Grossman).
10. **Mettre des combinaisons de 3 ou 4 touches sur des actions fréquentes.** Cela coûte du temps (KLM) et des erreurs, et c'est pénible avec une seule main ou des TMS. Les réserver aux actions rares ou de sécurité.
11. **Créer des modes verrouillés invisibles** (interrupteur global sans retour). Ils provoquent des erreurs de mode (Sellen et al.).
12. **Supposer des touches F et un pavé numérique** sur Mac ou sur portable (base de connaissances Image-Line 683, forum 2019).
13. **Utiliser `fn`/🌐 comme modificateur sur Mac** : Fn+A/C/D/E/N/Q sont des raccourcis système (Apple).

---

## 6. Proposition de profil par défaut : « FL+ main gauche »

**Règles de conception, issues des principes ci-dessus.**
- **Un seul espace de noms libre.** Sur Mac, FL traduit Ctrl en ⌘ et Alt en ⌥. La touche physique **⌃ Control** n'est donc presque pas utilisée par FL au clavier : c'est l'espace propre à FL Remap. Cela va contre la règle « éviter Control » des HIG, et c'est assumé : le risque d'Apple porte sur les raccourcis système Control, que l'on exclut explicitement (flèches, Espace) et que l'on vérifie pour les chiffres.
- **Un seul modificateur pour les actions fréquentes.** Les chiffres (positions physiques) servent pour les fenêtres, et les lettres stables de la main gauche (E, R, T, S, D, F, G, X, C, V, B, identiques en QWERTY, AZERTY et QWERTZ) servent pour les actions.
- **Réutiliser le sens que FL donne déjà aux lettres** pour qu'elles se renforcent : S = Solo dans le Mixer, T = outil Mute.
- **Rien n'écrase FL.** On ajoute, on ne remplace pas. Le jeu « Ableton » (Tab, 0, etc.) reste disponible en option.
- **Au total, 11 raccourcis** et une touche d'aide.

### Mac

| Action | Raccourci | Position (QWERTY ; en AZERTY si différent) | Justification |
|---|---|---|---|
| **Aide-mémoire** (maintenir) | maintenir `⌃` environ 0,5 s | coin inférieur gauche | ExposeHK : on maintient le modificateur même qu'on utilise ensuite (P2, P9) |
| Playlist | `⌃1` | rangée des chiffres (AZERTY : `&/1`, sans Maj grâce à la position physique) | Groupe spatial ordonné comme le flux de travail (P5, P6). Remplace F5, qui demande `fn` sur Mac |
| Channel Rack | `⌃2` | (AZERTY : `é/2`) | idem, remplace F6 |
| Piano Roll | `⌃3` | (AZERTY : `"/3`) | idem, remplace F7 |
| Mixer | `⌃4` | (AZERTY : `'/4`) | idem, remplace F9, la plainte « trop loin » du forum |
| Browser | `⌃5` | (AZERTY : `(/5`) | idem, remplace ⌥F8 |
| Pattern précédent | `⌃D` | rangée de repos, majeur gauche | Paire voisine, remplace `−` du pavé numérique, absent sur MacBook (P5, P7) |
| Pattern suivant | `⌃F` | rangée de repos, index gauche | Remplace `+` du pavé numérique |
| Mute (piste/canal sélectionné) | `⌃T` | | T = outil Mute de FL (P8), lettre stable |
| Solo (piste/canal sélectionné) | `⌃S` | | S = Solo dans le Mixer de FL (P8), lettre stable |
| Métronome | `⌃M` | AZERTY : touche M à droite de L (par étiquette) | Action rare, donc lettre mnémotechnique placée par étiquette (P5). Évite `⌘M`, qui réduit la fenêtre sous macOS |
| Rétablir | `⌘⇧Z` | | Standard Apple (HIG), plainte du forum sur ⌥⌘Z |
| Activer / désactiver FL Remap | `⌃⌥⌘F` + panneau visible | | Rare et volontairement difficile à taper par accident. Ajouter un retour visible (P9) |

**Retirés du profil actuel :** `Tab`, `0` (touches seules, WCAG), `⌃←`/`⌃→` (Spaces), `⌃L` (doublon de `L`, natif dans FL). Au premier lancement, si « Passer au bureau 1-5 » est activé, l'application propose `⌃⌥1` à `⌃⌥5` ou d'ouvrir les réglages système.

**Profil gaucher (miroir) :** `⌃6` à `⌃0` pour les fenêtres, `⌃J`/`⌃K` pour les patterns, `⌃U`/`⌃I` pour Mute/Solo. Lettres stables : U, I, O, P, J, K, L, N.

### Windows (pour un futur portage, à valider avec la liste complète des raccourcis FL)
Sur Windows, FL utilise lui-même Ctrl et Alt, et Ctrl+Alt est interdit (AltGr). L'espace le moins encombré est **Ctrl+Shift+chiffres et lettres stables** :
- fenêtres : `Ctrl+Shift+1` à `5` ;
- patterns : `Ctrl+Shift+D/F` ;
- Mute/Solo : `Ctrl+Shift+T/S` ;
- Rétablir : `Ctrl+Y` et `Ctrl+Shift+Z` (table Microsoft) ;
- aide-mémoire : maintenir `Ctrl+Shift`.

Il faut vérifier `Ctrl+Shift+S` (« Enregistrer sous » dans FL) et `Ctrl+Shift+M` (export MIDI) : si un conflit est confirmé, remplacer par `Ctrl+Shift+G` et `Ctrl+Shift+V`. Ne jamais utiliser Win+…, Alt+lettre ou Ctrl+Alt. Les touches F natives restent utilisables : la plupart des PC en ont, avec Fn-lock.

### AZERTY et QWERTZ
- Les chiffres sont enregistrés par position : `⌃1` reste la touche `&/1` sans Maj. L'aide-mémoire doit montrer les deux caractères gravés sur la touche.
- Les lettres d'action (D, F, S, T) sont stables sur les trois dispositions. M est la seule lettre placée par étiquette, puisqu'elle sert de moyen mnémotechnique.
- Le profil n'utilise aucune ponctuation.
- Sur Mac, les combinaisons ⌥+lettre produisent des caractères (œ, ©, @ selon la disposition) : on n'utilise pas ⌥ seul comme modificateur de FL Remap.

---

## 7. Sources

**Recherche HCI**
- Grossman, Dragicevic et Balakrishnan, *Strategies for Accelerating On-line Learning of Hotkeys*, CHI 2007 : https://www.dgp.toronto.edu/~ravin/papers/chi2007_learninghotkeys.pdf
- Malacria, Bailly, Harrison, Cockburn et Gutwin, *Promoting Hotkey Use through Rehearsal with ExposeHK*, CHI 2013 : https://www.csse.canterbury.ac.nz/andrew.cockburn/papers/ehk.pdf (résumé de presse : https://sciencedaily.com/releases/2013/09/130930093728.htm)
- Giannisakis, Bailly, Malacria et Chevalier, *IconHK*, CHI 2017 : https://biblio.telecom-paristech.fr/cgi-bin/download.cgi?id=16676
- Tak, Westendorp et van Rooij, *Satisficing and the use of keyboard shortcuts*, Interacting with Computers 25(5), 2013 : https://research.tue.nl/nl/publications/satisficing-and-the-use-of-keyboard-shortcuts-being-good-enough-i/
- Lane, Napier, Peres et Sándor, *Hidden costs of graphical user interfaces*, IJHCI 18(2), 2005 (résumé via https://ad-astra.ro/?p=17424 ; texte intégral non consulté)
- Krisler et Alterman, *Training towards mastery: overcoming the active user paradox* (HotKeyCoach), NordiCHI 2008 : https://synapsesocial.com/papers/W2036310984 (résumé seulement, pas de chiffres consultés)
- Cockburn, Gutwin, Scarr et Malacria, *Supporting Novice to Expert Transitions in User Interfaces*, ACM Computing Surveys 47(2), 2014 : https://api.openalex.org/works/doi:10.1145%2F2659796
- Scarr, Cockburn, Gutwin et Quinn, *Dips and Ceilings* (Blur), CHI 2011 : https://api.openalex.org/works/doi:10.1145/1978942.1979348
- Scarr, Cockburn, Gutwin et Bunt, *Improving Command Selection with CommandMaps*, CHI 2012 : https://hci.cs.umanitoba.ca/publications/details/improving-command-selection-with-commandmaps
- Malacria, Scarr, Cockburn, Gutwin et Grossman, *Skillometers*, UIST 2013 : https://research.autodesk.com/app/uploads/2023/03/skillometers-reflective-widgets-that.pdf_reco6nF5Pb4FQHd2x.pdf
- Appert et Zhai, *Using Strokes as Command Shortcuts* (citant Odell et al. 2004) : https://www.lri.fr/~appert/website/papers/StrokeShortcuts.pdf
- Cui et al., *HotStrokes*, CHI 2019 : https://par.nsf.gov/servlets/purl/10093189
- Raursø et al., *Intermodal Improvement: Nudging Users to Use Keyboard Shortcuts*, HCII 2020 : https://vbn.aau.dk/ws/files/438685057/HCII2020_cameraready.pdf
- Bailly, Avellino, Brulé et Malacria, *The Role of Social Interactions in the Discovery of Keyboard Shortcuts* (N = 853) : https://hci.isir.upmc.fr/project/keyboard-shortcuts/
- Kabbash, Buxton et Sellen, *Two-Handed Input in a Compound Task*, CHI 1994 : https://www.billbuxton.com/2hCHI94.html
- Sellen, Kurtenbach et Buxton, *The Prevention of Mode Errors through Sensory Feedback*, 1992 : https://billbuxton.com/ModeErrors.html
- Keystroke-Level Model (temps des opérateurs) : https://en.wikipedia.org/wiki/Keystroke-level_model
- Trewin et Pain, *Keyboard and Mouse Errors Due to Motor Disabilities* : https://www.dai.ed.ac.uk/daidb/papers/documents/rp838.html (résumé seulement)

**Plateformes et accessibilité**
- Apple HIG, Keyboards (copie lisible : https://hingumingu.oopy.io/dd7dbe1b-6a3a-485c-a7bf-b88a71d77176 ; officiel : https://developer.apple.com/design/human-interface-guidelines/keyboards)
- Raccourcis clavier du Mac : https://support.apple.com/en-us/102650
- Ctrl+gauche/droite comme raccourci Spaces par défaut : https://discuss.binaryage.com/t/disable-spaces-default-control-arrow/7555 ; https://www.macworld.com/article/215453/controlling-mission-control-with-your-keyboard.html
- Raymond Chen, *Why Ctrl+Alt shouldn't be used as a shortcut modifier* : https://devblogs.microsoft.com/oldnewthing/20040329-00/?p=40003
- kbdlayout.info, *Creating a shortcut?* : https://kbdlayout.info/shortcut
- Microsoft, Keyboard accelerators : https://learn.microsoft.com/en-us/windows/apps/design/input/keyboard-accelerators
- Microsoft, Windows keyboard shortcuts : https://support.microsoft.com/en-us/help/12445/windows-keyboard-shortcuts
- W3C, Understanding SC 2.1.4 Character Key Shortcuts : https://www.w3.org/WAI/WCAG21/Understanding/character-key-shortcuts
- AbilityNet, Sticky Keys macOS 26 : https://mcmw.abilitynet.org.uk/how-to-make-keyboard-shortcuts-easier-to-perform-in-macos-26-tahoe

**FL Studio**
- Manuel FL, raccourcis : https://www.image-line.com/fl-studio-learning/fl-studio-online-manual/html/basics_shortcuts.htm
- Manuel FL, nouveautés (2026.1.7) : https://www.image-line.com/fl-studio-learning/fl-studio-online-manual/html/basics_new.htm
- Manuel FL, Hint bar : https://www.image-line.com/fl-studio-learning/fl-studio-online-manual/html/toolbar_panels.htm
- Base de connaissances 683 (touches F et fn sur Mac) : https://support.image-line.com/action/knowledgebase/?ans=683
- Base de connaissances 606 (lecteurs d'écran) : https://support.image-line.com/action/knowledgebase?ans=606
- Forum, demande de personnalisation, avril 2026 : https://forum.image-line.com/viewtopic.php?p=2057042
- Forum, *Changing Keyboard Shortcuts :((*, mars 2026 : https://forum.image-line.com/viewtopic.php?p=2051874
- Forum, *a burning wish from my heart*, juin 2026 : https://forum.image-line.com/viewtopic.php?p=2063785
- Forum, *How can I change FL Studio's shortcuts?* : https://forum.image-line.com/viewtopic.php?p=1512581
- Forum, *Edit/Manage Keyboard Shortcuts*, 2011 : https://forum.image-line.com/viewtopic.php?p=489120
- Forum, pattern suivant sans pavé numérique, 2019 : https://forum.image-line.com/viewtopic.php?p=1428339
- Forum, pause et Spotlight, 2020 : https://forum.image-line.com/viewtopic.php?p=1462580
- Forum, conflits ⌘ sur Mac, 2013 : https://forum.image-line.com/viewtopic.php?p=839511
- Forum, utilisateur Mac venu d'un autre DAW, 2025 : https://forum.image-line.com/viewtopic.php?p=2014911
- Forum, AutoHotkey : https://forum.image-line.com/viewtopic.php?p=1602648 ; Key Manager : https://forum.image-line.com/viewtopic.php?p=1953602
- Guides tutoriels : https://tutorialtactic.com/blog/fl-studio-shortcuts/ ; https://routenote.com/blog/keyboard-shortcuts-for-fl-studio/
- Clavier Logickeyboard pour FL Studio : https://logickeyboard.com/shop/fl-studio-mac-4608p.html

**DAW concurrents**
- Ableton, MIDI and Key Remote Control : https://www.ableton.com/en/manual/midi-and-key-remote-control/
- Ableton, nouveaux raccourcis de Live 12 : https://help.ableton.com/hc/en-us/articles/12840878679452
- Ableton, demande de raccourcis personnalisables, 2026 : https://forum.ableton.com/viewtopic.php?p=1837301
- Logic Pro, Key Commands : https://help.apple.com/logicpro/mac/10.1/en.lproj/lgcp68d9ced1.html ; https://help.apple.com/logicpro/mac/10.1/en.lproj/lgcp32e85cd9.html ; https://help.apple.com/logicpro/mac/9.1.6/en/logicpro/usermanual/chapter_8_section_4.html ; https://www.soundonsound.com/techniques/logic-pro-key-commands
- Pro Tools, Keyboard Focus : https://www.soundonsound.com/techniques/using-pro-tools-keyboard-commands-focus
- Reaper : https://www.cockos.com/wiki/index.php/Actions_Menu_Bar ; https://www.cockos.com/wiki/index.php/Preferences_Keyboard ; https://www.soundonsound.com/node/4913273
- Bitwig, User Interfacing : https://www.bitwig.com/userguide/latest/user_interfacing
- Studio One : https://www.soundonsound.com/techniques/studio-one-shortcuts-efficient-workflows ; https://protoolsuserblog.wordpress.com/2015/03/19/2015-2-19-studio-one-quick-tips-import-key-commands-for-other-daws/ ; https://www.production-expert.com/production-expert-1/2018/8/20/a-pro-tools-users-first-steps-in-studio-one-with-help-from-an-editors-keys-keyboard

**Sources non accessibles pendant la recherche :**
- api.crossref.org (DOI 10.1145/3476510) : limite de débit, erreur HTTP 429 ;
- copies HAL d'ExposeHK et d'IconHK : protection anti-robots (le PDF canonique a été lu à la place) ;
- page du manuel Cubase et page officielle des HIG : contenu chargé en JavaScript ;
- Reddit : requête refusée par le proxy.
