// Risque de larsen avant d'enregistrer au micro : le micro ET le son de l'ordinateur lui-même
// (haut-parleurs intégrés) sont en service. Avec une carte son, un casque (prise jack, Bluetooth, USB) ou un
// micro externe, pas de risque signalé.
// Appareils réellement utilisés par FL (Core Audio, macOS 14.2+), sinon appareils par défaut du système.
// Lecture seule : rien n'est modifié dans la configuration audio.
import AppKit
import CoreAudio
import Foundation

enum FeedbackRisk {
    struct Device: Equatable {
        let name: String
        let builtIn: Bool
        let headphones: Bool
    }

    struct Report: Equatable {
        let input: Device?
        let output: Device?

        /// Micro intégré + haut-parleurs intégrés.
        var risky: Bool {
            guard let input, let output else { return false }
            return input.builtIn && output.builtIn && !output.headphones
        }

        var message: String {
            let i = input?.name ?? String(localized: "micro")
            let o = output?.name ?? String(localized: "haut-parleurs")
            return String(localized: """
                FL enregistre avec « \(i) » et joue le son sur « \(o) » : le micro reprendrait le son des \
                haut-parleurs (larsen). Branche un casque, ou choisis ta carte son dans FL (Options › Audio Settings) avant de lancer la lecture.
                """)
        }
    }

    /// Appareils de FL (ou du système) au moment de l'appel.
    static func check(flPID: pid_t) -> Report {
        var devices: [AudioObjectID] = []
        if #available(macOS 14.2, *) { devices = processDevices(pid: flPID) }
        var input = devices.first { hasStreams($0, scope: kAudioObjectPropertyScopeInput) }.flatMap(describe)
        var output = devices.first { hasStreams($0, scope: kAudioObjectPropertyScopeOutput) }.flatMap(describe)
        if input == nil { input = defaultDevice(kAudioHardwarePropertyDefaultInputDevice).flatMap(describe) }
        if output == nil { output = defaultDevice(kAudioHardwarePropertyDefaultOutputDevice).flatMap(describe) }
        return Report(input: input, output: output)
    }

    // MARK: Core Audio

    @available(macOS 14.2, *)
    private static func processDevices(pid: pid_t) -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var pidValue = pid
        var process = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                                UInt32(MemoryLayout<pid_t>.size), &pidValue, &size, &process)
        guard status == noErr, process != kAudioObjectUnknown else { return [] }
        return objectList(process, selector: kAudioProcessPropertyDevices, scope: kAudioObjectPropertyScopeGlobal)
    }

    private static func defaultDevice(_ selector: AudioObjectPropertySelector) -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id) == noErr,
              id != kAudioObjectUnknown else { return nil }
        return id
    }

    private static func objectList(_ object: AudioObjectID, selector: AudioObjectPropertySelector,
                                   scope: AudioObjectPropertyScope) -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var list = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &list) == noErr else { return [] }
        return list
    }

    private static func hasStreams(_ device: AudioObjectID, scope: AudioObjectPropertyScope) -> Bool {
        !objectList(device, selector: kAudioDevicePropertyStreams, scope: scope).isEmpty
    }

    private static func uint32(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                               scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> UInt32? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private static func name(_ device: AudioObjectID) -> String {
        var address = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr,
              let cf = value?.takeRetainedValue() else { return String(localized: "appareil audio") }
        return cf as String
    }

    private static func describe(_ device: AudioObjectID) -> Device? {
        guard device != kAudioObjectUnknown else { return nil }
        let transport = uint32(device, kAudioDevicePropertyTransportType)
        // Source de sortie « hdpn » : casque branché sur la prise de l'ordinateur.
        let source = uint32(device, kAudioDevicePropertyDataSource, scope: kAudioObjectPropertyScopeOutput)
        let label = name(device)
        let lower = label.lowercased()
        let headphoneName = ["headphone", "casque", "écouteurs", "airpods"].contains { lower.contains($0) }
        return Device(name: label,
                      builtIn: transport == kAudioDeviceTransportTypeBuiltIn,
                      headphones: source == 0x6864_706E || headphoneName)   // 'hdpn'
    }
}

/// Fenêtre d'explication (thread principal) : la macro ne lance pas l'enregistrement tant que le risque existe.
enum FeedbackAlert {
    static func show(_ report: FeedbackRisk.Report) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Tout est prêt, mais attention au larsen")
        alert.informativeText = report.message
            + String(localized: "\n\nLa piste et le REC sont prêts : il ne reste qu'à changer d'entrée ou de sortie.")
        alert.addButton(withTitle: String(localized: "OK"))
        alert.addButton(withTitle: String(localized: "Réglages Son…"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
