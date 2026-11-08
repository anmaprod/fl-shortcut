#!/usr/bin/env python3
# Fabrique les modèles des modes d'emploi du téléchargement : docs/telechargement/modele-mac.html et
# modele-windows.html (français), modele-mac-en.html et modele-windows-en.html (anglais), au style suisse de l'app.
# 05/11 : une page de remerciement, puis les étapes. 08/11 (« plus facile à lire, vraiment bref », puis ses retours
# ligne par ligne) : « merci » seul au début, plus de barre en haut, une à cinq lignes courtes par étape, deux lignes
# dans le jeu des touches, les cartes des macros toutes noires (blanches et soulevées au survol), les 4 cases de MIDI
# Settings à droite, les thèmes de l'app qui changent toute la page (section « à ton goût »), plus de pied de page ;
# l'anglais écrit ici, à côté du français (plus traduit morceau par morceau).
# Usage : python3 scripts/lisezmoi_modeles.py docs/telechargement, puis python3 scripts/lisezmoi.py (images collées).
import sys
DOSSIER = sys.argv[1] if len(sys.argv) > 1 else "docs/telechargement"

CSS = r'''
/* Mode d'emploi du téléchargement, au style suisse de l'app : fond plein, encre, traits fins, coins carrés, gros
   titres en minuscules et leur point carré, rouge #FF3B1F pour ce qui compte. Les trois thèmes de l'app (Noir,
   Papier, Orange) se choisissent dans la section « à ton goût » et changent toute la page, SANS JavaScript (08/11 :
   « le changement de thème ne fonctionne pas » : l'aperçu du Finder, barre d'espace, n'exécute aucun script) : trois
   cases radio cachées et `:root:has(#t-papier:checked)`. */
:root {
  --bg: #000000; --ink: #FFFFFF; --gray: #8A8A8A; --line: #333333; --faint: #222222; --dot: #FF3B1F;
  --card: #000000; --cardInk: #FFFFFF; --btnBg: #FFFFFF; --btnInk: #000000; --btnShadow: none; --lift: #FF3B1F;
}
:root:has(#t-papier:checked) {
  --bg: #FFFFFF; --ink: #000000; --gray: #6E6E6E; --line: #CFCFCF; --faint: #E6E6E6; --dot: #FF3B1F;
  --card: #FFFFFF; --cardInk: #000000; --btnBg: #000000; --btnInk: #FFFFFF; --btnShadow: 6px 6px 0 #FF3B1F; --lift: #FF3B1F;
}
:root:has(#t-orange:checked) {
  --bg: #FF3B1F; --ink: #000000; --gray: #3A0B03; --line: #A62614; --faint: #D5341B; --dot: #FFFFFF;
  --card: #000000; --cardInk: #FFFFFF; --btnBg: #FFFFFF; --btnInk: #000000; --btnShadow: 6px 6px 0 #000000; --lift: #000000;
}
* { box-sizing: border-box; }
html { scroll-behavior: smooth; }
body {
  margin: 0; background: var(--bg); color: var(--ink);
  font: 16px/1.45 "Helvetica Neue", Helvetica, Arial, sans-serif;
  transition: background .25s, color .25s;
}
main { max-width: 980px; margin: 0 auto; padding: 0 16px 80px; }
.label { font-size: 11px; letter-spacing: 1.5px; text-transform: uppercase; color: var(--gray); font-weight: 700; }
.dot { display: inline-block; width: .19em; height: .19em; background: var(--dot); margin-left: .07em; }
h1, h2 { margin: 0; font-weight: 700; text-transform: lowercase; }
h1 { font-size: clamp(72px, 16vw, 168px); line-height: .82; letter-spacing: -.07em; }
h2 { font-size: clamp(40px, 7vw, 64px); line-height: .9; letter-spacing: -.06em; }
p { margin: 0; }
kbd {
  display: inline-flex; align-items: center; min-width: 26px; height: 26px; padding: 0 7px; justify-content: center;
  border: 2px solid var(--ink); font: 700 12px "Helvetica Neue", Helvetica, Arial, sans-serif; vertical-align: middle;
}
.btn {
  display: inline-flex; align-items: center; justify-content: center; gap: 10px; height: 48px; padding: 0 24px;
  border: 2px solid var(--ink); background: var(--btnBg); color: var(--btnInk); box-shadow: var(--btnShadow);
  font: 700 13px "Helvetica Neue", Helvetica, Arial, sans-serif; letter-spacing: 1.4px; text-transform: uppercase;
  text-decoration: none; cursor: pointer; transition: transform .12s, box-shadow .12s;
}
.btn:hover { transform: translate(-2px, -2px); }
:focus-visible { outline: 3px solid var(--dot); outline-offset: 3px; }

/* Merci : la première page, seule. */
.merci { min-height: 100vh; display: flex; flex-direction: column; justify-content: center; gap: 28px; padding: 48px 0; }
.merci p.lead { font-size: clamp(20px, 2.6vw, 28px); max-width: 30ch; letter-spacing: -.01em; }

/* Une étape : son numéro, le titre, quelques lignes ; à droite, ce qui aide. « Commencer » : le trait de l'étape
   tout en haut de l'écran. */
section.step {
  display: grid; grid-template-columns: minmax(0, 1fr) minmax(0, 1fr); gap: 40px; align-items: start;
  padding: 56px 0; border-top: 1px solid var(--line); scroll-margin-top: 0;
}
.step .head { display: flex; flex-direction: column; gap: 14px; }
.step .num { color: var(--dot); }
.step .say { font-size: 17px; }
ol.do { list-style: none; margin: 8px 0 0; padding: 0; counter-reset: n; }
ol.do li {
  counter-increment: n; position: relative; padding: 12px 0 12px 36px;
  border-top: 1px solid var(--faint); font-size: 16px;
}
ol.do li::before { content: counter(n); position: absolute; left: 0; font-weight: 700; }
.panel { background: var(--card); color: var(--cardInk); border: 1px solid var(--line); padding: 20px; }
.panel .label { color: var(--gray); }
:root:has(#t-orange:checked) .panel .label { color: #B4B4B4; }

/* Jeu : changer une touche. */
.row {
  display: flex; align-items: center; gap: 10px; min-height: 46px; padding: 0 10px; border-top: 1px solid var(--faint);
  cursor: pointer; user-select: none;
}
.row:hover, .row.listening { background: var(--cardInk); color: var(--card); }
.row span.name { flex: 1; }
.row kbd { border-color: currentColor; }
.row kbd.changed { background: #FF3B1F; border-color: #FF3B1F; color: #000; }
.row .reset { border: 0; background: none; color: inherit; font-size: 16px; font-weight: 700; cursor: pointer; visibility: hidden; }
.row.changed .reset { visibility: visible; }
.row .wait { font-size: 11px; letter-spacing: 1.2px; text-transform: uppercase; }
.row.still { cursor: default; }
.row.still:hover { background: none; color: inherit; }

/* Les trois départs d'une macro, comme l'app : noirs au repos ; au survol, pleins, soulevés sur leur ombre rouge. */
.cards { display: grid; grid-template-columns: 1fr; gap: 14px; }
.cards div {
  border: 1px solid var(--line); background: var(--card); color: var(--cardInk); padding: 16px;
  display: flex; flex-direction: column; gap: 6px; transition: transform .12s, box-shadow .12s, background .12s;
}
.cards div:hover {
  background: var(--btnBg); color: var(--btnInk); border-color: var(--btnBg);
  transform: translate(-3px, -3px); box-shadow: 4px 4px 0 var(--lift);
}
.cards b { font-size: 26px; letter-spacing: -.05em; line-height: 1; text-transform: lowercase; }
.cards small { color: var(--gray); font-size: 13px; }
.cards .n { color: var(--gray); font-weight: 700; font-size: 13px; }
.cards div:hover small { color: inherit; opacity: .7; }
.cards div:hover .n { color: #FF3B1F; opacity: 1; }

/* MIDI Settings : les 4 cases. */
.cases { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; }
.cases figure { margin: 0; border: 1px solid #333; background: #000; }
.cases img { width: 100%; display: block; }
.cases figcaption { font-size: 12px; padding: 6px 8px; color: #FFF; background: #000; }
details.full { margin-top: 12px; }
details.full summary { cursor: pointer; font-size: 12px; letter-spacing: 1.2px; text-transform: uppercase; font-weight: 700; }
details.full img { width: 100%; margin-top: 10px; border: 1px solid #333; }

/* Thèmes : trois aperçus (des étiquettes de cases radio) ; un clic change toute la page. */
.theme-pick { position: absolute; width: 1px; height: 1px; margin: -1px; padding: 0; border: 0; opacity: 0; overflow: hidden; clip: rect(0 0 0 0); }
.tiles { display: grid; grid-template-columns: repeat(3, 1fr); gap: 12px; }
.tiles label {
  display: block; border: 1px solid var(--line); background: var(--bg); color: var(--ink); padding: 6px; cursor: pointer;
  font: 700 14px "Helvetica Neue", Helvetica, Arial, sans-serif; transition: transform .12s, box-shadow .12s;
}
.tiles label:hover { transform: translate(-2px, -2px); }
:root:has(#t-noir:checked) label[for="t-noir"],
:root:has(#t-papier:checked) label[for="t-papier"],
:root:has(#t-orange:checked) label[for="t-orange"] {
  border: 2px solid var(--ink); transform: translate(-3px, -3px); box-shadow: 4px 4px 0 var(--lift);
}
:root:has(#t-noir:focus-visible) label[for="t-noir"],
:root:has(#t-papier:focus-visible) label[for="t-papier"],
:root:has(#t-orange:focus-visible) label[for="t-orange"] { outline: 3px solid var(--dot); outline-offset: 3px; }
.tiles .mini { height: 72px; display: flex; border: 1px solid #333; margin-bottom: 8px; }
.tiles .mini span:first-child { width: 32%; }
.tiles .mini span:last-child { flex: 1; position: relative; }
.tiles .mini span:last-child::after {
  content: ""; position: absolute; left: 8px; bottom: 8px; width: 10px; height: 10px; border-radius: 50%; background: #FF3B1F;
}

.three { list-style: none; margin: 0; padding: 0; }
.three li { display: grid; grid-template-columns: 36px 1fr; gap: 6px; padding: 14px 0; border-top: 1px solid var(--line); }
.three li b { display: block; font-size: 17px; letter-spacing: -.02em; }
.three li span { color: var(--gray); font-size: 14px; }
.three li em { color: var(--dot); font-style: normal; font-weight: 700; font-size: 13px; }

@media (max-width: 760px) {
  section.step { grid-template-columns: 1fr; gap: 24px; padding: 48px 0; }
  .cases { grid-template-columns: 1fr; }
}
@media (prefers-reduced-motion: reduce) {
  * { transition: none !important; scroll-behavior: auto !important; }
}
'''


def page(v, t):
    return f'''<title>{t["titre"]}</title>
<meta name="claude:viewport-fit-sides" content="cover">
<style>{CSS}</style>

<main>
  <section class="merci" aria-label="{t["merci"]}">
    <h1>{t["merci"]}<span class="dot"></span></h1>
    <p class="lead">{t["merci_lead"]}</p>
    <div><a class="btn" href="#installer">{t["commencer"]}</a></div>
  </section>

  <section class="step" id="installer">
    <div class="head">
      <span class="label num">01</span>
      <h2>{t["installe"]}<span class="dot"></span></h2>
      <ol class="do">{v["installe"]}</ol>
    </div>
  </section>

  <section class="step" id="debut">
    <div class="head">
      <span class="label num">02</span>
      <h2>{v["debut_titre"]}<span class="dot"></span></h2>
      <ol class="do">{v["debut"]}</ol>
    </div>
    <div class="panel">{v["debut_panel"]}</div>
  </section>

  <section class="step" id="touches">
    <div class="head">
      <span class="label num">03</span>
      <h2>{t["touche"]}<span class="dot"></span></h2>
      <ol class="do"><li>{t["touche_1"]}</li><li>{t["touche_2"]}</li></ol>
    </div>
    <div class="panel" aria-label="{t["touche"]}">
      <span class="label">Playlist</span>
      <div id="rows">
        <div class="row" tabindex="0" data-key="{v["espace"]}"><span class="name">{t["lecture"]}</span><button class="reset" aria-label="{t["remettre"]}">↺</button><kbd>{v["espace"]}</kbd></div>
        <div class="row" tabindex="0" data-key="C"><span class="name">{t["couper"]}</span><button class="reset" aria-label="{t["remettre"]}">↺</button><kbd>C</kbd></div>
      </div>
    </div>
  </section>

  <section class="step" id="macros">
    <div class="head">
      <span class="label num">04</span>
      <h2>macros<span class="dot"></span></h2>
      <ol class="do"><li>{t["macros_1"]}</li></ol>
    </div>
    <div class="cards">
      <div><span class="n">01</span><b>{t["carte1"]}</b><small>{t["carte1_d"]}</small></div>
      <div><span class="n">02</span><b>{t["carte2"]}</b><small>{t["carte2_d"]}</small></div>
      <div><span class="n">03</span><b>{t["carte3"]}</b><small>{t["carte3_d"]}</small></div>
    </div>
  </section>

  <section class="step" id="organiser">
    <div class="head">
      <span class="label num">05</span>
      <h2>{t["range"]}<span class="dot"></span></h2>
      <ol class="do">{"".join(f"<li>{x}</li>" for x in t["range_lignes"])}</ol>
    </div>
    <div class="panel">
      <div class="cases">
        <figure><img src="{{{{MIDI1}}}}" alt=""><figcaption>{t["case1"]}</figcaption></figure>
        <figure><img src="{{{{MIDI2}}}}" alt=""><figcaption>{t["case2"]}</figcaption></figure>
        <figure><img src="{{{{MIDI3}}}}" alt=""><figcaption>3 · Enable</figcaption></figure>
        <figure><img src="{{{{MIDI4}}}}" alt=""><figcaption>{t["case4"]}</figcaption></figure>
      </div>
      <details class="full"><summary>{t["fenetre"]}</summary><img src="{{{{MIDIFULL}}}}" alt="MIDI Settings"></details>
    </div>
  </section>

  <section class="step" id="theme">
    <div class="head">
      <span class="label num">06</span>
      <h2>{t["gout"]}<span class="dot"></span></h2>
      <p class="say">{t["gout_d"]}</p>
    </div>
    <div class="tiles" role="radiogroup" aria-label="{t["theme"]}">
      <input class="theme-pick" type="radio" name="theme" id="t-noir" checked>
      <input class="theme-pick" type="radio" name="theme" id="t-papier">
      <input class="theme-pick" type="radio" name="theme" id="t-orange">
      <label for="t-noir"><span class="mini" style="background:#000"><span style="background:#000; border-right:1px solid #333"></span><span></span></span>{t["noir"]}</label>
      <label for="t-papier"><span class="mini" style="background:#FFF"><span style="background:#FFF; border-right:1px solid #CFCFCF"></span><span></span></span>{t["papier"]}</label>
      <label for="t-orange"><span class="mini" style="background:#FF3B1F"><span style="background:#000"></span><span></span></span>Orange</label>
    </div>
  </section>

  <section class="step" id="compte">
    <div class="head">
      <span class="label num">07</span>
      <h2>{t["compte"]}<span class="dot"></span></h2>
      <p class="say">{t["compte_d"]}</p>
    </div>
    <ul class="three">
      <li><em>01</em><div><b>{t["sauvegarde"]}</b><span>{t["sauvegarde_d"]}</span></div></li>
      <li><em>02</em><div><b>{t["ordis"]}</b><span>{t["ordis_d"]}</span></div></li>
      <li><em>03</em><div><b>{t["communaute"]}</b><span>{t["communaute_d"]}</span></div></li>
    </ul>
  </section>
</main>

<script>
(function () {{
  // Les thèmes n'ont pas besoin de script (cases radio et :has, plus haut) : l'aperçu du Finder les change aussi.
  // Jeu : un clic sur une ligne, puis une touche ; ↺ la remet. Échap annule.
  var listening = null;
  function names(e) {{
    var k = e.key;
    if (k === " ") k = "{v["espace"]}";
    else if (k.length === 1) k = k.toUpperCase();
    var mods = [];
    if (e.ctrlKey) mods.push("{v["ctrl"]}");
    if (e.altKey) mods.push("{v["alt"]}");
    if (e.shiftKey) mods.push("{v["shift"]}");
    if (e.metaKey) mods.push("{v["meta"]}");
    return mods.concat([k]);
  }}
  function show(row, keys, changed) {{
    row.querySelectorAll("kbd, .wait").forEach(function (n) {{ n.remove(); }});
    keys.forEach(function (k) {{
      var kb = document.createElement("kbd");
      kb.textContent = k;
      if (changed) kb.className = "changed";
      row.appendChild(kb);
    }});
    row.classList.toggle("changed", changed);
  }}
  document.querySelectorAll("#rows .row").forEach(function (row) {{
    function listen() {{
      if (listening) listening.classList.remove("listening");
      listening = row;
      row.classList.add("listening");
      row.querySelectorAll("kbd").forEach(function (n) {{ n.remove(); }});
      var w = document.createElement("span");
      w.className = "wait";
      w.textContent = "{t["attente"]}";
      row.appendChild(w);
    }}
    row.addEventListener("click", function (e) {{ if (!e.target.classList.contains("reset")) listen(); }});
    row.addEventListener("keydown", function (e) {{ if (!listening && e.key === "Enter") {{ e.preventDefault(); listen(); }} }});
    row.querySelector(".reset").addEventListener("click", function (e) {{
      e.stopPropagation();
      show(row, [row.getAttribute("data-key")], false);
    }});
  }});
  document.addEventListener("keydown", function (e) {{
    if (!listening) return;
    if (["Shift", "Control", "Alt", "Meta"].indexOf(e.key) >= 0) return;
    e.preventDefault();
    var row = listening;
    listening = null;
    row.classList.remove("listening");
    if (e.key === "Escape") {{ show(row, [row.getAttribute("data-key")], false); return; }}
    var keys = names(e);
    show(row, keys, keys.join("") !== row.getAttribute("data-key"));
  }});
}})();
</script>
'''


FR = {
    "titre": "Lisez-moi FL Shortcuts",
    "merci": "merci", "merci_lead": "Merci d'avoir choisi la rapidité.", "commencer": "Commencer",
    "installe": "installe",
    "touche": "change une touche", "touche_1": "Clique sur un raccourci.", "touche_2": "Appuie sur ta touche.",
    "lecture": "Lecture / Stop", "couper": "Couper", "remettre": "Remettre", "attente": "Appuie sur une touche…",
    "macros_1": "Clique sur Macros.",
    "carte1": "enregistrer une macro", "carte1_d": "Fais-le dans FL, l'app le retient.",
    "carte2": "macro vide", "carte2_d": "Pose les blocs un par un.",
    "carte3": "modèles", "carte3_d": "Pars d'une macro toute prête.",
    "range": "range ton projet",
    "range_lignes": ["Ouvre ton projet dans FL.", "Icône › Organiser.", "Suis les consignes.",
                     "Options › MIDI Settings : les 4 cases.", "Organiser."],
    "case1": "1 · Port de sortie", "case2": "2 · Même Port en entrée", "case4": "4 · Controller type : FL Shortcuts",
    "fenetre": "Voir toute la fenêtre",
    "gout": "à ton goût", "gout_d": "Trois thèmes : Noir, Papier, Orange. Dans Mon compte.", "theme": "Thème",
    "noir": "Noir", "papier": "Papier",
    "compte": "ton compte", "compte_d": "Dans Mon compte.",
    "sauvegarde": "Sauvegarde", "sauvegarde_d": "Tes raccourcis et tes macros, en ligne.",
    "ordis": "Tous tes ordis", "ordis_d": "Les mêmes sur ton Mac et ton PC.",
    "communaute": "Communauté", "communaute_d": "Partage et récupère des macros.",
}
EN = {
    "titre": "FL Shortcuts README",
    "merci": "thanks", "merci_lead": "Thanks for choosing speed.", "commencer": "Get started",
    "installe": "install",
    "touche": "change a key", "touche_1": "Click a shortcut.", "touche_2": "Press your key.",
    "lecture": "Play / Stop", "couper": "Cut", "remettre": "Reset", "attente": "Press a key…",
    "macros_1": "Click Macros.",
    "carte1": "record a macro", "carte1_d": "Do it in FL, the app remembers it.",
    "carte2": "empty macro", "carte2_d": "Place the blocks one by one.",
    "carte3": "templates", "carte3_d": "Start from a ready-made macro.",
    "range": "organize your project",
    "range_lignes": ["Open your project in FL.", "Icon › Organize.", "Follow the instructions.",
                     "Options › MIDI Settings: the 4 boxes.", "Organize."],
    "case1": "1 · Output port", "case2": "2 · Same port as input", "case4": "4 · Controller type: FL Shortcuts",
    "fenetre": "See the whole window",
    "gout": "your way", "gout_d": "Three themes: Black, Paper, Orange. In My account.", "theme": "Theme",
    "noir": "Black", "papier": "Paper",
    "compte": "your account", "compte_d": "In My account.",
    "sauvegarde": "Backup", "sauvegarde_d": "Your shortcuts and macros, online.",
    "ordis": "All your computers", "ordis_d": "The same on your Mac and your PC.",
    "communaute": "Community", "communaute_d": "Share and get macros.",
}


def accueil(titre, lignes):
    """Panneau de l'étape 02 : des lignes « nom · état », comme l'accueil de l'app (ou loopMIDI)."""
    rows = "".join(f'<div class="row still"><span class="name"><b>{n}</b></span>{etat}</div>' for n, etat in lignes)
    return f'<span class="label">{titre}</span>{rows}'


OK = '<kbd style="border-color:currentColor">{}</kbd>'
A_FAIRE = '<kbd class="changed">{}</kbd>'

mac = {
    "fr": {
        "installe": "<li>Ouvre <b>FLShortcuts.pkg</b>.</li>"
                    "<li>Bloqué ? Réglages Système › Confidentialité et sécurité › <b>Ouvrir quand même</b>.</li>",
        "debut_titre": "autorise",
        "debut": "<li>Ouvre FL Shortcuts.</li><li>Autorise le <b>Clavier</b>, puis le <b>Son de FL</b>.</li>",
        "debut_panel": accueil("Accueil", [("Clavier", OK.format("Autorisé")), ("Son de FL", A_FAIRE.format("À autoriser"))]),
        "espace": "Espace", "ctrl": "⌃", "alt": "⌥", "shift": "⇧", "meta": "⌘",
    },
    "en": {
        "installe": "<li>Open <b>FLShortcuts.pkg</b>.</li>"
                    "<li>Blocked? System Settings › Privacy &amp; Security › <b>Open Anyway</b>.</li>",
        "debut_titre": "allow",
        "debut": "<li>Open FL Shortcuts.</li><li>Allow <b>Keyboard</b>, then <b>FL sound</b>.</li>",
        "debut_panel": accueil("Welcome", [("Keyboard", OK.format("Allowed")), ("FL sound", A_FAIRE.format("To allow"))]),
        "espace": "Space", "ctrl": "⌃", "alt": "⌥", "shift": "⇧", "meta": "⌘",
    },
}
win = {
    "fr": {
        "installe": "<li>Lance <b>FLShortcuts-Windows-Setup.exe</b>.</li>"
                    "<li>Bloqué ? Informations complémentaires › <b>Exécuter quand même</b>.</li>"
                    "<li>Ton antivirus râle ? Autorise FL Shortcuts : il n'y a aucun virus.</li>"
                    "<li>Installe aussi <b>loopMIDI</b>, puis ferme-le : rien à faire dedans.</li>",
        "debut_titre": "deux ports midi",
        "debut": "<li>Ouvre <b>FL Shortcuts</b>, puis FL Studio.</li><li>Les ports MIDI se créent tout seuls.</li>",
        "debut_panel": accueil("loopMIDI", [("FL Shortcuts", OK.format("Prêt")), ("FL Shortcuts Retour", OK.format("Prêt"))]),
        "espace": "Espace", "ctrl": "Ctrl", "alt": "Alt", "shift": "Maj", "meta": "Win",
    },
    "en": {
        "installe": "<li>Run <b>FLShortcuts-Windows-Setup.exe</b>.</li>"
                    "<li>Blocked? More info › <b>Run anyway</b>.</li>"
                    "<li>Antivirus complaining? Allow FL Shortcuts: there is no virus.</li>"
                    "<li>Also install <b>loopMIDI</b>, then close it: nothing to do in it.</li>",
        "debut_titre": "two midi ports",
        "debut": "<li>Open <b>FL Shortcuts</b>, then FL Studio.</li><li>The MIDI ports create themselves.</li>",
        "debut_panel": accueil("loopMIDI", [("FL Shortcuts", OK.format("Ready")), ("FL Shortcuts Retour", OK.format("Ready"))]),
        "espace": "Space", "ctrl": "Ctrl", "alt": "Alt", "shift": "Shift", "meta": "Win",
    },
}

for nom, v in (("mac", mac), ("windows", win)):
    open(f"{DOSSIER}/modele-{nom}.html", "w", encoding="utf-8").write(page(v["fr"], FR))
    open(f"{DOSSIER}/modele-{nom}-en.html", "w", encoding="utf-8").write(page(v["en"], EN))
print("ok")
