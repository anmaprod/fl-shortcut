#!/usr/bin/env python3
# Fabrique docs/telechargement/modele-mac.html et modele-windows.html (05/11) : une page de remerciement, puis les
# étapes, au style suisse de l'app, avec de petits jeux (changer une touche, ranger un projet, changer de thème).
# Usage : python3 scripts/lisezmoi_modeles.py docs/telechargement, puis python3 scripts/lisezmoi.py (images collées).
import sys
DOSSIER = sys.argv[1] if len(sys.argv) > 1 else "docs/telechargement"

CSS = r'''
/* Mode d'emploi du téléchargement (LISEZMOI.html, 05/11 : « une page de remerciement… un peu interactif… rapide »),
   au style suisse de l'app : fond plein, encre, traits fins, coins carrés, gros titres en minuscules et leur point
   carré, rouge #FF3B1F pour ce qui compte. Les trois thèmes de l'app (Noir, Papier, Orange) se choisissent en haut. */
:root, :root[data-theme="noir"] {
  --bg: #000000; --ink: #FFFFFF; --gray: #8A8A8A; --line: #333333; --faint: #222222; --dot: #FF3B1F;
  --card: #000000; --cardInk: #FFFFFF; --btnBg: #FFFFFF; --btnInk: #000000; --btnShadow: none; --chosen: #FFFFFF;
}
:root[data-theme="papier"] {
  --bg: #FFFFFF; --ink: #000000; --gray: #6E6E6E; --line: #CFCFCF; --faint: #E6E6E6; --dot: #FF3B1F;
  --card: #FFFFFF; --cardInk: #000000; --btnBg: #000000; --btnInk: #FFFFFF; --btnShadow: 6px 6px 0 #FF3B1F; --chosen: #000000;
}
:root[data-theme="orange"] {
  --bg: #FF3B1F; --ink: #000000; --gray: #3A0B03; --line: #A62614; --faint: #D5341B; --dot: #FFFFFF;
  --card: #000000; --cardInk: #FFFFFF; --btnBg: #FFFFFF; --btnInk: #000000; --btnShadow: 6px 6px 0 #000000; --chosen: #000000;
}
* { box-sizing: border-box; }
html { scroll-behavior: smooth; }
body {
  margin: 0; background: var(--bg); color: var(--ink);
  font: 16px/1.45 "Helvetica Neue", Helvetica, Arial, sans-serif;
  transition: background .25s, color .25s;
}
main { max-width: 980px; margin: 0 auto; padding: 0 16px 64px; }
.label { font-size: 11px; letter-spacing: 1.5px; text-transform: uppercase; color: var(--gray); font-weight: 700; }
.dot { display: inline-block; width: .19em; height: .19em; background: var(--dot); margin-left: .07em; }
h1, h2 { margin: 0; font-weight: 700; text-transform: lowercase; }
h1 { font-size: clamp(72px, 16vw, 168px); line-height: .82; letter-spacing: -.07em; }
h2 { font-size: clamp(40px, 7vw, 64px); line-height: .9; letter-spacing: -.06em; }
p { margin: 0; }
a { color: inherit; }
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
.btn.soft { background: var(--bg); color: var(--ink); box-shadow: none; }
.btn.soft:hover { background: var(--ink); color: var(--bg); transform: none; }
:focus-visible { outline: 3px solid var(--dot); outline-offset: 3px; }

/* Barre du haut : le nom et le choix du thème. */
.bar {
  position: sticky; top: 0; z-index: 5; display: flex; align-items: center; gap: 12px; padding: 12px 16px;
  background: var(--bg); border-bottom: 1px solid var(--line); transition: background .25s;
}
.bar b { font-size: 15px; letter-spacing: -.03em; }
.themes { margin-left: auto; display: flex; }
.themes button {
  height: 32px; padding: 0 12px; margin-left: -2px; border: 2px solid var(--ink); background: var(--bg); color: var(--ink);
  font: 700 10.5px "Helvetica Neue", Helvetica, Arial, sans-serif; letter-spacing: 1.2px; text-transform: uppercase; cursor: pointer;
}
.themes button[aria-pressed="true"] { background: var(--ink); color: var(--bg); }

/* Merci : la première page. */
.merci { min-height: calc(100vh - 57px); display: flex; flex-direction: column; justify-content: center; gap: 28px; padding: 48px 0; }
.merci .icone { width: 84px; height: 84px; }
.merci p.lead { font-size: clamp(18px, 2.4vw, 24px); max-width: 30ch; letter-spacing: -.01em; }
.merci .actions { display: flex; flex-wrap: wrap; align-items: center; gap: 18px; }
.merci .actions span { color: var(--gray); font-size: 14px; }

/* Une étape : son numéro, le titre, trois lignes au plus ; à droite, de quoi essayer. */
section.step {
  display: grid; grid-template-columns: minmax(0, 1fr) minmax(0, 1fr); gap: 40px; align-items: start;
  padding: 64px 0; border-top: 1px solid var(--line);
}
.step .head { display: flex; flex-direction: column; gap: 14px; }
.step .num { color: var(--dot); }
ol.do { list-style: none; margin: 8px 0 0; padding: 0; counter-reset: n; }
ol.do li {
  counter-increment: n; position: relative; padding: 12px 0 12px 36px;
  border-top: 1px solid var(--faint); font-size: 16px;
}
ol.do li::before { content: counter(n); position: absolute; left: 0; font-weight: 700; }
.note { color: var(--gray); font-size: 14px; }
.panel { background: var(--card); color: var(--cardInk); border: 1px solid var(--line); padding: 20px; }
.panel .label { color: var(--gray); }
:root[data-theme="orange"] .panel .label { color: #B4B4B4; }

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

/* Jeu : ranger un projet. */
.mess { display: flex; flex-direction: column; gap: 6px; min-height: 290px; }
.sound {
  display: flex; align-items: center; gap: 10px; height: 34px; padding: 0 10px; border: 1px solid #333;
  font-size: 14px; transition: transform .35s ease, opacity .35s;
}
.sound i { width: 12px; height: 12px; display: inline-block; }
.family { font-size: 11px; letter-spacing: 1.4px; text-transform: uppercase; font-weight: 700; padding: 8px 0 2px; border-top: 3px solid; }

/* Les trois départs d'une macro, comme l'app. */
.cards { display: grid; grid-template-columns: 1fr; gap: 14px; }
.cards div {
  border: 1px solid var(--line); background: var(--card); color: var(--cardInk); padding: 16px; display: flex; flex-direction: column; gap: 6px;
  transition: transform .12s, box-shadow .12s;
}
.cards div:hover { transform: translate(-3px, -3px); box-shadow: 3px 3px 0 #FF3B1F; border-color: var(--ink); }
.cards b { font-size: 26px; letter-spacing: -.05em; line-height: 1; text-transform: lowercase; }
.cards small { color: var(--gray); font-size: 13px; }
.cards .n { color: var(--gray); font-weight: 700; font-size: 13px; }
.cards div:first-child { background: var(--btnBg); color: var(--btnInk); box-shadow: var(--btnShadow); border-color: var(--ink); }
.cards div:first-child small, .cards div:first-child .n { color: inherit; opacity: .75; }

/* MIDI Settings : les 4 cases. */
.cases { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; margin-top: 14px; }
.cases figure { margin: 0; border: 1px solid var(--line); background: #000; }
.cases img { width: 100%; display: block; }
.cases figcaption { font-size: 12px; padding: 6px 8px; color: #FFF; background: #000; }
details.full { margin-top: 10px; }
details.full summary { cursor: pointer; font-size: 12px; letter-spacing: 1.2px; text-transform: uppercase; font-weight: 700; }
details.full img { width: 100%; margin-top: 10px; border: 1px solid var(--line); }

/* Thèmes : trois aperçus. */
.tiles { display: grid; grid-template-columns: repeat(3, 1fr); gap: 12px; }
.tiles button { border: 1px solid var(--line); background: var(--bg); color: var(--ink); padding: 6px; cursor: pointer; text-align: left; font: 700 14px "Helvetica Neue", Helvetica, Arial, sans-serif; }
.tiles button[aria-pressed="true"] { border: 2px solid var(--ink); transform: translate(-3px, -3px); box-shadow: 4px 4px 0 #FF3B1F; }
.tiles .mini { height: 64px; display: flex; border: 1px solid #333; margin-bottom: 8px; }
.tiles .mini span:first-child { width: 32%; }
.tiles .mini span:last-child { flex: 1; position: relative; }
.tiles .mini span:last-child::after { content: ""; position: absolute; left: 8px; bottom: 8px; width: 10px; height: 10px; border-radius: 50%; background: #FF3B1F; }

.three { list-style: none; margin: 0; padding: 0; }
.three li { display: grid; grid-template-columns: 36px 1fr; gap: 6px; padding: 14px 0; border-top: 1px solid var(--line); }
.three li b { display: block; font-size: 17px; letter-spacing: -.02em; }
.three li span { color: var(--gray); font-size: 14px; }
.three li em { color: var(--dot); font-style: normal; font-weight: 700; font-size: 13px; }

footer { border-top: 1px solid var(--line); padding: 48px 0 0; display: flex; flex-wrap: wrap; gap: 18px; align-items: end; justify-content: space-between; }
footer h2 { font-size: clamp(36px, 6vw, 56px); }
footer p { color: var(--gray); font-size: 14px; max-width: 40ch; }

@media (max-width: 760px) {
  section.step { grid-template-columns: 1fr; gap: 24px; padding: 48px 0; }
  .tiles { grid-template-columns: 1fr 1fr 1fr; }
  .cases { grid-template-columns: 1fr; }
}
@media (prefers-reduced-motion: reduce) {
  * { transition: none !important; scroll-behavior: auto !important; }
}
'''

def page(v):
    return f'''<title>Lisez-moi FL Shortcuts</title>
<meta name="claude:viewport-fit-sides" content="cover">
<style>{CSS}</style>

<div class="bar">
  <b>fl shortcuts<span class="dot"></span></b>
  <div class="themes" role="group" aria-label="Thème">
    <button type="button" data-set="noir" aria-pressed="true">Noir</button>
    <button type="button" data-set="papier" aria-pressed="false">Papier</button>
    <button type="button" data-set="orange" aria-pressed="false">Orange</button>
  </div>
</div>

<main>
  <section class="merci" aria-label="Merci">
    <img class="icone" src="{{{{ICON}}}}" alt="">
    <span class="label">{v["systeme"]}</span>
    <h1>merci<span class="dot"></span></h1>
    <p class="lead">Merci d'essayer FL Shortcuts. Tes raccourcis, tes macros et ton projet rangé, dans FL Studio.</p>
    <div class="actions">
      <a class="btn" href="#installer">Commencer</a>
      <span>Trois minutes, pas plus.</span>
    </div>
  </section>

  <section class="step" id="installer">
    <div class="head">
      <span class="label num">01</span>
      <h2>installe<span class="dot"></span></h2>
      <ol class="do">{v["installe"]}</ol>
    </div>
    <div class="panel">{v["installe_panel"]}</div>
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
      <h2>change une touche<span class="dot"></span></h2>
      <ol class="do">
        <li>Choisis une page de FL, à gauche.</li>
        <li>Clique sur un raccourci.</li>
        <li>Appuie sur ta touche. C'est tout.</li>
      </ol>
      <p class="note">Essaie à droite.</p>
    </div>
    <div class="panel" aria-label="Essai : change une touche">
      <span class="label">Playlist</span>
      <div id="rows">
        <div class="row" tabindex="0" data-key="{v["espace"]}"><span class="name">Lecture / Stop</span><button class="reset" aria-label="Remettre">↺</button><kbd>{v["espace"]}</kbd></div>
        <div class="row" tabindex="0" data-key="C"><span class="name">Couper</span><button class="reset" aria-label="Remettre">↺</button><kbd>C</kbd></div>
        <div class="row" tabindex="0" data-key="P"><span class="name">Dessin</span><button class="reset" aria-label="Remettre">↺</button><kbd>P</kbd></div>
      </div>
    </div>
  </section>

  <section class="step" id="macros">
    <div class="head">
      <span class="label num">04</span>
      <h2>macros<span class="dot"></span></h2>
      <p class="note" style="font-size:16px; color: inherit">Fais-le une fois dans FL : l'app le refait d'une touche.</p>
      <ol class="do">
        <li>Icône › Macros.</li>
        <li>Enregistre, ou pose les blocs un par un.</li>
        <li>Donne-lui une touche, ou un bouton de ta souris.</li>
      </ol>
    </div>
    <div class="cards" aria-label="Les trois façons de commencer">
      <div><span class="n">01</span><b>enregistrer une macro</b><small>Fais-le dans FL, l'app le retient.</small></div>
      <div><span class="n">02</span><b>macro vide</b><small>Pose les blocs un par un.</small></div>
      <div><span class="n">03</span><b>modèles</b><small>Pars d'une macro toute prête.</small></div>
    </div>
  </section>

  <section class="step" id="organiser">
    <div class="head">
      <span class="label num">05</span>
      <h2>range ton projet<span class="dot"></span></h2>
      <ol class="do">
        <li>Ouvre ton projet dans FL.</li>
        <li>Icône › Organiser.</li>
        <li>La première fois : installe le lien, puis {v["quitte"]} et rouvre FL.</li>
        <li>Options › MIDI Settings : les 4 cases ci-dessous.</li>
        <li>Organiser. L'ancienne version part à la Corbeille si tu valides.</li>
      </ol>
      <div class="cases">
        <figure><img src="{{{{MIDI1}}}}" alt=""><figcaption>1 · Port de sortie</figcaption></figure>
        <figure><img src="{{{{MIDI2}}}}" alt=""><figcaption>2 · Même Port en entrée</figcaption></figure>
        <figure><img src="{{{{MIDI3}}}}" alt=""><figcaption>3 · Enable</figcaption></figure>
        <figure><img src="{{{{MIDI4}}}}" alt=""><figcaption>4 · Controller type : FL Shortcuts</figcaption></figure>
      </div>
      <details class="full"><summary>Voir toute la fenêtre</summary><img src="{{{{MIDIFULL}}}}" alt="La fenêtre MIDI Settings de FL, les 4 cases entourées"></details>
    </div>
    <div class="panel" aria-label="Essai : ranger un projet">
      <div style="display:flex; align-items:center; justify-content:space-between; margin-bottom:12px">
        <span class="label">Ton projet</span>
        <button class="btn" id="ranger" style="height:38px; padding:0 16px">Organiser</button>
      </div>
      <div class="mess" id="mess"></div>
    </div>
  </section>

  <section class="step" id="theme">
    <div class="head">
      <span class="label num">06</span>
      <h2>à ton goût<span class="dot"></span></h2>
      <p class="note" style="font-size:16px; color: inherit">Trois thèmes : Noir, Papier, Orange. Dans Mon compte.</p>
      <p class="note">Clique : cette page change aussi.</p>
    </div>
    <div class="tiles" role="group" aria-label="Thème">
      <button type="button" data-set="noir" aria-pressed="true"><span class="mini" style="background:#000"><span style="background:#000; border-right:1px solid #333"></span><span></span></span>Noir</button>
      <button type="button" data-set="papier" aria-pressed="false"><span class="mini" style="background:#FFF"><span style="background:#FFF; border-right:1px solid #CFCFCF"></span><span></span></span>Papier</button>
      <button type="button" data-set="orange" aria-pressed="false"><span class="mini" style="background:#FF3B1F"><span style="background:#000"></span><span></span></span>Orange</button>
    </div>
  </section>

  <section class="step" id="partout">
    <div class="head">
      <span class="label num">07</span>
      <h2>un compte, partout<span class="dot"></span></h2>
      <p class="note">Gratuit. Dans Mon compte.</p>
    </div>
    <ul class="three">
      <li><em>01</em><div><b>Sauvegarde</b><span>Tes raccourcis et tes macros, en ligne.</span></div></li>
      <li><em>02</em><div><b>Tous tes ordis</b><span>Les mêmes sur ton Mac et ton PC.</span></div></li>
      <li><em>03</em><div><b>Communauté</b><span>Partage et récupère des macros.</span></div></li>
    </ul>
  </section>

  <footer>
    <h2>bon son<span class="dot"></span></h2>
    <p>Une question, un souci : Aide › Écrire à l'équipe, dans l'app. On te répond.</p>
  </footer>
</main>

<script>
(function () {{
  // Thème : la barre du haut et la section 06 changent toute la page.
  function theme(name) {{
    document.documentElement.setAttribute("data-theme", name);
    document.querySelectorAll("[data-set]").forEach(function (b) {{
      b.setAttribute("aria-pressed", b.getAttribute("data-set") === name ? "true" : "false");
    }});
  }}
  document.querySelectorAll("[data-set]").forEach(function (b) {{
    b.addEventListener("click", function () {{ theme(b.getAttribute("data-set")); }});
  }});

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
      w.textContent = "Appuie sur une touche…";
      row.appendChild(w);
    }}
    row.addEventListener("click", function (e) {{ if (!e.target.classList.contains("reset")) listen(); }});
    row.addEventListener("keydown", function (e) {{ if (!listening && (e.key === "Enter")) {{ e.preventDefault(); listen(); }} }});
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

  // Jeu : un projet en vrac, « Organiser » le range par familles, à leurs couleurs.
  var sons = [["Audio Clip 4", "Voix"], ["Kick 1", "Drums"], ["Pad 3", "Mélodies"], ["808 long", "Basse"],
              ["riser", "FX"], ["snare_02", "Drums"], ["ZENOLOGY", "Mélodies"], ["Hat loop", "Drums"]];
  var couleurs = {{ "Drums": "#FF3B1F", "Basse": "#2F55FF", "Mélodies": "#FFC400", "Voix": "#FF5FA2", "FX": "#19C3A0" }};
  var ordre = ["Drums", "Basse", "Mélodies", "Voix", "FX"];
  var mess = document.getElementById("mess");
  var range = false;
  function draw() {{
    mess.innerHTML = "";
    if (!range) {{
      sons.forEach(function (s) {{
        var d = document.createElement("div");
        d.className = "sound";
        d.innerHTML = "<i style='background:#555'></i>" + s[0];
        mess.appendChild(d);
      }});
      return;
    }}
    ordre.forEach(function (f) {{
      var h = document.createElement("div");
      h.className = "family";
      h.style.borderColor = couleurs[f];
      h.textContent = f;
      mess.appendChild(h);
      sons.filter(function (s) {{ return s[1] === f; }}).forEach(function (s, i) {{
        var d = document.createElement("div");
        d.className = "sound";
        d.style.opacity = "0";
        d.style.transform = "translateX(-12px)";
        d.innerHTML = "<i style='background:" + couleurs[f] + "'></i>" + s[0];
        mess.appendChild(d);
        setTimeout(function () {{ d.style.opacity = "1"; d.style.transform = "none"; }}, 60 + i * 60);
      }});
    }});
  }}
  draw();
  var ranger = document.getElementById("ranger");
  ranger.addEventListener("click", function () {{
    range = !range;
    ranger.textContent = range ? "Revenir comme avant" : "Organiser";
    draw();
  }});
}})();
</script>
'''

mac = {
  "systeme": "Pour Mac",
  "installe": "<li>Ouvre <b>FLShortcuts.pkg</b>.</li><li>macOS le bloque ? Réglages Système › Confidentialité et sécurité › <b>Ouvrir quand même</b>.</li><li>Suis l'installation jusqu'au bout.</li>",
  "installe_panel": '<span class="label">Le paquet</span><div style="display:flex; align-items:center; gap:18px; margin-top:14px"><img src="{{PKG}}" alt="" style="width:72px; height:72px; background:#000; padding:6px"><div><b style="font-size:18px">FLShortcuts.pkg</b><p class="note">Pas encore signé par Apple : c\'est normal.</p></div></div>',
  "debut_titre": "autorise",
  "debut": "<li>Ouvre FL Shortcuts, dans Applications.</li><li>Clavier : <b>Autoriser</b>.</li><li>Son de FL : <b>Autoriser</b>.</li>",
  "debut_panel": '<span class="label">Accueil</span><div class="row" style="cursor:default"><span class="name"><b>Clavier</b><br><span class="note">Pour tes raccourcis dans FL.</span></span><kbd style="border-color:currentColor">Autorisé</kbd></div><div class="row" style="cursor:default"><span class="name"><b>Son de FL</b><br><span class="note">Pour écouter tes sons.</span></span><kbd class="changed">À autoriser</kbd></div><p class="note" style="margin-top:12px">Ensuite, un rond blanc en haut de l\'écran : tout est là.</p>',
  "espace": "Espace", "ctrl": "⌃", "alt": "⌥", "shift": "⇧", "meta": "⌘",
  "quitte": "quitte (⌘Q)",
}
win = {
  "systeme": "Pour Windows",
  "installe": "<li>Lance <b>FLShortcuts-Windows-Setup.exe</b>.</li><li>« Windows a protégé votre ordinateur » ? Informations complémentaires › <b>Exécuter quand même</b>.</li><li>Suis l'installation : l'icône arrive près de l'heure.</li>",
  "installe_panel": '<span class="label">Microsoft Defender SmartScreen</span><p style="margin-top:10px; font-size:18px; font-weight:700">Windows a protégé votre ordinateur</p><p class="note">L\'application n\'est pas encore reconnue : c\'est normal.</p><p style="margin-top:12px"><u>Informations complémentaires</u> › <b>Exécuter quand même</b></p>',
  "debut_titre": "deux ports midi",
  "debut": "<li>Installe <b>loopMIDI</b>.</li><li>Crée « FL Shortcuts » et « FL Shortcuts Retour ».</li><li>Laisse-le ouvert.</li>",
  "debut_panel": '<span class="label">loopMIDI</span><div class="row" style="cursor:default"><span class="name"><b>FL Shortcuts</b></span><kbd style="border-color:currentColor">Prêt</kbd></div><div class="row" style="cursor:default"><span class="name"><b>FL Shortcuts Retour</b></span><kbd style="border-color:currentColor">Prêt</kbd></div><p class="note" style="margin-top:12px">Ensuite, l\'icône près de l\'heure : tout est là. Cachée ? Sous la petite flèche ^.</p>',
  "espace": "Espace", "ctrl": "Ctrl", "alt": "Alt", "shift": "Maj", "meta": "Win",
  "quitte": "ferme",
}
for nom, v in (("mac", mac), ("windows", win)):
    open(f"{DOSSIER}/modele-{nom}.html", "w", encoding="utf-8").write(page(v))
print("ok")
