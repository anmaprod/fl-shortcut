// Bloc « Carte son branchée » : la carte son (USB, Thunderbolt…) devient la sortie et l'entrée du Mac. FL, réglé une
// fois sur « Default audio device » (Output) et « Default input device » (Input) dans Options › Audio settings, la
// suit tout seul (vérifié sur la vidéo de l'utilisateur : la ligne Status de FL passe de « 1x2 outputs » à
// « 2x2 outputs » quand la SSL 2+ devient la sortie du Mac). Aucun clic dans FL ; CoreAudio n'est interrogé qu'au
// moment du bloc (ou dans sa fiche), rien ne tourne au repos.
// - La carte peut être choisie dans la fiche du bloc (retenue sur ce Mac) : elle passe avant le choix automatique.
// - Le changement est relu : si macOS garde l'ancienne sortie, le bloc échoue en le disant (il ne réussit plus en
//   silence), et le journal garde ce qu'il a vu (types de liaison et nombres de flux, jamais les noms).
import CoreAudio
import Foundation

/// Un périphérique audio, tel que le bloc en a besoin.
struct AudioDeviceInfo: Equatable, Identifiable {
    let id: AudioObjectID
    let uid: String
    let name: String
    let transport: UInt32
    /// Nombre de flux d'entrée et de sortie (0 : pas d'entrée, ou pas de sortie).
    let inputs: Int
    let outputs: Int

    var isExternal: Bool { SoundCard.externalTransports.contains(transport) }
}

enum SoundCard {
    /// Carte choisie la dernière fois (identifiant CoreAudio), préférée si plusieurs cartes sont branchées.
    static let preferredKey = "soundCard.lastUID"
    /// Carte choisie dans la fiche du bloc : toujours celle-là quand elle est branchée, quelle que soit sa liaison.
    static let chosenKey = "soundCard.chosenUID"

    /// Cartes son : branchées en USB, Thunderbolt, FireWire, PCI ou AVB (pas les haut-parleurs du Mac, l'HDMI, le
    /// Bluetooth, AirPlay ni les périphériques virtuels ou agrégés).
    static let externalTransports: Set<UInt32> = [
        kAudioDeviceTransportTypeUSB, kAudioDeviceTransportTypeThunderbolt, kAudioDeviceTransportTypeFireWire,
        kAudioDeviceTransportTypePCI, kAudioDeviceTransportTypeAVB,
    ]

    /// Appareils qu'on peut choisir dans la fiche : tous ceux qui ont une sortie, sauf les agrégés et les virtuels.
    static func selectable(_ devices: [AudioDeviceInfo]) -> [AudioDeviceInfo] {
        let hidden: Set<UInt32> = [kAudioDeviceTransportTypeAggregate, kAudioDeviceTransportTypeAutoAggregate,
                                   kAudioDeviceTransportTypeVirtual]
        return devices.filter { $0.outputs > 0 && !hidden.contains($0.transport) && !$0.uid.isEmpty }
    }

    /// La carte à utiliser : celle choisie dans la fiche si elle est branchée ; sinon une carte externe avec une
    /// sortie, de préférence avec une entrée aussi ; parmi elles, celle de la dernière fois, sinon la première.
    static func choose(_ devices: [AudioDeviceInfo], preferredUID: String?, chosenUID: String? = nil) -> AudioDeviceInfo? {
        if let chosenUID, let chosen = selectable(devices).first(where: { $0.uid == chosenUID }) { return chosen }
        let cards = devices.filter { $0.isExternal && $0.outputs > 0 }
        let withInput = cards.filter { $0.inputs > 0 }
        let pool = withInput.isEmpty ? cards : withInput
        return pool.first { $0.uid == preferredUID } ?? pool.first
    }

    enum Outcome: Equatable {
        case done(name: String, input: Bool)
        case noCard
        case failed(String)
    }

    /// Met la carte en sortie (et en entrée si elle en a une) par défaut du Mac, puis vérifie que macOS l'a prise.
    static func apply(defaults: UserDefaults = .standard) -> Outcome {
        let devices = list()
        // Journal : ce qui a été vu, sans les noms (liaison, flux d'entrée / de sortie).
        MacroLog.shared.write("AUDIO", "\(devices.count) devices: "
                              + devices.map { "\(fourCC($0.transport)) \($0.inputs)/\($0.outputs)" }.joined(separator: ", "))
        guard let card = choose(devices, preferredUID: defaults.string(forKey: preferredKey),
                                chosenUID: defaults.string(forKey: chosenKey)) else { return .noCard }
        MacroLog.shared.write("AUDIO", "card \(fourCC(card.transport)) \(card.inputs)/\(card.outputs)")
        let status = setDefault(kAudioHardwarePropertyDefaultOutputDevice, card.id)
        guard waitForDefault(kAudioHardwarePropertyDefaultOutputDevice, card.id) else {
            MacroLog.shared.write("AUDIO", "output not taken (status \(status))")
            return .failed(String(localized: "macOS a gardé l'ancienne sortie audio au lieu de « \(card.name.displaySafe(max: 40)) »")
                           + (status == noErr ? "" : String(localized: " (erreur \(status))")))
        }
        var input = false
        if card.inputs > 0 {
            let inStatus = setDefault(kAudioHardwarePropertyDefaultInputDevice, card.id)
            input = waitForDefault(kAudioHardwarePropertyDefaultInputDevice, card.id)
            if !input { MacroLog.shared.write("AUDIO", "input not taken (status \(inStatus))") }
        }
        defaults.set(card.uid, forKey: preferredKey)
        return .done(name: card.name, input: input)
    }

    /// Appareil par défaut du Mac (sortie ou entrée), relu jusqu'à ce qu'il soit `device` (1 s au plus).
    private static func waitForDefault(_ selector: AudioObjectPropertySelector, _ device: AudioObjectID) -> Bool {
        for _ in 0..<20 {
            if currentDefault(selector) == device { return true }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return false
    }

    /// Sortie (ou entrée) par défaut du Mac en ce moment.
    static func currentDefault(_ selector: AudioObjectPropertySelector = kAudioHardwarePropertyDefaultOutputDevice) -> AudioObjectID? {
        var a = address(selector)
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &id) == noErr,
              id != AudioObjectID(kAudioObjectUnknown) else { return nil }
        return id
    }

    /// « usb  », « bltn »… : le type de liaison lisible dans le journal.
    static func fourCC(_ value: UInt32) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8((value >> $0) & 0xFF) }
        guard bytes.allSatisfy({ (32...126).contains($0) }) else { return String(value) }
        return String(decoding: bytes, as: UTF8.self)
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

    @discardableResult
    private static func setDefault(_ selector: AudioObjectPropertySelector, _ device: AudioObjectID) -> OSStatus {
        var a = address(selector)
        var id = device
        return AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil,
                                          UInt32(MemoryLayout<AudioObjectID>.size), &id)
    }
}
