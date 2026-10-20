// Organiser : capte le son du SEUL processus de FL (Core Audio, macOS 14.2+) pendant l'écoute, rien d'autre : ni
// micro, ni autres applis, ni écran. FL est rendu muet pendant la capture (on n'entend pas défiler les sons).
// Créée au début de l'écoute, tout est détruit à la fin (tap, appareil agrégé privé, IOProc). La première fois, macOS
// demande l'autorisation « Audio système » (NSAudioCaptureUsageDescription).
import CoreAudio
import Foundation

enum CaptureError: Error, Equatable {
    case processNotFound
    case failed(String, OSStatus)
    case unsupportedFormat

    var message: String {
        switch self {
        case .processNotFound: return String(localized: "FL Studio n'envoie pas de son pour l'instant : ouvre ton projet dans FL, puis relance Organiser.")
        case .failed(let step, let status): return String(localized: "Écoute de FL impossible (\(step), erreur \(status)) : vérifie l'autorisation « Audio système » de FL Shortcuts dans Réglages Système › Confidentialité et sécurité.")
        case .unsupportedFormat: return String(localized: "Format du son de FL inattendu : écoute impossible.")
        }
    }
}

/// Autorisation « Audio du système » (Réglages Système › Confidentialité et sécurité › Enregistrement de l'écran et de
/// l'audio du système). Sans elle, macOS ne refuse pas la capture : il donne du silence (chaque son finissait « À
/// vérifier »). macOS n'a pas de fonction publique pour la lire : celle de TCC, chargée à la demande ; introuvable,
/// l'état reste inconnu et l'écoute part comme avant.
enum AudioCapturePermission: Equatable {
    case granted, denied, unknown

    private static let service = "kTCCServiceAudioCapture" as CFString
    private static let tcc = dlopen("/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_NOW)

    static var status: AudioCapturePermission {
        typealias Preflight = @convention(c) (CFString, CFDictionary?) -> Int32     // 0 oui, 1 non, 2 pas demandé
        guard let tcc, let symbol = dlsym(tcc, "TCCAccessPreflight") else { return .unknown }
        switch unsafeBitCast(symbol, to: Preflight.self)(service, nil) {
        case 0: return .granted
        case 1: return .denied
        default: return .unknown
        }
    }

    /// Fenêtre de macOS (une seule fois) ; `done(autorisé)` sur le fil principal. Faux : rien n'a pu être demandé.
    @discardableResult
    static func request(_ done: @escaping (Bool) -> Void) -> Bool {
        typealias Request = @convention(c) (CFString, CFDictionary?, @convention(block) (Bool) -> Void) -> Void
        guard let tcc, let symbol = dlsym(tcc, "TCCAccessRequest") else { return false }
        unsafeBitCast(symbol, to: Request.self)(service, nil) { granted in
            DispatchQueue.main.async { done(granted) }
        }
        return true
    }
}

@available(macOS 14.2, *)
final class FLAudioTap: AudioSource {
    private let pid: pid_t
    private let queue = DispatchQueue(label: "app.flshortcut.organizer.tap", qos: .userInitiated)
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var buffer: CaptureBuffer?
    private(set) var rate: Double = 48_000
    private var info = CaptureStats()
    /// Tampons vus par la lecture (écrits sur sa file, lus pour le diagnostic).
    private let seen = NSLock()
    private var seenBuffers = 0
    private var seenUsed = 0

    init(pid: pid_t) {
        self.pid = pid
    }

    deinit { stop() }

    var stats: CaptureStats {
        var out = info
        if let buffer {
            let received = buffer.received
            out.chunks = received.chunks
            out.peakDB = 20 * log10(max(Double(received.peak), 1e-9))
        }
        seen.lock()
        out.buffers = seenBuffers
        out.used = seenUsed
        seen.unlock()
        return out
    }

    /// D'abord un agrégat qui ne contient que le son de FL (aucune entrée de carte son ne peut s'y mêler) ; s'il ne
    /// reçoit rien en 0,6 s, l'agrégat avec l'appareil de sortie de macOS (son FL lu après les entrées de la carte).
    func start() throws {
        try start(withOutput: false)
        if waitForSound(0.6) { return }
        MacroLog.shared.write("ORGANIZE", "tap-only aggregate silent: output device used")
        try start(withOutput: true)
    }

    /// Des blocs arrivent (même muets : la lecture tourne).
    private func waitForSound(_ seconds: TimeInterval) -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if (buffer?.received.chunks ?? 0) > 0 { return true }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return (buffer?.received.chunks ?? 0) > 0
    }

    private func start(withOutput: Bool) throws {
        stop()
        let process = try Self.processObject(pid: pid)
        let description = CATapDescription(stereoMixdownOfProcesses: [process])
        description.uuid = UUID()
        description.name = "FL Shortcuts – Organiser"
        description.isPrivate = true
        description.muteBehavior = .mutedWhenTapped
        var tap = AudioObjectID(kAudioObjectUnknown)
        var status = AudioHardwareCreateProcessTap(description, &tap)
        guard status == noErr else { throw CaptureError.failed("tap", status) }
        tapID = tap

        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var address = Self.address(kAudioTapPropertyFormat)
        status = AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &format)
        guard status == noErr else { stop(); throw CaptureError.failed("format", status) }
        guard format.mFormatID == kAudioFormatLinearPCM, format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              format.mBitsPerChannel == 32, format.mSampleRate >= 8_000 else {
            stop()
            throw CaptureError.unsupportedFormat
        }
        rate = format.mSampleRate

        let output = withOutput ? Self.defaultOutput() : nil
        var aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "FL Shortcuts – écoute de FL",
            kAudioAggregateDeviceUIDKey: "app.flshortcut.organizer." + UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true,
                                               kAudioSubTapUIDKey: description.uuid.uuidString]],
        ]
        if let output {
            aggregate[kAudioAggregateDeviceMainSubDeviceKey] = output.uid
            aggregate[kAudioAggregateDeviceSubDeviceListKey] = [[kAudioSubDeviceUIDKey: output.uid]]
        }
        var device = AudioObjectID(kAudioObjectUnknown)
        status = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &device)
        guard status == noErr else { stop(); throw CaptureError.failed("agrégat", status) }
        aggregateID = device
        // Le son arrive à la fréquence de l'agrégat (celle de son appareil principal), pas forcément celle du tap.
        if let nominal = Self.nominalRate(device), nominal >= 8_000 { rate = nominal }
        let capture = CaptureBuffer(rate: rate, seconds: 4)
        buffer = capture

        let interleaved = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
        let tapBuffers = interleaved ? 1 : Int(max(format.mChannelsPerFrame, 1))
        // Une carte son a des entrées (SSL 2+…) : dans l'agrégat, elles passent avant le son de FL. Le son de FL :
        // les tampons après elles (audit : sinon on écoutait l'entrée de la carte son, pas FL).
        let skip = output.map { Self.inputStreamCount($0.id) } ?? 0
        info = CaptureStats(mode: withOutput ? "carte" : "tap seul", outputInputs: skip, rate: rate,
                            tapChannels: Int(format.mChannelsPerFrame), interleaved: interleaved)
        let seen = self.seen
        status = AudioDeviceCreateIOProcIDWithBlock(&procID, device, queue) { [weak self] _, input, _, _, _ in
            let list = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            let from = list.count >= skip + tapBuffers ? skip : max(list.count - tapBuffers, 0)
            if let self {
                seen.lock()
                self.seenBuffers = list.count
                self.seenUsed = from
                seen.unlock()
            }
            guard from < list.count else { return }
            if interleaved {
                let first = list[from]
                guard let data = first.mData else { return }
                let channels = Int(max(first.mNumberChannels, 1))
                let frames = Int(first.mDataByteSize) / (MemoryLayout<Float>.size * channels)
                capture.appendInterleaved(data.assumingMemoryBound(to: Float.self), frames: frames, channels: channels)
            } else {
                let planes: [UnsafePointer<Float>] = (from..<min(from + tapBuffers, list.count)).compactMap { i in
                    list[i].mData.map { UnsafePointer($0.assumingMemoryBound(to: Float.self)) }
                }
                let frames = Int(list[from].mDataByteSize) / MemoryLayout<Float>.size
                capture.appendPlanar(planes, frames: frames)
            }
        }
        guard status == noErr, let proc = procID else { stop(); throw CaptureError.failed("lecture", status) }
        status = AudioDeviceStart(device, proc)
        guard status == noErr else { stop(); throw CaptureError.failed("démarrage", status) }
    }

    func reset() { buffer?.reset() }
    func take() -> [Float] { buffer?.take() ?? [] }

    /// Tout est détruit : lecture, appareil agrégé, tap (sans effet si rien n'a démarré).
    func stop() {
        if aggregateID != kAudioObjectUnknown, let proc = procID {
            AudioDeviceStop(aggregateID, proc)
            AudioDeviceDestroyIOProcID(aggregateID, proc)
        }
        procID = nil
        if aggregateID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggregateID) }
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        tapID = AudioObjectID(kAudioObjectUnknown)
        buffer = nil
    }

    // MARK: Core Audio

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    /// Objet audio du processus de FL (n'existe que s'il a déjà ouvert sa sortie audio).
    private static func processObject(pid: pid_t) throws -> AudioObjectID {
        var address = Self.address(kAudioHardwarePropertyTranslatePIDToProcessObject)
        var pid = pid
        var object = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                                UInt32(MemoryLayout<pid_t>.size), &pid, &size, &object)
        guard status == noErr else { throw CaptureError.failed("processus", status) }
        guard object != kAudioObjectUnknown else { throw CaptureError.processNotFound }
        return object
    }

    private static func defaultOutput() -> (id: AudioObjectID, uid: String)? {
        var address = Self.address(kAudioHardwarePropertyDefaultSystemOutputDevice)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { return nil }
        var uidAddress = Self.address(kAudioDevicePropertyDeviceUID)
        var uid: Unmanaged<CFString>?
        var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &uid) {
            AudioObjectGetPropertyData(device, &uidAddress, 0, nil, &uidSize, $0)
        }
        guard status == noErr, let uid else { return nil }
        let text = uid.takeRetainedValue() as String
        return text.isEmpty ? nil : (id: device, uid: text)
    }

    /// Flux d'entrée d'un appareil (un tampon chacun dans l'agrégat) : 0 pour des haut-parleurs.
    private static func inputStreamCount(_ device: AudioObjectID) -> Int {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                                 mScope: kAudioObjectPropertyScopeInput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr else { return 0 }
        return Int(size) / MemoryLayout<AudioStreamID>.size
    }

    private static func nominalRate(_ device: AudioObjectID) -> Double? {
        var address = Self.address(kAudioDevicePropertyNominalSampleRate)
        var value = Float64(0)
        var size = UInt32(MemoryLayout<Float64>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }
}
