# Traduction anglaise des modes d'emploi (README-Mac.html, README-Windows.html), demandée le 02/11 : exactement les
# mêmes pages que les LISEZMOI, en anglais. Chaque texte des modèles français est remplacé tel quel ; les mots de
# l'app sont ceux de sa version anglaise (Resources/en.lproj), ceux de macOS et de Windows ceux de leurs versions
# anglaises. Un texte oublié arrête scripts/lisezmoi.py (voir `reste_du_francais`).
import re

TITRES = {
    "Lisez-moi FL Shortcuts": "FL Shortcuts README",
    "Lisez-moi FL Shortcuts Windows": "FL Shortcuts Windows README",
}

TEXTES = {
    # En-tête et sommaire
    "Tes raccourcis, tes macros, l'Organiser et la Communauté pour FL Studio. Six étapes, dans l'ordre.":
        "Your shortcuts, your macros, Organize and the Community for FL Studio. Six steps, in order.",
    "Tes raccourcis, tes macros, l'Organiser et la Communauté pour FL Studio. Quatre étapes, dans l'ordre.":
        "Your shortcuts, your macros, Organize and the Community for FL Studio. Four steps, in order.",
    "Mode d'emploi · Mac · macOS 13 ou plus récent": "User guide · Mac · macOS 13 or later",
    "Mode d'emploi · Windows 10 ou 11 ·": "User guide · Windows 10 or 11 ·",
    "version en cours": "work in progress",
    "Étapes": "Steps",
    "Installer": "Install",
    "Premier lancement": "First launch",
    "Autorisations": "Permissions",
    "Tous les jours": "Every day",
    "Organiser": "Organize",
    "Communauté": "Community",
    "Étape 01": "Step 01", "Étape 02": "Step 02", "Étape 03": "Step 03", "Étape 04": "Step 04",
    "Étape 05": "Step 05", "Étape 06": "Step 06",
    "Étape 04 · bientôt sur Windows": "Step 04 · coming to Windows",
    # 1. Installer (Mac)
    "Ouvre": "Open",
    "macOS dit qu'il ne peut pas vérifier le paquet : c'est normal, il n'est pas encore signé par Apple. Clique":
        "macOS says it can't verify the package: that's normal, it isn't signed by Apple yet. Click",
    "Terminé": "Done",
    "Réglages Système ›": "System Settings ›",
    "Confidentialité et sécurité": "Privacy & Security",
    "Ouvrir quand même": "Open Anyway",
    ", puis suis l'installation jusqu'au bout.": ", then follow the installer to the end.",
    "macOS ne peut pas vérifier FLShortcuts.pkg": "macOS can't verify FLShortcuts.pkg",
    "« FLShortcuts.pkg » n'a pas été ouvert": "“FLShortcuts.pkg” Not Opened",
    "Apple ne peut pas vérifier qu'il est exempt de logiciels malveillants.":
        "Apple could not verify it is free of malware.",
    "Placer dans la Corbeille": "Move to Trash",
    "Réglages Système, Confidentialité et sécurité, Ouvrir quand même":
        "System Settings, Privacy & Security, Open Anyway",
    "Sécurité": "Security",
    "« FLShortcuts.pkg » a été bloqué pour protéger ton Mac.": "“FLShortcuts.pkg” was blocked to protect your Mac.",
    # 2. Premier lancement
    "Ouvre le dossier": "Open the",
    "Applications": "Applications",
    "Clic droit sur": "Right-click",
    "Ouvrir": "Open",
    "Son icône, un petit clavier, arrive en haut de l'écran.": "Its icon, a small keyboard, appears at the top of the screen.",
    "Dans Applications, clic droit sur FL Shortcuts, puis Ouvrir": "In Applications, right-click FL Shortcuts, then Open",
    "Afficher le contenu du paquet": "Show Package Contents",
    "Lire les informations": "Get Info",
    # 3. Autorisations
    "Clavier": "Keyboard",
    ": clique « Tout autoriser… », coche FL Shortcuts, puis ton mot de passe ou Touch ID.":
        ": click “Allow all…”, turn on FL Shortcuts, then your password or Touch ID.",
    "Son de FL": "FL sound",
    ": coche FL Shortcuts dans": ": turn on FL Shortcuts in",
    "Enregistrement de l'écran et audio du système": "Screen & System Audio Recording",
    "(la liste du haut), puis": "(the top list), then",
    "Quitter et rouvrir": "Quit & Reopen",
    "L'accueil de FL Shortcuts : Clavier autorisé, Son de FL à autoriser":
        "FL Shortcuts' welcome window: Keyboard allowed, FL sound to allow",
    "Autorisé": "Allowed",
    "À autoriser": "To allow",
    "Plus tard": "Later",
    "Tout autoriser…": "Allow all…",
    # 4. Tous les jours
    "Tes raccourcis fonctionnent quand": "Your shortcuts work when",
    "est ouvert.": "is open.",
    "Tout le reste est dans l'": "Everything else is in the ",
    "icône": "icon",
    "en haut de l'écran : raccourcis, macros, Organiser.": "at the top of the screen: shortcuts, macros, Organize.",
    "Pour chercher un raccourci : la barre en haut à gauche de la fenêtre. L'icône clavier cherche avec les touches que tu connais.":
        "To find a shortcut: the bar at the top left of the window. The keyboard icon searches with the keys you know.",
    "Le menu de l'icône de FL Shortcuts dans la barre des menus": "The FL Shortcuts icon menu in the menu bar",
    "lun. 2 nov. 10:42": "Mon Nov 2 10:42",
    "Modifier les raccourcis…": "Edit shortcuts…",
    "Organiser…": "Organize…",
    "Désinstaller FL Shortcuts…": "Uninstall FL Shortcuts…",
    "Ouvrir FL Shortcuts": "Open FL Shortcuts",
    "Quitter ⌘Q": "Quit ⌘Q",
    "La barre de recherche et son icône clavier": "The search bar and its keyboard icon",
    "Rechercher": "Search",
    # 5. Organiser
    "Ouvre ton projet dans FL, puis icône ›": "Open your project in FL, then icon ›",
    "Ouvre ton projet dans FL, puis l'icône près de l'heure ›": "Open your project in FL, then the icon near the clock ›",
    "La première fois :": "The first time:",
    "Installer le lien": "Install the link",
    ", puis quitte FL": ", then quit FL",
    "et rouvre-le.": "and open it again.",
    ", puis ferme FL et rouvre-le.": ", then close FL and open it again.",
    "Vérifie d'abord les": "First check the",
    "4 cases de MIDI Settings": "4 MIDI Settings boxes",
    ", juste en dessous.": ", just below.",
    "Démarrer": "Start",
    ", puis vérifie l'aperçu (tu peux glisser les familles et les sons) et":
        ", then check the preview (you can drag families and sounds) and",
    "À la fin, « Tu valides la version organisée ? ».": "At the end, “Keep the organized version?”.",
    "Oui": "Yes",
    ": l'ancienne version part à la Corbeille.": ": the old version goes to the Trash.",
    "Retourner en arrière": "Go back",
    ": c'est la version organisée qui y part.": ": the organized version goes there instead.",
    "Rien n'est supprimé pour de bon : tant que tu ne vides pas la Corbeille, tu peux y récupérer le projet.":
        "Nothing is deleted for good: until you empty the Trash, you can get the project back from it.",
    "L'Organiser la première fois : Installer le lien": "Organize the first time: Install the link",
    "Une fois, avant le premier rangement. FL doit ensuite être relancé.":
        "Once, before the first organize. FL then has to be restarted.",
    "Annuler": "Cancel",
    "L'écoute du projet, son par son": "Listening to the project, sound by sound",
    "L'écoute, son par son.": "Listening, sound by sound.",
    "L'aperçu des familles avant de ranger": "The family preview before organizing",
    "L'aperçu, puis « Organiser ».": "The preview, then “Organize”.",
    "Tu valides la version organisée ?": "Keep the organized version?",
    "Tu valides : l'ancienne version part à la Corbeille.": "Keep it: the old version goes to the Trash.",
    # Les 4 cases de MIDI Settings
    "À faire pour Organiser": "To do for Organize",
    "Les 4 cases de MIDI Settings": "The 4 MIDI Settings boxes",
    "Dans FL : Options › MIDI Settings. Règle ces 4 cases, puis clique « Démarrer » dans Organiser.":
        "In FL: Options › MIDI Settings. Set these 4 boxes, then click “Start” in Organize.",
    "Output : un numéro de Port (ex. 7).": "Output: a Port number (e.g. 7).",
    "Case Port de la sortie": "Output Port box",
    "Input : le même numéro de Port. N'importe lequel, du moment que les deux sont pareils.":
        "Input: the same Port number. Any number, as long as both are the same.",
    "Case Port de l'entrée": "Input Port box",
    "Input : clique « FL Shortcuts Link », puis allume Enable.": "Input: click “FL Shortcuts Link”, then turn on Enable.",
    "Case Enable de l'entrée": "Input Enable box",
    "Controller type : FL Shortcuts.": "Controller type: FL Shortcuts.",
    "Liste Controller type": "Controller type list",
    "Voir toute la fenêtre": "See the whole window",
    "La fenêtre MIDI Settings de FL, les 4 cases entourées": "FL's MIDI Settings window, the 4 boxes circled",
    # 6. Communauté
    "Récupère les macros et les raccourcis des autres en un clic :":
        "Get other people's macros and shortcuts in one click:",
    "Ajouter à mes macros": "Add to my macros",
    "Utiliser ces raccourcis": "Use these shortcuts",
    "Partage les tiens avec": "Share yours with",
    "Partager": "Share",
    ": une macro qui te fait gagner du temps sert à tout le monde.": ": a macro that saves you time helps everyone.",
    "Pour partager, il faut un compte (Mon compte). Pour regarder, non.":
        "Sharing needs an account (My account). Browsing doesn't.",
    "Pour partager, il faut un compte (Mon compte). Pour regarder, non. Déjà dans l'app Mac ; elle arrive dans l'app Windows.":
        "Sharing needs an account (My account). Browsing doesn't. Already in the Mac app; coming to the Windows app.",
    "La page Communauté : des macros et des raccourcis partagés": "The Community page: shared macros and shortcuts",
    "Tout": "All",
    "Macros": "Macros",
    "Raccourcis": "Shortcuts",
    "Les miens": "Mine",
    "Macro": "Macro",
    "Armer la piste et lancer l'enregistrement": "Arm the track and start recording",
    "Voir": "View",
    "Raccourcis façon Ableton": "Ableton-style shortcuts",
    # En plus
    "En plus": "Also",
    "Mise à jour et aide": "Updates and help",
    "Mettre à jour": "Update",
    "Le nouveau .pkg": "The new .pkg",
    "Ouvre le nouveau": "Open the new",
    ": il remplace l'ancienne version. macOS peut redemander l'autorisation du clavier.":
        ": it replaces the old version. macOS may ask for the keyboard permission again.",
    "Désinstaller": "Uninstall",
    "Rien ne reste": "Nothing left behind",
    "Icône ›": "Icon ›",
    "Tout part, réglages compris.": "Everything goes, settings included.",
    "Un problème ?": "A problem?",
    "Écrire à l'équipe": "Write to the team",
    "Dans l'app :": "In the app:",
    "Aide › Écrire à l'équipe": "Help › Write to the team",
    ". Le diagnostic part avec ton message, jamais le nom de tes sons.":
        ". The diagnostic goes with your message, never the names of your sounds.",
    # Windows
    "Lance": "Run",
    "Si Windows dit « Windows a protégé votre ordinateur » :": "If Windows says “Windows protected your PC”:",
    "Informations complémentaires": "More info",
    "Exécuter quand même": "Run anyway",
    "Suis l'installation jusqu'au bout. FL Shortcuts démarre près de l'heure, en bas à droite.":
        "Follow the installer to the end. FL Shortcuts starts near the clock, at the bottom right.",
    "Windows a protégé votre ordinateur : Informations complémentaires, puis Exécuter quand même":
        "Windows protected your PC: More info, then Run anyway",
    "Windows a protégé votre ordinateur": "Windows protected your PC",
    "L'application n'est pas encore reconnue.": "The app isn't recognized yet.",
    "Ne pas exécuter": "Don't run",
    "près de l'heure : raccourcis, macros, Organiser.": "near the clock: shortcuts, macros, Organize.",
    "Elle peut être cachée sous la petite flèche ^ de la barre des tâches.":
        "It may be hidden under the small ^ arrow of the taskbar.",
    "Le menu de l'icône de FL Shortcuts, près de l'heure": "The FL Shortcuts icon menu, near the clock",
    "Quitter": "Quit",
    "02/11/2026": "11/2/2026",
    "Le nouveau Setup": "The new Setup",
    "Lance le nouveau": "Run the new",
    ": il remplace l'ancienne version.": ": it replaces the old version.",
    "Paramètres": "Settings",
    "Paramètres ›": "Settings ›",
    "› FL Shortcuts ›": "› FL Shortcuts ›",
    "À savoir": "Good to know",
    "Version en cours": "Work in progress",
    "Certains blocs de macro ne fonctionnent encore que sur Mac : l'app le dit sur le bloc.":
        "Some macro blocks only work on Mac for now: the app says so on the block.",
}


# Morceaux dont l'ordre des mots change en anglais (remplacés en entier, avant les textes).
BLOCS = {
    "<span>Ouvre le dossier <b>Applications</b>.</span>": "<span>Open the <b>Applications</b> folder.</span>",
    "Paramètres › <b>Applications</b> › FL Shortcuts › <b>Désinstaller</b>.":
        "Settings › <b>Apps</b> › FL Shortcuts › <b>Uninstall</b>.",
}


def traduire(html):
    """La page anglaise : chaque texte (entre deux balises) et chaque attribut lisible, remplacés à l'identique."""
    for fr, en in BLOCS.items():
        html = html.replace(fr, en)
    for fr, en in TITRES.items():
        html = html.replace(f"<title>{fr}</title>", f"<title>{en}</title>")
    for fr in sorted(TEXTES, key=len, reverse=True):
        en = TEXTES[fr]
        html = re.sub(r"(>\s*)" + re.escape(fr) + r"(\s*<)", lambda m: m.group(1) + en + m.group(2), html)
        html = html.replace(f'aria-label="{fr}"', f'aria-label="{en}"').replace(f'alt="{fr}"', f'alt="{en}"')
    # Pas d'espace avant les deux-points en anglais (« <b>Yes</b> : » → « <b>Yes</b>: »).
    return re.sub(r"(</b>|</kbd>)\s+:", r"\1:", html)


def reste_du_francais(html):
    """Les textes encore en français après la traduction (vide : tout est traduit)."""
    sans_style = re.sub(r"<style>.*?</style>", "", html, flags=re.S)
    morceaux = re.findall(r">([^<>]+)<", sans_style) + re.findall(r'(?:aria-label|alt)="([^"]+)"', sans_style)
    return sorted({m.strip() for m in morceaux if m.strip() in TEXTES and TEXTES[m.strip()] != m.strip()})
