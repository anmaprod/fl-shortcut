# Macro Creator for FL Shortcuts: what the best macro tools teach

Scope note: I couldn't find a standalone Windows program called "Super Macro" on the web. The closest match is BarRaider's **SuperMacro**, a Stream Deck plugin. I covered it, plus the common "simple recorder" category (Jitbit, Bartels Macro Recorder, Macro Scheduler), in its place. I also added three DAW-relevant references: **SoundFlow** (Pro Tools), **Cubase/Studio One macros**, and FL Studio's own *Tools › Macros*.

I read the repo's `/home/user/fl-shortcut/MACROS.md` so the recommendations fit what already exists:
- Step types today: `key`, `delay`, `click` with anchors, `menu`, `waitDialog`, `chooseFile`.
- Esc cancels a macro, and a macro runs only while FL is frontmost.
- Custom macros can only be written by hand in JSON, and import refuses them.

---

## 1. Comparison table

### A. How macros are made

| Tool | How you create a macro | How steps look and are edited | Trigger | Timing / waiting | Logic and variables |
|---|---|---|---|---|---|
| **Pulover's Macro Creator (PMC)** | Record (F9) plus *Commands* windows to insert steps by hand. You can mix both. | A table with Index, Action, Details, Repeat, Delay, Window, Comment and Color columns. Each row has a checkbox to disable it, and inserted loops and Ifs get indented. You can edit several rows at once, find/replace, and undo. | One hotkey per macro, which can be limited to one window (#IfWinActive) | A Delay column per row. Optional "Timed intervals" recording, random delays, and a "Repeat until image found" option. | Mouse, Text, Window, Image/Pixel search (with *If found / If not found* actions), If, Loop, While, variables, functions. Exports a working .ahk file. |
| **AutoHotkey v2** | Code in a text file | Script lines. Window Spy shows window names and coordinates (screen, window, client). | `^!x::` hotkeys, hotstrings, `#HotIf` context | `Sleep` or `WinWait`/`WinWaitActive` with a timeout (they return 0 on timeout and return at once if the window is already active) | Everything (it is a full language) |
| **Office VBA recorder** | Record, then edit the VBA code | VBA code in the editor | Ctrl+letter (it overrides Excel's own shortcut), a button, or the ribbon | None recorded | None can be recorded: no If, loops, variables or error handling. You add them in code. |
| **Simple recorders** (Jitbit, Bartels Macro Recorder, Macro Scheduler) | Recorder first | A list of readable steps. Bartels merges mouse moves and shows click overlays. | Hotkey | Real-time pauses or a speed slider. Some offer "Wait for window" or image match ("no static wait times"). | Basic IF, REPEAT, goto |
| **Keyboard Maestro (KM)** | Build from an actions palette, with *Insert Action by Name* search. A Record button also exists. | Stacked action blocks with editable fields, grouped into macro groups | Hotkey and dozens of other triggers. Groups can be active only in chosen apps or windows. | Recording leaves out pauses (a clock button adds them). *Pause Until* waits for a condition. Each action has timeout, abort and notify options. | If/Then/Else, loops, variables, image-based conditions |
| **Apple Shortcuts** | Drag or double-click blocks from a searchable action list | Blocks with blue "Magic Variable" tokens | Keyboard shortcut, menu bar, Services | Mostly implicit (each action finishes before the next starts) | If, Repeat, variables, *Ask Each Time* |
| **Automator "Watch Me Do"** | Record only | A list of events, which you can delete | Through a Service or Quick Action | Playback speed slider only. Playback keeps going even if the app isn't ready. | Only through other Automator actions |
| **BetterTouchTool (BTT)** | Build an action sequence | List of actions | Keys, gestures, app-specific triggers | Non-blocking delay vs. blocking delay. *Wait For Condition To Become True*. | If (variables, image visible on screen), Repeat, Cycle |
| **Hammerspoon** | Lua code | `init.lua` file, then *Reload Config* | `hs.hotkey.bind` | Code | Full language |
| **DAW macros** (REAPER Custom Actions, Cubase, Studio One) | Search the command list and add commands to a second list | An ordered list of named commands | Shortcut, toolbar button, MIDI | REAPER: "Wait n seconds before next action" | REAPER: "Prompt to continue" and simple loop actions. Real if/then needs a script (ReaScript). |
| **Stream Deck Multi Action / SuperMacro** | Drag actions onto a key / type a text syntax (`{{ctrl}}{{c}}{{pause:400}}`) | Small list / text field | Physical key | Delay step plus two timing sliders per action (key-press length, gap before the next action, about 100 ms by default). Multi-actions can't be nested. | SuperMacro: variables, toggle, sticky |
| **SoundFlow (Pro Tools)** | *Add Action* with search, plus *Pick UI element* | Action list with properties, and a *Convert to Script* button | Keys, Stream Deck, limited to the apps you choose ("When these apps are focused") | Staff advice: wait for the UI element, never an arbitrary pause | Possible in script form |

### B. Running, failing and sharing

| Tool | Testing / debugging | When a step fails | Stop / safety | Sharing / templates | Most common complaints |
|---|---|---|---|---|---|
| **PMC** | *Play Current Macro*, *Play From / Until / Only selected rows*, a Manual hotkey to go one step at a time, and a tooltip showing the last and next step | Option "Do not display errors" (it hides failures) | Stop and Pause hotkeys, tray menu | .pmc project files, AHK export, example files | Wrong coordinates (by default relative to the active window), "Invalid hotkey" on non-English keyboards, needs admin rights, no updates since 5.4.1 (2021) |
| **AutoHotkey v2** | Error dialogs only | Script error, or a 0 return value to check yourself | You write it (e.g. `^!p::Pause`) | .ahk files | Syntax, confusion between v1 and v2, admin/UAC blocks, games block it |
| **Office VBA recorder** | Step through in the VBA editor (F8) | Runtime error dialog | — | Personal Macro Workbook (available in every workbook) | Recorded code is bloated (every dialog option is recorded), tied to the selection, can't record mouse text selection, "Macros cannot be undone" |
| **Simple recorders** | Partial playback, breakpoints (Jitbit) | Often keeps going | Hotkey | EXE export | Clicks miss after the layout or speed changes |
| **Keyboard Maestro** | Macro Debugger: shows the running action, Pause New Macros, Step Over/In/Out, breakpoint actions, recent variables. The *Display* option highlights image matches on screen. | "Failure Aborts Macro" and "Notify on Failure" per action. Timeouts that neither notify nor abort are not logged. | Cancel menu, *Cancel All Macros*, ⌃⌥⇧⌘-click on the menu bar icon | .kmmacros / .kmlibrary files. Imported library items arrive inactive, with a "check what it does" warning. | Learning curve. Found Image breaks with Retina/DPI or resolution changes. Recording needs Accessibility permission. |
| **Apple Shortcuts** | No step debugger: Apple suggests Show Alert or Quick Look | Run stops with an alert | Stop button. *Stop Shortcut* action. | iCloud links, Gallery | Hard to debug ("DIY console"). Can't click reliably inside non-native apps. |
| **Automator "Watch Me Do"** | Replay | **Continues regardless** | — | .workflow | Needs "the environment to exactly match" the recording |
| **BetterTouchTool** | — | — | Cancel timed sequences | Presets | Very dense settings screens |
| **Hammerspoon** | Console | Lua error | You write it | Lua files and "Spoons" | Assumes you can program |
| **DAW macros** | Run from the list | Usually skip or stop | — | REAPER exports `.ReaperKeyMap`. REAPER can make a whole macro a single undo step. | No conditions without a script |
| **Stream Deck** | Press the key | — | — | Profiles, marketplace | Hotkeys misfire if the key-press time is set too short |
| **SoundFlow** | *Run Macro* button | Error with the step named | Ctrl+Shift+Esc | Package Store | Selector paths break on UI changes |

---

## 2. Design principles for an FL Studio macro creator (25)

1. **Record, then edit.** Recording only produces a draft that the user refines. KM's wiki says to "use recording to create a base sequence of actions and then adjust as necessary". The Excel recorder and Automator say the same in practice.
2. **Record the intent, not the pixels.** Turn what you capture into named steps. A key that FL understands becomes "Ouvrir le Mixer". A menu click becomes a menu path. Pixel coordinates are a last resort. (KM records "Selecting a menu"; SoundFlow and REAPER chain *named* commands; Word won't record mouse selections at all and tells users to use the keyboard.)
3. **One searchable block library**, organized by category and searchable by typing ("mix", "attendre"). From KM *Insert Action by Name*, Shortcuts' action search, REAPER's filter and SoundFlow's *Add Action*.
4. **Each step row reads as a French sentence**, with values shown as pills: « Appuyer sur [⌃F8] », « Attendre que [la boîte Ouvrir] apparaisse · 5 s max ». Bartels' recorder promises "easy-to-edit steps instead of cryptic macro code", PMC uses Action/Details columns, and Shortcuts uses pill tokens.
5. **"Wait until" before "pause".** Fixed pauses are a visible last resort. From KM *Pause Until*, BTT *Wait For Condition*, SoundFlow ("we wait for the actual thing"), and AHK `WinWaitActive`, which returns immediately when the window is already there.
6. **Every wait has a timeout and a stated outcome.** Default: stop and explain. Advanced options: skip, or ask. From KM's timeout/abort/notify settings, AHK's 0 return value, and PMC's *If found / If not found*.
7. **Never fail silently.** By default a failure stops the macro, names the step and the reason, beeps, and writes to the log. Automator "continues regardless", PMC has "Do not display errors", and KM doesn't log silent timeouts: these are the anti-patterns.
8. **Positions are relative to an anchor**: the FL window, a panel, or a found image. Never the absolute screen. If the window size changed, ask the user to show the spot again rather than clicking blindly. From KM "relative to front window corner / found image", AHK's client-area default, and PMC's FAQ entry on wrong coordinates.
9. **Context scoping.** A macro only runs when FL is frontmost, and later only when a given FL window is focused. From KM app-specific macro groups, PMC context-sensitive hotkeys, AHK `#HotIf`, and SoundFlow "When these apps are focused".
10. **A stop key that always works, plus automatic stop when FL loses focus.** On stop, release every held modifier key. From PMC's Stop hotkey, KM *Cancel All Macros*, and SoundFlow Ctrl+Shift+Esc.
11. **A Test button in the editor that highlights the running step live.** From the KM Debugger and PMC's "last and next step" tooltip.
12. **Partial runs**: run from this step, run up to this step, run only the selected steps. From PMC and Jitbit.
13. **Step-by-step mode**: press "Next" to run each step. From PMC's Manual hotkey and KM's Step Over and Pause New Macros.
14. **Disable a step without deleting it.** From PMC's checkbox column.
15. **"Show me" buttons**: flash the learned click spot or the image match on screen. From KM *Display* and the Get/Go buttons, SoundFlow *Pick*, and AHK Window Spy.
16. **Ask at run time.** Any value can be "ask me each time", for example the preset or the track. From Shortcuts *Ask Each Time*, REAPER *Prompt to continue*, and FL Shortcuts's existing "ask for the preset each time".
17. **Clean recordings automatically.** Merge mouse moves, drop the first click that only switches windows, collapse typed text into one step, and offer to replace recorded pauses with waits. From Bartels' merged moves, the Automator tutorial deleting the first Dock event, and Microsoft's advice to trim recorded code.
18. **Global speed and timing settings rather than a delay on every row.** Real-time pauses are optional when recording. From the KM clock button and PMC speed hotkeys. Macro Scheduler warns that faster playback is less reliable.
19. **Assign the shortcut with conflict detection.** Excel lets a macro silently override a built-in shortcut, and Shortcuts has reserved keys. FL Shortcuts already warns about conflicts; reuse that.
20. **Templates before a blank page**: a gallery of FL-specific starting macros. From PMC example files, the KM Macro Library, the Shortcuts Gallery, the SoundFlow Store, and FL's own *Tools › Macros*.
21. **Show advanced features gradually.** No variables or code in v1. Loops and conditions sit behind « Avancé ». Hammerspoon assumes programming, AHK's v1/v2 syntax confuses beginners, and a BTT If needs three blocks.
22. **Readable sharing, imported "in quarantine".** An imported macro arrives disabled, with a summary of what it does, until the user enables it. From KM ("never execute a macro without verifying the source") and REAPER `.ReaperKeyMap`. FL Shortcuts today refuses custom macros at import; quarantine would replace that refusal.
23. **Short, composable macros**, with a "Lancer une autre macro" step. From Excel ("smaller relevant macros"), KM Execute Macro, and REAPER nested custom actions.
24. **Treat a macro as one action.** Tell the user it may not undo in one step, and block dangerous keys. REAPER can consolidate a macro into one undo point; Excel warns "Macros cannot be undone"; FL Shortcuts already has a ⌘Q/⌘W blacklist.
25. **Keep the keyboard layout and environment in mind.** Store key codes but display AZERTY labels. Store the FL version and window size with each learned position, and check them again before running. PMC breaks on non-English layouts, and KM image matching breaks on DPI or resolution changes.

---

## 3. Recommended feature set and editor layout

### MVP: expose the existing engine through a UI
- **Editor sheet** (described below) for custom macros. This replaces hand-written JSON.
- **About 8 blocks**:
  - Action FL, picked from the shortcut catalog by name
  - Touche / combinaison
  - Menu de FL (a menu path)
  - Clic à un endroit appris (anchored to the FL window, re-asked if the size changed)
  - Attendre que… (a dialog opens or closes, an FL window is in front), with a 5 s timeout by default
  - Pause (at most 5 s, shown with an orange badge)
  - Choisir un fichier / preset (fixed or asked each time)
  - Demander de continuer
- **Row editing**: drag to reorder, duplicate, delete, a checkbox to disable, a comment per step, undo.
- **Shortcut field** with the existing conflict warnings.
- **Testing**: *Tester*, *Tester à partir d'ici*, live step highlight, Esc to stop, and a result banner that names the failed step.
- **Safety kept from today**: FL must be frontmost, the blacklist, the limits (40 steps, 180 s), and releasing modifier keys.
- **6–8 FL templates**: quick record (exists), open the Mixer and focus a track, render/export, save a new version, load a preset, show/hide panels.
- **Export/import** as a readable `.flsmacro` file (JSON), with import in quarantine.

### v2
- **Recorder** that captures keys, menus and clicks, cleans them up, and shows a review screen.
- **Step-by-step mode** and running only the selected steps.
- **"Attendre que cette image apparaisse"** and *Clic sur l'image*. These need the Screen Recording permission, so ask for it only when the first image block is added. Include the *Montrer* highlight.
- **Répéter N fois**, *Demander à chaque fois* on any field, and a simple *Si* (if a dialog or image is present).
- **Lancer une autre macro** step, a global speed setting, and a per-macro run log viewer.

### Later
- Variables, conditional loops and Else.
- Context per FL window (Piano Roll vs. Mixer).
- MIDI and Stream Deck triggers (reusing the MIDI mode).
- Community gallery or share links.
- Windows port (SendInput + UI Automation).
- Export as script: probably never needed for this audience.

### Editor layout (macOS, French labels)

**Toolbar:**
- Macro name, a **Raccourci** field, then the buttons ● *Enregistrer*, ▶ *Tester*, ⏭ *Pas à pas*, *Exporter*.
- Status pill: "Prête" / "FL pas au premier plan" / "Position à réapprendre".

**Left sidebar:** macros grouped as *Mes macros* and *Modèles*, plus *Importées (à vérifier)*.

**Center, "Étapes":** a numbered list where each row has:
- a drag handle, an on/off checkbox and the step number;
- a category icon in color (blue keys, purple menus, orange mouse, green waits, gray control);
- a one-line sentence with pills, e.g. « Ouvrir **le Mixer** (F9) » or « Attendre que **la boîte Ouvrir** apparaisse · 5 s max »;
- a badge on the right: ⚠ orange for "fixed pause" or "position fragile", ⏱ for a timeout, 💬 for a comment;
- a hover "+" between rows to insert a step there.

**Right inspector, for the selected step:**
- Its parameters.
- *Apprendre la position* / *Montrer*.
- Timeout.
- *Si l'étape échoue : Arrêter (défaut) / Passer / Demander*.
- Plain-French help for the block.

**Adding a step:** a bottom bar "＋ Ajouter une étape — tape pour chercher…" opens a popover. It shows categories (FL Studio, Clavier, Menus, Souris, Attendre, Fichiers, Contrôle, Autres macros) plus "Récents", and is fully usable from the keyboard (type, then ↩). The new step goes below the selection, as in PMC and Cubase.

**Recording:**
1. *Enregistrer* brings FL to the front and shows a small floating window that doesn't take focus: "● Enregistrement · 3 étapes · Terminer (⌃⌥⌘R) · Annuler". It shows each captured step as it is caught.
2. On *Terminer*, a review sheet titled « Voici ce que j'ai compris » lists the cleaned steps with suggestions, for example « Remplacer ces 2 pauses par *Attendre la boîte Ouvrir* ? » or « Ce clic dépend de la position : l'ancrer à la fenêtre ? ».
3. *Insérer* puts the steps at the cursor position.

**Testing:**
1. *Tester* brings FL to the front, and a floating window that doesn't take focus shows "Étape 3/7 — Attendre la boîte Ouvrir… [Arrêter · Échap]".
2. In the editor, finished steps get a green check, the running step is blue, and a failed step is red with its reason.
3. At the end a banner says, for example: « Échec à l'étape 4 : la boîte "Ouvrir" n'est pas apparue en 5 s ». It offers [Montrer l'étape] [Allonger l'attente] [Réessayer].

---

## 4. Pitfalls to avoid

- **Brittle coordinates.** Absolute screen points break when windows move, are resized, change Retina scaling, or when FL panels are detached or rearranged (Watch Me Do, PMC FAQ, KM DPI threads). Prefer FL keys and menus, then anchors, then images. Store the window size with each learned position and ask again instead of guessing.
- **Timing.** A pause tuned on the creator's Mac is too short on a slow Mac or a heavy project, and too long otherwise. Recorded real-time pauses copy hesitations. Waits with timeouts fix this.
- **Focus stealing.** Your own windows (the floating test window, alerts, notifications), macOS dialogs, or the user touching the mouse can send keystrokes to the wrong app. Use panels that don't take focus, check that FL is frontmost before *every* step, and stop if focus changes.
- **Modifier leakage and stuck keys.** The trigger's ⌃ still held turns a click into a right-click (FL Shortcuts already handles this). After a stop, always send key-up for every modifier.
- **Unreadable step lists.** Raw key codes, "Click (812, 433)", hundreds of mouse moves, and recorded noise (all of Word's dialog settings). Merge, name things, allow comments, and group steps.
- **Too much power too early.** Variables, loops and code at the top level (AHK, Hammerspoon, BTT's three-block If, hundreds of KM actions) scare off musicians. Keep the first palette to about 8 blocks.
- **Silent continue / hidden errors.** Automator continuing regardless and PMC's "Do not display errors" are exactly what not to copy.
- **Irreversible damage.** Macros can't be undone (Excel). Block dangerous keys, confirm destructive steps, and suggest testing on a copy of the project.
- **Runaway macros and untrusted imports.** Keep limits, the stop key and quarantine on import.
- **Permissions.** Ask for Screen Recording only when an image block is added; it is a common cause of KM failures.
- **AZERTY and FL version drift.** Show key labels in the user's layout. Check menu paths again after FL updates.

---

### Sources
- PMC docs: https://www.macrocreator.com/docs/ · Main.html · Record.html · Playback.html · Commands.html · Commands/Image_Search.html · Commands/Pause.html · Export.html · Faq.html · Help/examples: https://www.macrocreator.com/help/ · Forum on relative coordinates: https://www.autohotkey.com/boards/viewtopic.php?p=78171 · Version 5.4.1 (2021): https://www.chocolatey.org/packages/macrocreator
- AutoHotkey v2: https://www.autohotkey.com/docs/v2/Tutorial.htm · https://www.autohotkey.com/docs/v2/lib/WinWaitActive.htm · https://www.autohotkey.com/docs/v2/lib/Click.htm · https://www.autohotkey.com/docs/v2/FAQ.htm · v1/v2 confusion: https://www.autohotkey.com/boards/viewtopic.php?p=510925
- Office: https://support.microsoft.com/office/automate-tasks-with-the-macro-recorder-974ef220-f716-4e01-b015-3ea70e64937b · https://support.microsoft.com/en-us/office/create-or-run-a-macro-c6b99036-905c-49a6-818a-dfb98b7c3c9c · https://github.com/MicrosoftDocs/VBA-Docs/blob/main/word/Concepts/Customizing-Word/revising-recorded-visual-basic-macros.md · Relative references: https://www.exceldemy.com/excel-macro-relative-reference/
- Recorders: https://www.jitbit.com/macro-recorder/ · https://www.macrorecorder.com/ · https://www.mjtnet.com/blog/what-is-a-macro-recorder/ · SuperMacro: https://docs.barraider.com/faqs/supermacro/getting-started/ · https://docs.barraider.com/faqs/supermacro/examples/
- Keyboard Maestro: https://wiki.keyboardmaestro.com/manual/Recording · https://wiki.keyboardmaestro.com/action/Pause_Until · https://wiki.keyboardmaestro.com/manual/Macro_Debugger · https://wiki.keyboardmaestro.com/action/Move_or_Click_Mouse · https://wiki.keyboardmaestro.com/manual/Macro_Groups · https://wiki.keyboardmaestro.com/manual/Macro_Library · https://forum.keyboardmaestro.com/t/timeouts-do-not-write-to-engine-log-when-notify-on-timeout-is-not-checked/34507 · https://forum.keyboardmaestro.com/t/kill-switch/2798/4 · https://forum.keyboardmaestro.com/t/click-at-found-image-not-clicking-on-imac-retina-running-mojave/12270 · https://forum.keyboardmaestro.com/t/add-ability-to-insert-favorite-actions-by-name-search-bar/24467
- Apple: https://support.apple.com/guide/shortcuts-mac/apdc33e4f4da/mac · https://support.apple.com/guide/shortcuts-mac/apdd02c2780c/mac · https://support.apple.com/guide/shortcuts-mac/apd163eb9f95 · https://support.apple.com/guide/shortcuts-mac/apdb9661c761/mac · https://www.macstories.net/reviews/logger-for-shortcuts/ · Automator: https://dssw.co.uk/blog/2014-11-10-automator-watch-me-do/ · https://macosxautomation.com/training/automator/tut04/04.html · https://macosxautomation.com/training/automator/tut04/05.html
- BTT: https://docs.folivora.ai/docs/actions/control-flow/ · Hammerspoon: https://www.hammerspoon.org/go/
- DAWs: https://www.audeobox.com/learn/reaper/custom-actions-guide/ · https://www.cockos.com/wiki/index.php/ALR_Main_2005 · https://www.cockos.com/wiki/index.php/Macros · https://reaperaccessibility.com/wiki/Keyboard_Shortcuts · Cubase: https://archive.steinberg.help/nuendo/v13/en/cubase_nuendo/topics/key_commands/key_commands_macros_setting_up_t.html · Studio One: https://www.soundonsound.com/techniques/studio-one-macro-machines · FL Tools › Macros: https://www.image-line.com/fl-studio-learning/fl-studio-online-manual/html/menu_tools.htm
- Stream Deck: https://help.elgato.com/hc/en-us/articles/360027960912-Elgato-Stream-Deck-Multi-Actions · https://help.elgato.com/hc/en-us/articles/7092527123725 · SoundFlow: https://soundflow.org/docs/macros/create-your-first-macro · https://soundflow.org/docs/macros/advanced-macro-editing

Not directly sourced, from my own knowledge: Apple Shortcuts highlighting the running action in the editor, and Excel's Personal Macro Workbook location. Treat those as unverified.
