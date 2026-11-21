# FL Studio automation surface for FL Shortcuts's macro creator (FL 2024 → FL 2026, macOS)

This covers what a helper app can drive in FL Studio: script actions and reads, keyboard shortcuts, menus, and a proposed set of macro blocks.

**What I based it on:**
- The official Image-Line manual, downloaded and parsed locally. Its API tables carry a "Version" column that goes up to **API 45**.
- The official API stubs (IL-Group repo, last commit 13 May 2026, now marked unmaintained), parsed with `ast`: 461 functions with their minimum API version.
- The FL "What's New" changelog, up to 26.1.7.5 (12 Oct 2026).
- The repo's own `PROTOCOL.md`, `MACROS.md`, `audit/04_compatibilite_versions.md` and `Resources/device_FLShortcut.py`, so the proposals fit what already exists.

**Reliability marks used throughout:**
- **✔** idempotent: it sets a state, so running it twice is harmless.
- **↺** toggle.
- **✚** creates something each time it runs.
- **⚠** fragile, or not yet checked on a real FL.

**How each block is carried out (implementation codes):**
- **S**: an action of the FL script, woken over MIDI.
- **K**: an FL keyboard shortcut.
- **M**: a menu, either through the macOS menu bar using Accessibility, or with the letters of an FL context menu.
- **C**: a click at a learned position.
- **W**: a wait on FL's window list.
- **A**: the app on its own.

---

## 0. Five facts that shape the design

1. **The script turns toggles into "set to this state" blocks.** Almost every FL command is a toggle (Space, R, L, ⌘M, `transport.record()`, `mixer.armTrack()`, `globalTransport(FPT_*)`). The script can read the state first and only toggle when needed: `isPlaying`, `isRecording`, `getLoopMode`, `ui.isMetronomeEnabled/isPrecountEnabled/isLoopRecEnabled/isStartOnInputEnabled`, `isTrackArmed`, `isTrackMuted`, and so on. Without the MIDI link, a block built on a keyboard shortcut cannot be idempotent.

2. **FL's main menus are in the macOS menu bar (since FL 2024.2).**
   - FL 21.2.99 Beta 1 "Added all items from the main menu to the macOS application menu".
   - FL 2024.1.2 removed it again ("graphics instability").
   - FL 2024.2 brought it back ("FL Studio menu items are shown in the macOS system menu").
   - So File / Edit / Add / Patterns / View / Options / Tools / Help can be pressed by title through Accessibility (AXMenuBar → AXMenuItem → AXPress). That is more robust than letters or clicks.
   - Context menus (mixer track, channel, playlist track, REC button…) are FL's own popups. They are driven by accelerator letters and the arrow keys, after waiting for the popup window to appear.
   - Accelerator letters are confirmed by the changelog: 'D' is "Delete" in the mixer track menu (FL 25 Beta 3); accelerators were added in 25.2.5; a crash "when scrolling a context menu while pressing an accelerator key" was fixed in 26.1.5. The repo's own tests confirm F = File, then O = Open mixer track state.

3. **A script cannot open files, load a state or preset file, pick an audio input, render, or "Save As".** These always need M + W + chooseFile, or C.

4. **Know the script's version-specific bugs.**
   - `transport.globalTransport` can freeze or crash FL on **26.1.0–26.1.6** (fixed in 26.1.7). The repo already avoids it in that range.
   - Mixer functions on the "current" track were wrong until 26.1.4.
   - `setPatternLength` was buggy until 26.1 beta 4.
   - `enableTrackSlots`, `revTrackPolarity` and `swapTrackChannels` had no toggle until 25.1.99 b3. Always pass an explicit `value`.
   - In FL 2025 an invalid mixer index crashed FL. Validate indexes against `mixer.trackCount()` (that count includes Master and "Current").

5. **Setters fail while a modal dialog is open.** They raise `TypeError("Operation unsafe at current time")`; `PME_System_Safe` is unset while a modal window is shown. Run script steps only after a `waitDialogClose`, and check `general.safeToEdit()` (API 29) or catch that exception, then reply with ack 0.

---

## 1. MIDI scripting API: what is useful for macros

The script reads the API number with `general.getVersion()`. Gate every call with `hasattr`: the manual's version numbers sometimes contradict the changelog. For example, `mixer.setCurrentTempo` is documented as v38 but the changelog adds it in 25.2.4, and `setPatternLength` is documented as v39 but added in 26.1 beta 1.

### Approximate API version ↔ FL version

| API | FL version |
|---|---|
| 1 | 20.7 |
| 8–10 | 20.7.3–20.8.1 |
| 15 | 20.8.4 |
| 19–20 | 20.9.x |
| 22 | 21.0 |
| 25–28 | 21.0.3 |
| 29 | 21.1 |
| 30–33 | 21.2 |
| 35–37 | FL 2024 / 2024.2 |
| 38 | FL 2025 |
| 39 | 25.2.2 (`movePattern`) |
| 40 | 25.2.4 (`selectTool`) |
| 41 | 26.1 b2 (`showPicker`) |
| 42 | 26.1 b5–b6 (`setShuffle`, `HW_Dirty_Undo`) |
| 43 | 26.1.1 (`clonePattern` with destination index) |
| 44 | 26.1.3 (`clearPattern`) |
| 45 | 26.1.6–26.1.7 (`duplicatePatternData`); the repo's audit records a real report of API 45 on 26.1.7 |

### transport

**Actions**
- `start()` ↺ play/pause.
- `stop()` ✔.
- `record()` ↺ arms the REC button only. Play starts the actual recording.
- `setLoopMode()` ↺ toggles Pattern/Song.
- `setSongPos(pos, mode)` ✔. Mode −1 = normalised 0..1, 0 = ms, 1 = s, 2 = absolute ticks (the mode parameter needs API 4). The bars/steps/ticks modes are **not implemented** in `setSongPos`; to go to bar N use `(N−1)*general.getRecPPB()` ticks.
- `markerJumpJog(±n)`, `markerSelJog`.
- `rewind` / `fastForward(SS_Start=2 / SS_Stop=0)`.
- `setPlaybackSpeed(0.25–4)`.
- `globalTransport(FPT_x, 1)`.

**Reads**
- `isPlaying()`.
- `isRecording()`: the REC button is armed. "Actually recording" = `isRecording() and isPlaying()`.
- `getLoopMode()`: 0 = pattern, 1 = song.
- `getSongPos(mode)`, `getSongPosHint()` ("B:S:T"), `getSongLength(mode)` (API 3).

**`globalTransport` commands (API 1).** These are events with no state, so pair each with a read.

| Group | Commands (code) |
|---|---|
| Transport | Play 10, Stop 11, Record 12, Loop 15 |
| Undo | Undo 20 (undo/redo toggle), UndoUp 21 |
| Markers | AddMarker 33, MarkerJumpJog 35 |
| Edit and snap | Snap 48, SnapMode 49, Cut/Copy/Paste 50–52, Insert/Delete 53–54 |
| Navigation | NextWindow 58 |
| Function keys F1–F12 (60–71) | F2 rename mixer track, F4 next empty pattern with name dialog, F5–F7 toggle Playlist / Channel Rack / Piano Roll, F8 plugin picker, F9 mixer, F10 MIDI settings, F11 song info, F12 close all windows |
| Keys | Enter 80, Escape 81, Yes 82, No 83 |
| Menus | **Menu 90 / ItemMenu 91** ("item edit/tool/contextual menu") |
| Files | **Save 92, SaveNew 93** |
| Jogs | Pattern/Track/ChannelJog 100–102, TempoJog 105 (0.1 BPM steps) |
| Tempo | TapTempo 106 |
| Record options | Metronome 110, WaitForInput 111, Overdub 112, LoopRecord 113, StepEdit 114, CountDown 115 |
| Other | NextMixerWindow 120, ShuffleJog 122 |

⚠ ItemMenu (91) might open the selected mixer track's context menu without a right-click. To test: it would make "Charger un état de piste" independent of the click position.

### mixer

The selected track is `trackNumber()`. `getTrackInfo(TN_Sel)` returns the special **"Current"** track, not the selected one. `trackCount()` includes Master and Current; `getTrackCount()` (v38) excludes them. FL 2025 introduced a dynamic mixer, so never hard-code 125 or 126.

**Actions**

| Function | API | Idempotent? |
|---|---|---|
| `setTrackNumber(i, curfxScrollToMakeVisible=1)` | 1 | ✔ |
| `setActiveTrack(i)` (exclusive selection) | 27 | ✔ |
| `selectTrack(i)` | 1 | ↺ |
| `selectAll` / `deselectAll` | 1 | ✔ |
| `setTrackName(i, s)` (no dialog) | 1 | ✔ |
| `setTrackColor(i, 0xRRGGBB)` | 1 | ✔ |
| `armTrack(i)` | 1 | **↺** — only toggles, no value parameter; idempotent only by reading `isTrackArmed` first |
| `muteTrack(i, value)` | 2; `value` from 30 | ✔ with value |
| `soloTrack(i, value, mode)` | 1 | ✔. Modes: 1 = with sources, 2 = with sends, 3 = both (= Opt-click), 4 = this track only |
| `enableTrack(i)` | 1 | ↺ |
| `setTrackVolume(i, v)` (0..1, **0.8 = 0 dB**) | 1 | ✔ |
| `setTrackPan(i, −1..1)` | 1 | ✔ |
| `setTrackStereoSep` | 12 | ✔ |
| `enableTrackSlots(i, value)` (FX on/off) | 19 | ✔ with explicit value |
| `revTrackPolarity`, `swapTrackChannels` | 19 | ✔ with explicit value |
| `setRouteTo(i, dest, 1, updateUI)` | 1; `updateUI` 36 | ✔ |
| `setRouteToLevel` | 36 | ✔ |
| `linkChannelToTrack(ch, track, select)` | 23 | ✔ |
| `focusEditor(track, slot)` | 25 | ✔ |
| `setPluginMixLevel` | 37 | ✔ |
| EQ `setEqGain/Frequency/Bandwidth` | 35 | ✔ |
| `setCurrentTempo(bpm)` (float since 25.2.4) | 38 | ✔ |

The changelog also announces `get/setPluginMuteState` (25.1.99), which the manual does not document. Test it with `hasattr`.

**Reads**
- `trackNumber()`, `trackCount()`, `getTrackName(i)`, `isTrackSelected`.
- `isTrackArmed`, `isTrackMuted` (2), `isTrackSolo`, `isTrackEnabled`, `isTrackSlotsEnabled` (19).
- `getTrackVolume(i, 1)` returns **dB** (API 14), `getTrackPan`.
- `getTrackPeaks(i, PEAK_LR=2)`: 0 = silence, 1 = 0 dB.
- `getRouteSendActive`, `getTrackRecordingFileName`, `getCurrentTempo()`, `isTrackPluginValid(i, slot)`, `getActiveEffectIndex()` (25).

**Setting a volume in dB.** There is no setter in dB. Use a dichotomy: `setTrackVolume`, then `getTrackVolume(i, 1)`, about 12 iterations within one script call.

### channels

Indexes respect the Channel Rack group; `useGlobalIndex` exists from API 33.

**Actions**
- `selectOneChannel(i)` ✔ (API 8). Before that, fall back to `FPT_ChannelJog`.
- `selectChannel(i, value)`.
- `showEditor(i, 1/0)` ✔ (value from API 3). `showCSForm(i, state)`. `focusEditor(i)`.
- `muteChannel(i, value)` ✔. `soloChannel(i, value)` ✔ (value from API 30).
- `setChannelVolume`, `setChannelPan`, `setChannelPitch` ✔.
- `setTargetFxTrack(ch, track)` ✔ (28).
- `setGridBit(i, step, 0/1)` ✔: step-sequencer steps.
- `quickQuantize(i, startOnly)` (9).
- `setShuffle(v)` (42): global swing.
- `rerollLoopStarterLoop(i)` (39).

**Reads**
- `selectedChannel()` (5), `channelCount()`, `getChannelName(i)`, `isChannelSelected`, `isChannelMuted/Solo`, `getChannelVolume(i, dB)`, `getTargetFxTrack(i)`, `getChannelType(i)` (19), `getGridBit`, `getShuffle()` (42).

### patterns

**Actions**
- `jumpToPattern(i)` ✔.
- `findFirstNextEmptyPat(FFNEP_DontPromptName=2)` ✚ (2 = no naming prompt).
- `setPatternName` ✔, `setPatternColor` ✔.
- `setPatternLength(i, beats)` (39) ✔, `incrementPatternLength`.
- `clonePattern(i, dest)` (25; dest from 43) ✚.
- `clearPattern(i)` (44) ✔.
- `duplicatePatternData(i)` (45).
- `movePattern(±1)` (39).
- `selectPattern(i, value)` (2).

**Reads**
- `patternNumber()`, `patternCount()`, `getPatternName`, `getPatternLength`.
- `isPatternDefault(i)` (23): the pattern is empty.
- `getActivePatternGroup` (28).

### playlist

**Actions**
- `muteTrack(i, value)` ✔ (value 30), `soloTrack(i, value)` ✔.
- `selectTrack` ↺ (12), `selectAll` / `deselectAll` (12).
- `setTrackName`, `setTrackColor` ✔.
- `selectTool(EETool_*)` (40) ✔ — selects the tool in the playlist **and** the piano roll. Values: Pencil 0, Brush 1, Del 2, Sel 4, Zoom 5, Cut 6, Play 7, Slip 8, Mute 9.
- `triggerLiveClip` (performance mode).

**Reads**
- `trackCount()`, `getTrackName`, `isTrackMuted/Solo/Selected`, `getPerformanceModeState()` (21), `getTrackActivityLevel`.

### arrangement

- **Actions:** `addAutoTimeMarker(ticks, name)` ✚, `jumpToMarker(±1, select)`, `liveSelection(time, stop)` (to test as a way to set a time selection for loop recording).
- **Reads:** `currentTime(snap)`, `selectionStart/End()`, `getMarkerName(i)`.
- The changelog announces setters for the selection (FL 2025); they are not documented.

### ui

**Actions**
- `showWindow(wid)` ✔ (unlike F5–F9, which toggle). `hideWindow(wid)` (5). `setFocused(wid)` (2) ✔.
- Window ids: Mixer 0, Channel Rack 1, Playlist 2, Piano Roll 3, Browser 4. For `setFocused` only: effect plugin 6, generator plugin 7, plugin picker 8 (since 26.1).
- `showPicker(0 plugins / 1 project, category)` (41).
- `openEventEditor(channels.getRecEventId(ch)+midi.REC_Chan_PianoRoll, midi.EE_PR)` (9): opens the Piano Roll of that channel.
- `setSnapMode(v)` (24) ✔. `snapOnOff` ↺.
- `setStepEditMode(bool)` (28) ✔.
- `setHintMsg(text)` ✔: a message in FL's hint bar, a good way to give feedback.
- `scrollWindow(wid, i)` (13).
- `closeActivePopupMenu()`.
- FL-internal keys: `escape/enter/yes/no/up/down/left/right/cut/copy/paste/delete`. Their effect on native macOS panels is unknown.
- `launchAudioEditor(reuse, file, track, …)`: opens Edison on a track with a file.

**Reads (conditions and waits)**
- `getFocused(wid)`, `getVisible(wid)`, `getFocusedFormCaption()`, `getFocusedFormID()` (13), `getFocusedPluginName()` (5).
- **`isInPopupMenu()`**: a FL popup menu is open.
- `isMetronomeEnabled`, `isPrecountEnabled`, `isLoopRecEnabled`, `isStartOnInputEnabled`, `getStepEditMode` (28), `getSnapMode`, `getHintMsg`.
- `getVersion(0..3)`: FL major / minor / release / build.

### general

**Actions**
- `undoUp()` ✔ (one step back), `undoDown()` (redo). `undo()` is an undo/redo toggle like ⌘Z.
- `saveUndo(name, flags)`.
- `processRECEvent(midi.REC_Tempo, bpm*1000, midi.REC_Control|midi.REC_UpdateControl)` (API 7): tempo fallback for builds without `setCurrentTempo`.
- `setNumerator` / `setDenominator` / `setRecPPQ` (38).
- **`dumpScoreLog(seconds, silent)` (15)**: writes what was just played into the selected pattern.
- `clearLog()`.

**Reads**
- `getChangedFlag()`: 0 clean, 1 dirty, 2 dirty but auto-saved.
- `getVersion()` (API number), `getRecPPB/PPQ`, `getUseMetronome`, `getPrecount`.
- `getProjectTitle/Author/Genre` (38), `safeToEdit()` (29), `getUndoHistoryCount/Pos`.

### plugins

`index` is a channel index, or a mixer track with `slotIndex`.
- **Actions:** `nextPreset` / `prevPreset` (10) ↺, `setParamValue(v, param, index, slot)` (8) ✔.
- **Reads:** `isValid`, `getPluginName(…, userName)`, `getParamCount/Name/Value/ValueString`, `getPresetCount` (15).

### device

- Only what the protocol uses: `midiOutMsg` for replies, `getPortNumber`, `isAssigned`.
- The changelog announces `releaseCC`; FL Remote can send virtual MIDI.

### NOT possible through the script

- Open, import or "Save As" a project with a filename. Only `FPT_Save` and `FPT_SaveNew` exist.
- Export or render. `FPT_Save` saves the project but does not render.
- **Load or save a mixer track state**, or load a plugin preset **by file**. Only next/previous preset is possible.
- **Choose an audio input or output** for a mixer track, the recording pickup point (EXT/MIX/FX…), or input monitoring.
- The recording filter (Audio / Notes / Automation), "Recording starts playback", "Auto-unarm", "Auto-create audio clips".
- Add a plugin to a channel or slot (only open the picker), insert or delete mixer tracks or channels.
- Set a playlist track to Audio Track mode, place clips, edit notes. Piano Roll `.pyscript` scripts are a separate API, run with ⌘⌥Y "Run last script again".
- Read or toggle "Typing keyboard to piano" (⌘T): there is no API.
- Any key other than the FPT list. Open an arbitrary menu other than `FPT_Menu` / `FPT_ItemMenu`.
- Window positions or sizes.
- Edition: FL **Fruity** has no audio recording; `ui.getVersion()` text starts with "Fruity Edition".

---

## 2. Default keyboard shortcuts most useful in macros (Mac)

The manual's mapping: Ctrl → **Cmd**, Alt → **Opt**, Backspace → delete, Delete → **fn+delete** (forward delete, key code 0x75), Insert → **fn+return**.

**Mac exceptions**
- Some shortcuts really use **Control** on Mac: mixer track properties Ctrl+Return, full screen **Ctrl+Cmd+F** (FL 2024.2).
- **Ctrl+click = right-click** (fixed in 26.1.1). Never hold Control during a left click.
- ⌘Space (pause) conflicts with Spotlight.
- **⌘Q quits FL.** Piano Roll Quick quantize moved to **⌥⌘Q** in 25.1.5.
- ⚠ **⌘H** (FL "panic") and **⌘M** (metronome) are the standard macOS Hide and Minimize. Since FL 2024.2 added the standard macOS menu items, test whether they still reach FL.

**Single-letter shortcuts** (R, L, S, P, B…) only work when "Typing keyboard to piano" (⌘T) is **off**, and FL cannot report that state. Prefer script actions or shortcuts with modifiers.

**Keyboard layout (AZERTY).** Since FL 2025, shortcuts follow the layout's character (fix 19856), and menu accelerators work on non-US layouts (fixes 18718, 20467). FL Shortcuts must turn the character into a key code for the current layout (TIS/UCKeyTranslate) and set the Unicode string on the CGEvent. Hard-coded QWERTY key codes will not work.

**Numpad.** Use keypad key codes even on a laptop: + 0x45, − 0x4E, digits 0x52–0x5C, * 0x43, / 0x4B. Numpad digits select patterns; the top-row digits mute channels.

### Global and transport
| Mac | Action |
|---|---|
| Space | Play/Stop (↺) |
| Ctrl/⌘Space | Pause (Spotlight conflict) |
| R | REC on/off ↺ |
| L | Pattern/Song ↺ |
| ⌘M / ⌘P / ⌘I / ⌘B / ⌘E | Metronome / precount / wait for input / blend notes / step edit (all ↺) |
| ⌘T | Typing keyboard to piano ↺ |
| ⌘H | Stop sound (panic) |
| ⌘Z | Undo/redo toggle |
| ⌥⌘Z | Step back in the undo history |
| Backspace | Snap line/none |
| numpad 0 / * / ÷ | Fast forward / next bar / previous bar |

### Files
| Mac | Action |
|---|---|
| ⌘S | Save |
| ⌘N | Save new version (or "save to new project folder") |
| ⇧⌘S | Save As (but with the **Mixer** focused the table lists "Save mixer track state" ⚠) |
| ⌘O | Open |
| ⌥0–9 | Recent projects |
| ⌘R | Export WAV |
| ⇧⌘R | Export MP3 / OGG |
| ⇧⌘M | Export MIDI |
| ⇧⌘H | Arrange windows |

### Windows
| Mac | Action |
|---|---|
| F5 / F6 / F7 / F9 | Playlist / Channel Rack / Piano Roll / Mixer (toggles ↺) |
| ⌥F8 | Browser |
| F8 | Plugin picker |
| ⌘F8 | Project picker |
| F10 | MIDI settings |
| F11 | Project info |
| F12 | Close all windows |
| Tab | Cycle windows |
| Esc | Close window |
| Return | Maximise/minimise the Playlist |
| F3 | Tool menu of the active window |

### Patterns
| Mac | Action |
|---|---|
| numpad 1–9 / + / − | Select pattern / next / previous |
| F4 | Next empty pattern, with naming dialog |
| ⇧F4 | First empty pattern |
| ⌘F4 (shortcuts page) or ⌘4 (Patterns menu page) | Next empty without naming. The two pages disagree ⚠ |
| F2 | Rename/colour the pattern |
| ⌥C | Clone pattern (Patterns menu). Conflicts with clone channel |

### Channel Rack (focus required)
| Mac | Action |
|---|---|
| ↑ / ↓ | Select channel |
| 1–0 (top row) | Mute the first 10 channels |
| ⌘1–0 | Solo the first 10 channels |
| ⌥C | Clone channel |
| ⌥⌦ | Delete channel |
| ⌥G | Group |
| ⌥Z / ⌥U | Zip / unzip |
| ⌘L | Route selected channels to free mixer tracks |
| ⇧⌘← / → | Rotate steps |
| ⌥M | Mixer track selectors |

### Mixer (focus required)
| Mac | Action |
|---|---|
| S | Solo ↺ |
| ⌥S | Solo with routed tracks |
| F2 | Rename the track |
| ⌘L | Link selected channels to this track |
| ⇧⌘L | Link starting from this track |
| ⌥L | Select linked channels |
| ⌥← / → | Move the track |
| **⌥R** | Render armed tracks to WAV |
| **⇧⌥R** | Render selected tracks |
| Ctrl+Return | Track properties |
| ⌘A | Select all tracks |
| ⌥W | Waveform view |
| ⇧E | Load Edison on the track ready to record (from the audio recording page ⚠) |

### Playlist (focus required)
| Mac | Action |
|---|---|
| P / B / D / E / C / T / S / Y / Z | Pencil / paint / delete / select / slice / mute / slip / play / zoom tools |
| Home | Go to start |
| ⌥T or ⌘T | Time marker (⌘T toggles typing-to-piano when the Playlist is not focused!) |
| ⌥* / ⌥÷ | Next/previous marker |
| ⌘A / ⌘D | Select all / deselect |
| ⌘B | Duplicate |
| ⌥⌘C | Consolidate |
| ⌘P | **Performance mode** (precount elsewhere!) |
| ⌥P | Picker panel |
| ⇧4 / ⇧5 | Show all / zoom to selection |
| ⇧Q | Quantize clip starts |
| ⇧⌥T | Time signature |

### Piano Roll (focus required)
| Mac | Action |
|---|---|
| Same tool letters, plus F / G / H / J / K | Channel above / below |
| ⌥Q | Quantize dialog |
| ⌥⌘Q | Quick quantize |
| ⇧Q | Quantize starts |
| ⌘L | Quick legato |
| ⌘U | Quick chop |
| ⌘G | Glue |
| ⌘↑ / ↓ | Octave up / down |
| ⇧↑↓←→ | Move notes |
| ⌘B | Duplicate |
| ⌘A / ⌘D | Select all / deselect |
| ⌥A / ⌥E / ⌥S / ⌥R / ⌥U / ⌥F / ⌥K / ⌥L / ⌥O / ⌥W / ⌥X / ⌥Y | Arpeggiate / Riff machine / Strum / Randomize / Chop / Flam / Limit / Articulate / LFO / Claw / Scale levels / Flip |
| ⌥P | Chord progression |
| ⌘M | Import MIDI |
| ⌥⌘Y | **Run the last Piano Roll script again** |

### Browser and plugin picker
- Browser: ↑↓ to navigate, ⇧↑↓ to step with preview, Return to replace the channel with the item.
- Plugin picker (F8): **typing the name filters the list**, ↑↓ / ←→ navigate. Double-clicking an instrument loads it into a new channel; double-clicking an effect loads it into the selected mixer track. Whether Return loads it is untested ⚠.

### Shortcuts whose meaning depends on the focused window
Run `ui.setFocused(wid)` (or `showWindow` + `setFocused`) before these.

| Keys | Meanings |
|---|---|
| ⌘P | Precount, or Performance mode (Playlist) |
| ⌘T | Typing-to-piano, or add marker (Playlist / Piano Roll) |
| ⌘B | Blend notes, or duplicate (Playlist / Piano Roll) |
| ⌘E | Step edit, or Edison (Mixer) |
| ⌘M | Metronome, or import MIDI (Piano Roll) |
| ⌘L | Route to free track (Channel Rack), link (Mixer), or legato (Piano Roll) |
| ⌘I | Wait for input, or insert controller value (Piano Roll) |
| S | Solo (Mixer), slip tool (Playlist), or slide (Piano Roll) |
| ⇧⌘S | Save As, or Save mixer track state (Mixer) |
| ⌥C | Clone channel, or clone pattern |

FL 2024+ also has **Options › General settings › Manage shortcuts**, but it only covers the browser and pickers, the MIDI import window, and audio-clip double-click.

---

## 3. Menus reachable without a script

### A. The macOS menu bar (Accessibility, by title)

Available since FL 2024.2.

| Menu | Useful items |
|---|---|
| **File** | New; New from template ›; Open (⌘O); Save; Save as; Save new version; Save as template; Import; **Export › Wave (⌘R) / mp3 / ogg / MIDI / All playlist tracks › (From song start / From track start / Time selection) / Zipped loop package / Project bones / Project data files**; Recent projects; Revert to last backup |
| **Edit** | Undo, Cut, Copy, Paste |
| **Add** | Channel ›, Effect ›, Plugin picker, Automation for last tweaked parameter, Pattern |
| **Patterns** | Find first/next empty; Rename and color; Clone; Insert one; Delete; Move up/down; Split by channel; **Quick render as audio clip / Render as audio clip / Render and replace**; Set time signature; Transpose |
| **View** | Windows; Tempo tapper; Script output (Interpreter, Edit script, Reload); Plugin performance monitor |
| **Options** | MIDI / Audio / General / File settings; Project info / general settings; switches (Typing to piano, Metronome, Recording precount, Start on input, Blend, Step edit, Loop record); Multi-link |
| **Tools** | One-click audio recording ("into Edison" / "into Playlist as an Audio Clip"); **Panic › Cancel recording**; Macros; Select unused channels; Purge unused audio clips; Reset empty playlist tracks; **Score logger › Dump score log to selected pattern / Clear log**; Audio logger |

Titles depend on FL's interface language: match the English title plus known localised variants. FL's own in-window menu bar (FILE EDIT … in the toolbar) is the click fallback. Once it is open, the arrow keys and Return work (keyboard bugs fixed in 25.1.4).

### B. FL context menus (popup windows: letters and arrows)

| Menu (how to open it) | Tasks that need it | Letters known so far |
|---|---|---|
| **Mixer track**: right-click the track header (⚠ maybe `FPT_ItemMenu`) | **File › Open mixer track state / Save mixer track state / Browse states**; Rename, color & icon (F2); **Assign to new audio track(s)**; Unassign; Open audio editor (and record); Reset track; Routing › (Route selected channels to this track ⌘L, Sidechain, Create submix…); Group; Layout (Dock to, Move, **Delete**, **Insert**, Trim unused) | **F** File › **O** Open (verified by the repo; S = Save and B = Browse are likely ⚠); **D** Delete (changelog) |
| **Mixer window menu**: arrow at the top left of the Mixer | **Disk recording › Render armed tracks (⌥R) / Render selected (⇧⌥R) / Auto-unarm / Auto-create audio clips / Latency compensation / bit depth**; PDC; View | to learn |
| **REC button**: right-click | **Recording filter** (Automation / Notes / Audio / Clips), **Recording starts playback**, **Disarm on stop**, quantize. ⌥-click opens "What do you want to record" when that prompt is disabled | to learn |
| **Mixer input selector**: click / right-click | Choose the input (stereo list above, mono below; **choosing an input arms the track**). Right-click = **Auto-map** inputs onto the following tracks. ⌥-click = reset to (none) (FL 26.1+) | the item list depends on the audio interface, so use a learned click |
| **Mixer track REC icon**: right-click | File name and location dialog for the recording | — |
| **Playlist track header**: right-click | **Track mode › Audio track › Insert N** (link to a mixer track) | to learn |
| **Channel button**: right-click | Rename, Clone (⌥C), Delete, Route to free mixer track, "Assign to free mixer track" (accelerator added in 25.2.5), Replace | to learn |

**Accelerator letters.** They can change between versions and languages, so learn them per FL version. The universal fallback is ↓×N, → to open a submenu, Return. Wait for the popup window (W) before typing, and move the pointer away from the menu first (the repo already does this).

---

## 4. Proposed macro blocks (79)

**COND** marks a block that can serve as a condition. Columns: Label | Effect | How | Parameters | Reliability.

### Transport (8)
| # | Label | Effect | How | Parameters | Reliability |
|---|---|---|---|---|---|
| T1 | **Lecture / Pause / Stop** | Puts the transport in the requested state | S: `isPlaying()` then `start()` or `stop()`; without a script K Space (↺) | state | ✔ (with S) |
| T2 | **Aller à la mesure…** | Moves the playhead | S `setSongPos((N−1)*getRecPPB(), 2)`; bar 1 = start; K Home in the Playlist | bar | ✔ |
| T3 | **Mode Song / Pattern** | Sets the mode | S `getLoopMode` → `setLoopMode`; K L (↺) | mode | ✔ |
| T4 | **Tempo** | Sets the BPM | S `mixer.setCurrentTempo(x)`, otherwise `processRECEvent(REC_Tempo, x*1000, REC_Control)` | BPM (10–522) | ✔ |
| T5 | **Signature rythmique** | e.g. 3/4 | S `setNumerator/Denominator` (38); otherwise K ⇧⌥T + dialog | n/d | ✔ |
| T6 | **Métronome ON/OFF** | Sets the metronome | S `isMetronomeEnabled` → `FPT_Metronome` (or K ⌘M if different) | state | ✔ |
| T7 | **Marqueur** | Adds a marker / goes to the next or previous one | S `addAutoTimeMarker(getSongPos(2), name)` / `jumpToMarker(±1)` | name, direction | ✚ / ✔ |
| T8 | **Couper le son (panique)** | Stops hanging notes | K ⌘H (⚠ macOS Hide) | — | ✔ |

### Recording / Enregistrement (8)
| # | Label | Effect | How | Parameters | Reliability |
|---|---|---|---|---|---|
| E1 | **REC armé ON/OFF** | Main REC button | S `isRecording` → `record()` (action 40 `recon`) | state | ✔ |
| E2 | **Démarrer l'enregistrement** | REC on, then play | S E1(ON) + T1(play); then W: if a "What do you want to record" popup appears, letter or Esc | — | ✔ ⚠ popup |
| E3 | **Options d'enregistrement** | Precount / loop record / wait for a note / step edit | S read (`isPrecountEnabled`, `isLoopRecEnabled`, `isStartOnInputEnabled`, `getStepEditMode`) then FPT_CountDown / LoopRecord / WaitForInput / `setStepEditMode` | option, state | ✔ |
| E4 | **Armer la piste ON/OFF** | Arms the selected mixer track | S `isTrackArmed(t)` → `armTrack(t)` (actions 9/39) | state | ✔ |
| E5 | **Désarmer toutes les pistes** | Unarms every track | S loop `isTrackArmed` → `armTrack` | — | ✔ |
| E6 | **Choisir l'entrée audio** | Mixer input N (arms the track) | C learned (selector, then item); FL 26.1+: ⌥-click = (none) first | input | ⚠ depends on layout and interface |
| E7 | **Récupérer ce que je viens de jouer** | Score log → selected pattern | S `general.dumpScoreLog(sec, 1)`; or M Tools › Score logger | duration (s) | ✚ |
| E8 | **Annuler la prise en cours** | Cancels the recording and deletes the .wav | M AX Tools › Panic › Cancel recording | — | ⚠ |

### Mixer (10)
| # | Label | Effect | How | Parameters | Reliability |
|---|---|---|---|---|---|
| X1 | **Sélectionner la piste** | By number / name contains / next / previous / last clicked | S `setActiveTrack` (27) or `setTrackNumber(i, 1)`; name: `getTrackName` loop (case-insensitive); validate 1…`trackCount()`−2 | target | ✔ (fails if not found) |
| X2 | **Renommer / colorer la piste** | Sets the name and colour | S `setTrackName`, `setTrackColor`; otherwise K F2 + text + Return | name, colour | ✔ |
| X3 | **Mute / Solo de la piste** | Mute or solo the track, or clear all solos | S `muteTrack(t, v)` / `soloTrack(t, v, mode)` / loop | state, solo mode | ✔ |
| X4 | **Volume / Pan de la piste** | Absolute dB or ±dB, pan | S dichotomy on `getTrackVolume(t, 1)`; `setTrackPan` | dB, pan | ✔ |
| X5 | **Effets de la piste ON/OFF** | FX slot bypass | S `enableTrackSlots(t, value)` (19) | state | ✔ |
| X6 | **Envoi vers une piste** | Send with a level | S `setRouteTo(t, d, 1, True)` + `setRouteToLevel` (36) | destination, level | ✔ |
| X7 | **Relier l'instrument à la piste** | Selected channel → selected track | S `setTargetFxTrack(ch, t)` (28) or `linkChannelToTrack` (23); K ⌘L (Mixer focus) | — | ✔ |
| X8 | **Charger un état de piste** | `.fst` onto the selected track | M right-click on the row (or `FPT_ItemMenu` ⚠) → W menu → F → O → W Open panel → chooseFile (⌘⇧G path) or the user chooses → W closed (existing `trackMenu`) | file or "ask" | ⚠ medium |
| X9 | **Enregistrer l'état de piste** | Saves the track state to `.fst` | M F → S (⚠), or ⇧⌘S with Mixer focus (⚠) → W Save panel (name prefilled with the track name since 26.1) → text → Return → W | name, folder | ⚠ |
| X10 | **Rendre les pistes armées** | Bounce of the armed or selected tracks to WAV | K ⌥R / ⇧⌥R (Mixer focus), or M Mixer menu › Disk recording → W dialogs | armed/selected | ⚠ |

### Channel Rack (8)
| # | Label | Effect | How | Parameters | Reliability |
|---|---|---|---|---|---|
| C1 | **Sélectionner l'instrument** | By number / name contains / next / previous | S `selectOneChannel` (8) + name loop; otherwise `FPT_ChannelJog` | target | ✔ |
| C2 | **Interface de l'instrument** | Opens or closes the plugin window | S `showEditor(ch, 1/0)` | state | ✔ |
| C3 | **Réglages de l'instrument** | Mute / solo / volume / pan | S `muteChannel(ch, v)`, `soloChannel(ch, v)`, `setChannelVolume/Pan` | values | ✔ |
| C4 | **Remplir les pas** | One step every N (kick on the beats…) | S `setGridBit` loop (option: clear first) | N, offset | ✔ |
| C5 | **Cloner l'instrument** | Clones the selected channel | K ⌥C (Channel Rack focus) | — | ✚ |
| C6 | **Router vers une piste libre** | Selected channels → free mixer tracks | K ⌘L (Channel Rack focus) | — | ✚ |
| C7 | **Ajouter un instrument** | Loads a plugin by name | S `showPicker(0, 0)` (41) or K F8 → type the name → Return (⚠) / double-click | plugin name | ✚ ⚠ |
| C8 | **Swing global** | Main shuffle | S `setShuffle(v)` (42) | % | ✔ |

### Patterns (6)
| # | Label | Effect | How | Parameters | Reliability |
|---|---|---|---|---|---|
| P1 | **Nouveau pattern** | Next empty pattern, named | S `findFirstNextEmptyPat(2)` + `setPatternName(patternNumber(), name)` | name, colour | ✚ |
| P2 | **Aller au pattern** | By number / name / ± | S `jumpToPattern`; K numpad ± | target | ✔ |
| P3 | **Cloner le pattern** | Clones the current pattern | S `clonePattern()` (25) | — | ✚ |
| P4 | **Longueur du pattern** | In beats | S `setPatternLength(i, n)` (39; reliable from 26.1) | beats | ✔ |
| P5 | **Vider le pattern** | Clears the pattern | S `clearPattern(i)` (44 = 26.1.3+) | — | ✔ |
| P6 | **Rendre le pattern en audio** | Quick render as audio clip | M AX Patterns › Quick render as audio clip | — | ✚ ⚠ |

### Playlist (3)
| # | Label | Effect | How | Parameters | Reliability |
|---|---|---|---|---|---|
| L1 | **Outil Playlist / Piano Roll** | Pencil, paint, delete, mute, slice, select, zoom, play, slip | S `playlist.selectTool(EETool_*)` (40); K tool letters (focus + typing-to-piano OFF) | tool | ✔ |
| L2 | **Mute / Solo piste Playlist** | By number or name | S `playlist.muteTrack/soloTrack(i, v)` | state | ✔ |
| L3 | **Mode Performance ON/OFF** | Sets performance mode | S read `getPerformanceModeState` + K ⌘P (Playlist focus) | state | ✔ |

### Piano Roll (4)
| # | Label | Effect | How | Parameters | Reliability |
|---|---|---|---|---|---|
| R1 | **Ouvrir le Piano Roll de l'instrument** | Opens it | S `openEventEditor(getRecEventId(ch)+REC_Chan_PianoRoll, EE_PR)` (9), otherwise `showWindow(3)` | channel | ✔ |
| R2 | **Quantifier** | Quick or dialog | S `channels.quickQuantize(ch)` (9); K ⌥⌘Q / ⌥Q | mode | ✔ / ✚ |
| R3 | **Édition rapide** | Legato / chop / glue / ±octave / duplicate / select all | K ⌘L, ⌘U, ⌘G, ⌘↑↓, ⌘B, ⌘A (Piano Roll focus) | action | ✚ |
| R4 | **Outil génératif ou script** | Riff machine, arpeggiate, strum, randomize, chord progression, or rerun the last script | K ⌥E / ⌥A / ⌥S / ⌥R / ⌥P / ⌥⌘Y → W dialog | tool | ✚ |

### Windows / Fenêtres (4)
| # | Label | Effect | How | Parameters | Reliability |
|---|---|---|---|---|---|
| F1 | **Afficher une fenêtre** | Mixer / Channel Rack / Playlist / Piano Roll / Browser | S `showWindow(w)` + `setFocused(w)`; K F9 / F6 / F5 / F7 / ⌥F8 (↺) | window | ✔ |
| F2 | **Masquer / tout fermer** | Hide one window, or close all | S `hideWindow(w)` (5); K F12 | window | ✔ |
| F3 | **Ouvrir un sélecteur** | Plugin / project picker | S `showPicker(mode, cat)` (41); K F8 / ⌘F8 | type | ✔ |
| F4 | **Message dans FL** | Text in the hint bar | S `ui.setHintMsg(text)` | text | ✔ |

### Files and presets / Fichiers, Presets (6)
| # | Label | Effect | How | Parameters | Reliability |
|---|---|---|---|---|---|
| D1 | **Enregistrer le projet** | Normal save or new version | S `FPT_Save` / `FPT_SaveNew`; K ⌘S / ⌘N; W a dialog if the project is new | mode | ✔ / ✚ |
| D2 | **Enregistrer sous…** | Save under a new name | K ⇧⌘S (not with the Mixer focused) → W panel → text → Return → W | name, folder | ⚠ |
| D3 | **Ouvrir un projet** | File or recent project | K ⌘O → W → chooseFile; or ⌥1…0 (W possible "save changes?" prompt) | path / rank | ⚠ |
| D4 | **Exporter** | WAV / MP3 / MIDI (stems: learned click on "Split mixer tracks") | K ⌘R / ⇧⌘R / ⇧⌘M → W Save panel → path → Return → W render window → Return or learned click on "Start" (⚠) → W closed | format, name | ⚠ |
| D5 | **Annuler / Rétablir** | Undo or redo steps | S `undoUp()` / `undoDown()`; K ⌥⌘Z / ⌘Z (↺) | count | ✔ (S) |
| D6 | **Commande du menu FL** | Any item of the macOS menu bar | AX by title path, e.g. File › Export › MIDI file | path | ✔ AX |

### Plugins (4)
| # | Label | Effect | How | Parameters | Reliability |
|---|---|---|---|---|---|
| G1 | **Preset suivant / précédent** | For the selected channel or the focused effect | S `plugins.next/prevPreset(ch)` or `(track, slot)` (10) | direction | ↺ |
| G2 | **Ouvrir un effet de la piste** | Opens slot N | S `mixer.focusEditor(t, slot)` (25) | slot | ✔ |
| G3 | **Régler un paramètre de plugin** | By parameter name; also dry/wet | S `getParamName` loop → `setParamValue`; `setPluginMixLevel` (37) | name, value | ✔ |
| G4 | **Ajouter un effet** | Into the selected track | S `showPicker(0, 1)` or K F8 → name → double-click / Return (⚠) | name | ✚ ⚠ |

### Keyboard / Clavier (3)
| # | Label | Effect | How | Parameters | Reliability |
|---|---|---|---|---|---|
| K1 | **Raccourci FL** | Any combo (blocklist: ⌘Q, ⌘W, Ctrl+click…) | A CGEvent (layout-aware); optional "focus window X first" | combo, window | ↺ in general |
| K2 | **Taper un texte** | Names, picker search, paths | A character by character, using the current layout | text | ✔ |
| K3 | **Naviguer dans un menu** | Letter(s), ↓×N, →, Return, Esc | A, after W menu | sequence | ⚠ |

### Mouse / Souris (2)
| # | Label | Effect | How | Parameters | Reliability |
|---|---|---|---|---|---|
| M1 | **Clic à un point appris** | Left / right / double / ⌥-click relative to the FL window | A (existing anchors) | point, button | ⚠ |
| M2 | **Clic droit sur la piste Mixer** | Right-click on the last clicked or selected track's row | A (`TrackMemory`) | — | ⚠ |

### Waits / Attendre (5)
| # | Label | Effect | How | Parameters | Reliability |
|---|---|---|---|---|---|
| W1 | **Pause** | Waits a fixed time | A | ms | ✔ |
| W2 | **Attendre une fenêtre / boîte de FL** | Opening or closing | A window list (count, layer, bounds). Titles: AX (`kCGWindowName` needs Screen Recording) | timeout | ✔ |
| W3 | **Attendre le menu** | A popup is open | A new window, or S `ui.isInPopupMenu()` | timeout | ✔ |
| W4 | **Attendre la lecture** | Until it stops / until bar N / until REC on | S polling `isPlaying`, `getSongPos(2)`, `isRecording` (each poll keeps the script awake) | condition, timeout | ✔ |
| W5 | **Attendre l'accusé du script** | Ack CC 119 ≠ 0 | A (existing) | — | ✔ |

### Conditions (9, all COND)

All script reads except C9.

| # | Label | Reads |
|---|---|---|
| Q1 | **Si transport** | playing / REC armed / recording (`isPlaying`, `isRecording`, both) |
| Q2 | **Si piste Mixer sélectionnée** | armed / muted / solo / **name contains…** / FX on / signal present (`getTrackPeaks > threshold` ⚠) |
| Q3 | **Si instrument sélectionné** | name contains… / muted / plugin = … (`getChannelName(selectedChannel())`, `getPluginName`) |
| Q4 | **Si option** | Song mode / metronome / precount / loop record / wait for input / step edit / performance mode |
| Q5 | **Si fenêtre FL** | X has focus or is visible (`getFocused` / `getVisible`), a menu is open (`isInPopupMenu`), the focused plugin contains… (`getFocusedPluginName` / `getFocusedFormCaption`) |
| Q6 | **Si pattern** | current pattern empty (`isPatternDefault(patternNumber())`) / number = / name contains |
| Q7 | **Si projet modifié** | `getChangedFlag() > 0` |
| Q8 | **Si tempo** | =, < or > X (`getCurrentTempo()`) |
| Q9 | **Si boîte de dialogue FL ouverte / FL au premier plan / version FL ≥ …** | A window list; `getVersion()` / API |

---

## 5. Five example macros (as block sequences)

### 1. « Enregistrement rapide » (voice)
1. Q1 if recording → T1 Stop
2. F1 Mixer
3. X1 select the last clicked track (or the one whose name contains "Voix")
4. X8 load the track state: Voix.fst, through the context menu (F, O) → W panel → chooseFile → W closed
5. E6 audio input 1 (this arms the track)
6. E4 arm the track ON (makes sure)
7. T3 Song mode
8. E3 precount ON, loop record OFF
9. E1 REC armed ON
10. F4 message "Prêt — Espace pour enregistrer"
11. Microphone-feedback check (existing `feedbackCheck`)

### 2. « Nouveau beat »
1. T1 Stop
2. P1 new pattern "Beat"
3. P4 length 16 beats
4. T4 tempo 140
5. T5 4/4
6. T3 Pattern mode
7. T6 metronome ON
8. F1 Channel Rack
9. C1 channel "Kick" → C4 one step in 4
10. C1 "Hat" → C4 one step in 2, offset 1
11. C1 "Snare" → C4 one step in 8, offset 4
12. T1 Play

### 3. « Bounce piste »
**Version A, with the export dialog:**
1. Q1 if playing → T1 Stop
2. X1 track whose name contains {nom}
3. X3 Solo ON (mode 1, with sources)
4. D4 Export WAV: ⌘R → W Save panel → K2 "{nom}" → Return → W render window → Return/Start → W closed
5. X3 clear all solos
6. F4 "Bounce terminé"

**Version B, FL's own bounce:**
1. E5 unarm all tracks
2. X1 target track
3. E4 arm ON
4. X10 render armed tracks (⌥R) → W dialogs
5. E5 unarm all

### 4. « Punch-in »
1. Q1 if playing → T1 Stop
2. Q2 if the track is not armed → E4 arm ON
3. E3 loop record OFF, precount ON
4. T3 Song mode
5. T2 bar {début}
6. E1 REC ON
7. T1 Play
8. W4 until bar {fin} (timeout)
9. T1 Stop
10. E1 REC OFF
11. D1 save

### 5. « Récupérer l'impro » (score logger)
1. C1 keep the selected channel (Q3 if none → abort)
2. P1 new pattern "Impro"
3. E7 dump the score log (120 s)
4. R1 open the Piano Roll of the channel
5. R2 quick quantize
6. F4 message

**Bonus, « Fin de session »:** Q7 if the project is modified → D1 new version → D4 export MP3 named after `getProjectTitle()`.

---

## 6. Notes for FL Shortcuts's implementation

- **The protocol needs to grow.** Today a frame carries only an action id (1–42, §6), but blocks need parameters: track or channel name, BPM, dB, bar, tool, state ON/OFF.
  - Suggestion: an authenticated parameter frame (for example CC 112–116 for slot + a 14-bit value, and text as 7-bit ASCII), covered by the MAC.
  - Plus a **state READ** request that answers with one snapshot frame: bits for playing / REC / armed / mute / solo / loopMode / metronome / precount / loopRec / waitInput / stepEdit / popup open / changed flag / focused window, plus the selected track index and name, and the selected channel index and name.
  - Conditions (including "name contains") are then evaluated in the app, after one round trip.
- **Every "set to state" block works without the script only as a blind toggle.** Mark it "non idempotent sans lien MIDI" in the interface.
- **Window titles.** `kCGWindowName` from the window list needs the Screen Recording permission. Use counts, layers and bounds, and Accessibility for titles (already granted). Test whether FL's own popups expose anything to Accessibility.
- **Side finding (bug in the repo).** In `Resources/device_FLShortcut.py`, `_a_newpat` uses `_const("FFNEP_DontPromptName", 1)`, but the real constant is **2** (`1 << 1` in the stubs; the manual also says 2). It only matters if `midi.FFNEP_DontPromptName` is ever missing: with 1, the fallback would pass the wrong flag. I did not change it.

---

## Sources

**Official Image-Line manual**
- MIDI scripting: https://www.image-line.com/fl-studio-learning/fl-studio-online-manual/html/midi_scripting.htm
- Keyboard and mouse shortcuts: https://www.image-line.com/fl-studio-learning/fl-studio-online-manual/html/basics_shortcuts.htm
- Mixer menu and mixer track menu: https://www.image-line.com/fl-studio-learning/fl-studio-online-manual/html/mixer_mixermenu.htm
- Mixer track properties: https://www.image-line.com/fl-studio-learning/fl-studio-online-manual/html/mixer_trackprops.htm
- Audio recording: https://www.image-line.com/fl-studio-learning/fl-studio-online-manual/html/recording_audio.htm
- Transport panel and REC button: https://www.image-line.com/fl-studio-learning/fl-studio-online-manual/html/toolbar_panels.htm
- Main menus: …/html/menu_file.htm, menu_edit.htm, menu_add.htm, menu_patterns.htm, menu_view.htm, menu_options.htm, menu_tools.htm
- Piano Roll menu: …/html/pianoroll_menu.htm
- Channel Rack: …/html/channelrack.htm
- Browser and plugin picker: …/html/browser.htm
- Export and render dialog: …/html/fformats_save_export.htm
- Manage shortcuts: …/html/envsettings_general.htm
- Changelog: https://www.image-line.com/fl-studio-learning/fl-studio-online-manual/html/WhatsNew.htm (entries 15333, 18105, 18134, 19579, 19856, 18718, 20467, 21561, 21576, 22015, 22064, 22492, 22689/22725, 22329/21539/20735)

**API stubs**
- https://il-group.github.io/FL-Studio-API-Stubs/
- https://github.com/IL-Group/FL-Studio-API-Stubs (cloned; commit 9b4c7fa of 13 May 2026, marked unmaintained)
- https://github.com/MaddyGuthridge/FL-Studio-API-Stubs (original author's version)

**Forum (in-window menus on macOS)**
- https://forum.image-line.com/viewtopic.php?p=1863139

**Repo context**
- `/home/user/fl-shortcut/PROTOCOL.md`
- `/home/user/fl-shortcut/MACROS.md`
- `/home/user/fl-shortcut/audit/04_compatibilite_versions.md`
- `/home/user/fl-shortcut/Resources/device_FLShortcut.py`
