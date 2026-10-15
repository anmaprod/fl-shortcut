// Bloc « Carte son branchée » : la carte son (USB, Thunderbolt…) devient la sortie et l'entrée du Mac. FL, réglé une
// fois sur « Default audio device » (Output) et « Default input device » (Input) dans Options › Audio settings, la
// suit tout seul (vérifié sur la vidéo de l'utilisateur : la ligne Status de FL passe de « 1x2 outputs » à
// « 2x2 outputs » quand la SSL 2+ devient la sortie du Mac). Aucun clic dans FL ; CoreAudio n'est interrogé qu'au
// moment du bloc, rien ne tourne au repos.
import CoreAudio
import Foundation

/// Un périphérique audio, tel que le bloc en a besoin.
struct AudioDeviceInfo: Equatable {
    let id: AudioObjectID
    let uid: String
    let name: String
    let transport: UInt32
    /// Nombre de flux d'entrée et de sortie (0 : pas d'entrée, ou pas de sortie).
    let inputs: Int
    let outputs: Int
}

enum SoundCard {
    /// Carte choisie la dernière fois (identifiant CoreAudio), préférée si plusieurs cartes sont branchées.
    static let preferredKey = "soundCard.lastUID"

    /// Cartes son : branchées en USB, Thunderbolt, FireWire, PCI ou AVB (pas les haut-parleurs du Mac, l'HDMI, le
    /// Bluetooth, AirPlay ni les périphériques virtuels ou agrégés).
    static let externalTransports: Set<UInt32> = [
        kAudioDeviceTransportTypeUSB, kAudioDeviceTransportTypeThunderbolt, kAudioDeviceTransportTypeFireWire,
        kAudioDeviceTransportTypePCI, kAudioDeviceTransportTypeAVB,
    ]

    /// La carte à utiliser : une carte externe avec une sortie, de préférence avec une entrée aussi ; parmi elles,
    /// celle choisie la dernière fois si elle est branchée, sinon la première.
    static func choose(_ devices: [AudioDeviceInfo], preferredUID: String?) -> AudioDeviceInfo? {
        let cards = devices.filter { externalTransports.contains($0.transport) && $0.outputs > 0 }
        let withInput = cards.filter { $0.inputs > 0 }
        let pool = withInput.isEmpty ? cards : withInput
        return pool.first { $0.uid == preferredUID } ?? pool.first
    }

    enum Outcome: Equatable {
        case done(name: String, input: Bool)
        case noCard
        case failed(String)
    }

    /// Met la carte en sortie (et en entrée si elle en a une) par défaut du Mac.
    static func apply(defaults: UserDefaults = .standard) -> Outcome {
        guard let card = choose(list(), preferredUID: defaults.string(forKey: preferredKey)) else { return .noCard }
        guard setDefault(kAudioHardwarePropertyDefaultOutputDevice, card.id) else {
            return .failed("macOS a refusé de changer la sortie audio")
        }
        let input = card.inputs > 0 && setDefault(kAudioHardwarePropertyDefaultInputDevice, card.id)
        defaults.set(card.uid, forKey: preferredKey)
        return .done(name: card.name, input: input)
    }

    // MARK: CoreAudio

    static func list() -> [AudioDeviceInfo] {
        objects(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDevices).map { id in
            AudioDeviceInfo(id: id,
                            uid: string(id, kAudioDevicePropertyDeviceUID) ?? "",
                            name: string(id, kAudioObjectPropertyName) ?? "",
                            transport: uint32(id, kAudioDevicePropertyTransportType) ?? 0,
                            inputs: objects(id, kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeInput).count,
                            outputs: objects(id, kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput).count)
        }
    }

    private static func address(_ selector: AudioObjectPropertySelector,
                                _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func objects(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> [AudioObjectID] {
        var a = address(selector, scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &a, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(object, &a, 0, nil, &size, &ids) == noErr else { return [] }
        return Array(ids.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }

    private static func uint32(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var a = address(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(object, &a, 0, nil, &size, &value) == noErr ? value : nil
    }

    private static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var a = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &a, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    private static func setDefault(_ selector: AudioObjectPropertySelector, _ device: AudioObjectID) -> Bool {
        var a = address(selector)
        var id = device
        return AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil,
                                          UInt32(MemoryLayout<AudioObjectID>.size), &id) == noErr
    }
}
