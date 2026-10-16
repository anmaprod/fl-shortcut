# Compte rendu des essais de FL Shortcut sur le Mac de Malo

- Date : 16/10/2026, à partir de 13:50
- Commit essayé : 0a04f2f (branche claude/great-hopper-qihaiy)
- macOS 27.0.1 (26A434), Apple M4 (arm64) · Xcode 27.0
- FL Studio 2026 26.1.7.5419 (/Applications/FL Studio 2026.app)
- Écrans : intégré Retina 3024 × 1964 (1512 × 982 points, principal) ; HDMI 2560 × 1440, placé au-dessus
  (origine −442, −1440)
- Clavier : disposition « French » (AZERTY)

## A. Automatique

**A1 — KO au premier lancement, OK une fois relancé avec `--vite`.**

Premier lancement, `scripts/essais-mac.sh` sans option :

1. Pas : `cd ~/Documents/fl-shortcut && scripts/essais-mac.sh`. FL Studio ouvert, personne à la souris.
2. Attendu : 5 essais PASS et `dist/essais/resume.txt`. Obtenu : Python, tests Swift et compilation PASS,
   puis les 4 essais du FL simulé en FAIL. Pas de `dist/essais/` à la fin, ni de résumé. Les préférences
   n'ont pas pu être remises.
3. Sortie complète :
```
macOS 27.0.1 (arm64) · Xcode 27.0 · commit 0a04f2f
FL Studio 26.1.7.5419 (/Applications/FL Studio 2026.app)
▸ Tests du script FL (Python)
PASS  Tests du script FL (Python) (3 s)
▸ Tests Swift
PASS  Tests Swift (14 s)
      	 Executed 314 tests, with 0 failures (0 unexpected) in 5.574 (5.592) seconds
▸ Compilation et installation dans ~/Applications
PASS  Compilation et installation dans ~/Applications (35 s)
▸ Choix automatique du preset (vraie boîte « Open »)
FAIL  Choix automatique du preset (vraie boîte « Open ») (3 s, code 0) → /Users/malo/Documents/fl-shortcut/dist/essais/selftest-preset.txt
scripts/essais-mac.sh: line 103: /Users/malo/Documents/fl-shortcut/dist/essais/fakefl.txt: No such file or directory
▸ Macro « Enregistrement rapide » sur le FL simulé (6 passages)
FAIL  Macro « Enregistrement rapide » sur le FL simulé (6 passages) (16 s, code 1) → /Users/malo/Documents/fl-shortcut/dist/essais/selftest-macro.txt
▸ Macro construite en blocs (chemin du bouton « Tester »)
FAIL  Macro construite en blocs (chemin du bouton « Tester ») (15 s, code 1) → /Users/malo/Documents/fl-shortcut/dist/essais/selftest-blocs.txt
▸ « Enregistrer des clics » puis rejeu
FAIL  « Enregistrer des clics » puis rejeu (15 s, code 1) → /Users/malo/Documents/fl-shortcut/dist/essais/selftest-clics.txt
Error: Could not read data from /Users/malo/Documents/fl-shortcut/dist/essais/preferences-avant.plist
scripts/essais-mac.sh: line 74: /Users/malo/Documents/fl-shortcut/dist/essais/resume.txt: No such file or directory

Résumé : /Users/malo/Documents/fl-shortcut/dist/essais/resume.txt
cat: /Users/malo/Documents/fl-shortcut/dist/essais/resume.txt: No such file or directory
grep: /Users/malo/Documents/fl-shortcut/dist/essais/resume.txt: No such file or directory
```
   Le script sort avec le code 0 malgré les FAIL : `grep -q '^FAIL' "$RESUME"` ne trouve pas le résumé.
4. macro.log : non concerné, les essais n'ont pas démarré.
5. Fenêtres de FL : non concerné, rien dans le vrai FL.
6. Reproductible à chaque lancement sans `--vite` : c'est déterministe. Avec `--vite`, tout passe (ci-dessous).
7. Cause : `scripts/essais-mac.sh:30-31` crée `OUT="$PWD/dist/essais"` et y range la sauvegarde des préférences
   (ligne 73). L'étape de compilation lance ensuite `./build.sh`, qui fait `rm -rf dist` (`build.sh:37`) : la
   sauvegarde, puis tous les fichiers de sortie, disparaissent. Correctif : mettre `OUT` hors de `dist/`
   (par exemple `build/essais` ou un dossier `mktemp -d`), ou créer `OUT` et la sauvegarde APRÈS la compilation.
   Il faut aussi faire échouer le script quand le résumé manque (`[[ -f "$RESUME" ]] || exit 1`).

Relance avec `scripts/essais-mac.sh --vite`, sur l'app compilée juste avant au même commit :
```
Essais automatiques de FL Shortcut — 16/10/2026 13:58
Commit : 0a04f2f (claude/great-hopper-qihaiy)
macOS 27.0.1 (arm64) · Xcode 27.0 · commit 0a04f2f
FL Studio 26.1.7.5419 (/Applications/FL Studio 2026.app)
PASS  Tests du script FL (Python) (3 s)
PASS  Choix automatique du preset (vraie boîte « Open ») (2 s)
PASS  Macro « Enregistrement rapide » sur le FL simulé (6 passages) (19 s)
PASS  Macro construite en blocs (chemin du bouton « Tester ») (1 s)
PASS  « Enregistrer des clics » puis rejeu (7 s)
```
Tests Swift (314, 0 échec) et compilation : PASS au premier lancement.

**A2** — NON FAIT pour l'instant : prévu en fin de plan (ordre du plan).

## G. Système (vu pendant A1)

**G1 — KO : les préférences ne reviennent pas exactement comme avant.**

1. Pas : `defaults export app.flshortcut.FLShortcut <sauvegarde>`, puis `scripts/essais-mac.sh --vite`, puis
   comparaison du domaine avec ma sauvegarde (`diff` des deux plist en XML).
2. Attendu : préférences identiques. Obtenu : deux clés en plus, laissées par les essais du FL simulé.
3. Diff exact (`<` = après les essais, absent de la sauvegarde) :
```
45,46d44
< 	<key>macroMenuEnterAfterLetter</key>
< 	<true/>
51,56d48
< 	</data>
< 	<key>macroSpots.v2.input</key>
< 	<data>
< 	eyJob3BzIjpbeyJzaXplIjpbMjMwLDg4XSwib2Zmc2V0IjpbMTE1LDU0XX1dLCJ2ZXJz
< 	aW9uIjoyLCJzdGFydCI6eyJmcm9tVG9wUmlnaHQiOlstMTM1LDg2XSwid2luZG93U2l6
< 	ZSI6Wzk0MCw2NDhdfX0=
```
   Une fois décodée, `macroSpots.v2.input` vaut `{"ops":[{"size":[230,88],"offset":[115,54]}],"version":2,
   "start":{"fromTopRight":[-135,86],"windowSize":[940,648]}}`. C'est l'entrée apprise sur la fenêtre du FL
   simulé (940 × 648). Laissée en place, la macro « Enregistrement rapide » l'aurait rejouée dans le vrai FL.
4. Sortie : voir le diff. 5. Fenêtres : non concerné.
6. Reproductible : à chaque fois qu'un essai apprend une clé qui n'existait pas avant.
7. Cause : `scripts/essais-mac.sh:76`, `defaults import` FUSIONNE le fichier dans le domaine (il réécrit les
   clés du fichier) mais ne retire pas les clés ajoutées entre-temps. Correctif : `defaults delete "$DOMAIN"`
   juste avant `defaults import` (après `pkill -x FLShortcut`, déjà fait ligne 75).
   Remise en état faite à la main : `defaults delete … macroMenuEnterAfterLetter` et
   `defaults delete … macroSpots.v2.input`. Le domaine est ensuite identique à la sauvegarde.

## C. Macros (constats sans essai, d'après les captures du vrai FL du 16/10)

**C3 — en partie vérifié, sans essai.** Le menu de piste du Mixer (clic droit sur le nom d'Insert 1, FL 26.1.7)
contient, dans l'ordre de la section Routing : Channel routing ›, Track routing › (grisé), Select ›, Reset selected
track(s) routing, Unroute tracks routed to the selected track(s), puis un séparateur, puis Solo selected track(s)
(S), Alt solo selected track(s) (⌥S), Arm selected track(s), Disarm selected track(s), Compensate for master latency
(grisé, coché). Depuis « Select », « Arm selected track(s) » est donc le 5e élément actif, ce que suppose
`MacroRunner.armDownCount = 5` (`MacroRunner.swift:139`), À CONDITION que ↓ saute le séparateur entre « Unroute… »
et « Solo… ». C'est le seul point encore à voir sur le vrai FL. Les autres éléments du menu : Rename, color and icon…
(F2), Change color…, Random color, Gradient color… (grisé), Change icon…, Assign to new Audio track(s), Unassign
from Audio track(s) (grisé), File ›, Open audio editor (⌘E), Open audio editor and record (⇧E), Reset selected
track(s) to default, Group : Separator (coché), Create group…, Auto color group (grisé) ; Layout : Dock to ›, Move
left (⌥←), Move right (⌥→), Delete (Del), Insert one, Insert multiple…, Insert from state › ; CPU : Allow threaded
processing (coché).

## D. Icônes (essais du 16/10, avant ce plan)

- Pose 7-4 sur Insert 2 (`--diag-icon 7-4 --relearn`, bouton montré par Malo) et 1-0 sur la piste 3 (`--diag-icon
  1-0`, bouton appris cliqué seul, 0,97 s) : PASS, icônes vues dans la fenêtre du nom (micro, note).
- Juste après la 2e pose, la grille gardait son numéro (#9055) réduite à 44 × 44 (animation de fermeture). Corrigé
  dans be39e72 : une grille qui n'a plus sa forme compte comme fermée (sinon « grille restée ouverte » et deux Échap
  à tort si l'animation dépasse 1 s ; test du faux FL qui échouait avant).

## Lenteurs

- A1 : aucune étape anormale. Tests Swift 14 s, compilation 35 s, macro « Enregistrement rapide » 19 s pour
  6 passages.

## Surprises

- `build.sh` installe aussi l'app dans ~/Applications à chaque compilation, y compris quand c'est
  `essais-mac.sh` qui l'appelle.
