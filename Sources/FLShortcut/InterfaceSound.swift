// Sons de l'interface : sons du Mac, très discrets (volume 0,15), seulement dans les fenêtres de l'app et à la fin de
// l'Organiser. Le menu de l'icône et les fenêtres qui s'ouvrent depuis lui restent muets (FL est souvent devant et
// peut jouer). Jamais pendant l'écoute, le rangement ou le retour de l'Organiser. Coupés par le réglage « Sons de
// l'interface » (menu ⋯) ou par « Effets sonores de l'interface » de macOS. Son absent du Mac : silence.
import AppKit

enum InterfaceSoundEvent {
    case cardOpen, cardClose, creatorOpen, creatorClose, dropDetach, organiserDone

    /// Son du Mac (/System/Library/Sounds).
    var soundName: String {
        switch self {
        case .cardOpen, .creatorOpen: return "Pop"
        case .cardClose, .creatorClose: return "Bottle"
        case .dropDetach: return "Tink"
        case .organiserDone: return "Glass"
        }
    }
}

enum InterfaceSound {
    /// Réglage « Sons de l'interface » (activé par défaut).
    static let key = "interfaceSounds"
    static let volume: Float = 0.15

    /// Règle pure : réglage de l'app et de macOS activés, jamais pendant le travail de l'Organiser ; l'app doit être
    /// active, sauf pour la fin de l'Organiser (FL est devant, l'Organiser vient de l'arrêter).
    static func allowed(event: InterfaceSoundEvent, enabled: Bool, systemSounds: Bool, appActive: Bool,
                        organiserBusy: Bool) -> Bool {
        guard enabled, systemSounds, !organiserBusy else { return false }
        return event == .organiserDone || appActive
    }

    /// « Effets sonores de l'interface » de macOS (absent : activé).
    static var systemSoundsEnabled: Bool {
        let value = CFPreferencesCopyAppValue("com.apple.sound.uiaudio.enabled" as CFString,
                                              "com.apple.systemsound" as CFString)
        return (value as? NSNumber)?.boolValue ?? true
    }

    /// Joue le son de cet évènement s'il est permis. Une copie par lecture : deux sons proches se superposent.
    static func play(_ event: InterfaceSoundEvent, organiserBusy: Bool = false) {
        let enabled = UserDefaults.standard.object(forKey: key) as? Bool ?? true
        guard allowed(event: event, enabled: enabled, systemSounds: systemSoundsEnabled, appActive: NSApp.isActive,
                      organiserBusy: organiserBusy),
              let sound = NSSound(named: NSSound.Name(event.soundName))?.copy() as? NSSound else { return }
        sound.volume = volume
        sound.play()
    }
}
