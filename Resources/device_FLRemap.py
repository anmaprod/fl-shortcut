# name=FL Remap
# url=
"""
Script MIDI pour FL Studio : reçoit les messages envoyés par l'appli FL Remap
(port MIDI virtuel "FL Remap", canal 16) et exécute l'action correspondante.

Les numéros de CC doivent correspondre à FLAction.cc dans Sources/FLRemap/Model.swift.
"""

import midi
import transport
import ui
import general
import mixer
import channels
import patterns

MIDI_CHANNEL = 15  # canal 16, 0-indexé


def _show(window_id):
    ui.showWindow(window_id)
    ui.setFocused(window_id)


def toggle_playlist_mixer():
    if ui.getFocused(midi.widMixer):
        _show(midi.widPlaylist)
    else:
        _show(midi.widMixer)


def mute_selected():
    if ui.getFocused(midi.widMixer):
        mixer.muteTrack(mixer.trackNumber())
    elif ui.getFocused(midi.widChannelRack):
        channels.muteChannel(channels.selectedChannel())
    else:
        ui.setHintMsg("FL Remap : mute dispo dans le Mixer ou le Channel Rack")


def solo_selected():
    if ui.getFocused(midi.widMixer):
        mixer.soloTrack(mixer.trackNumber())
    elif ui.getFocused(midi.widChannelRack):
        channels.soloChannel(channels.selectedChannel())
    else:
        ui.setHintMsg("FL Remap : solo dispo dans le Mixer ou le Channel Rack")


def jump_pattern(delta):
    target = patterns.patternNumber() + delta
    if 1 <= target <= patterns.patternCount():
        patterns.jumpToPattern(target)


ACTIONS = {
    20: transport.start,                       # play / pause
    21: transport.stop,
    22: transport.record,
    23: general.undoUp,                        # annuler
    24: general.undoDown,                      # rétablir
    25: lambda: _show(midi.widPlaylist),
    26: lambda: _show(midi.widMixer),
    27: lambda: _show(midi.widChannelRack),
    28: lambda: _show(midi.widPianoRoll),
    29: lambda: _show(midi.widBrowser),
    30: toggle_playlist_mixer,
    31: mute_selected,
    32: solo_selected,
    33: lambda: transport.globalTransport(midi.FPT_Metronome, 1),
    34: transport.setLoopMode,                 # Pattern <-> Song
    35: lambda: jump_pattern(1),
    36: lambda: jump_pattern(-1),
    37: ui.nextWindow,
}


def OnInit():
    ui.setHintMsg("FL Remap prêt")


def OnMidiMsg(event):
    if event.midiId != midi.MIDI_CONTROLCHANGE or event.midiChan != MIDI_CHANNEL:
        return
    action = ACTIONS.get(event.data1)
    if action is None or event.data2 == 0:
        return
    event.handled = True
    try:
        action()
    except Exception as exc:  # on ne veut jamais faire planter le script
        ui.setHintMsg("FL Remap erreur : %s" % exc)
