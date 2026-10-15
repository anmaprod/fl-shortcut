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
        case .processNotFound: return "FL Studio n'envoie pas de son pour l'instant : ouvre ton projet dans FL, puis relance Organiser."
        case .failed(let step, let status): return "Écoute de FL impossible (\(step), erreur \(status)) : vérifie l'autorisation « Audio système » de FL Shortcut dans Réglages Système › Confidentialité et sécurité."
        case .unsupportedFormat: return "Format du son de FL inattendu : écoute impossible."
        }
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

    init(pid: pid_t) {
        self.pid = pid
    }

    deinit { stop() }

    func start() throws {
        stop()
        let process = try Self.processObject(pid: pid)
        let description = CATapDescription(stereoMixdownOfProcesses: [process])
        description.uuid = UUID()
        description.name = "FL Shortcut – Organiser"
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
        let capture = CaptureBuffer(rate: rate, seconds: 4)
        buffer = capture

        let output = Self.defaultOutputUID() ?? ""
        var aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "FL Shortcut – écoute de FL",
            kAudioAggregateDeviceUIDKey: "app.flshortcut.organizer." + UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true,
                                               kAudioSubTapUIDKey: description.uuid.uuidString]],
        ]
        if !output.isEmpty {
            aggregate[kAudioAggregateDeviceMainSubDeviceKey] = output
            aggregate[kAudioAggregateDeviceSubDeviceListKey] = [[kAudioSubDeviceUIDKey: output]]
        }
        var device = AudioObjectID(kAudioObjectUnknown)
        status = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &device)
        guard status == noErr else { stop(); throw CaptureError.failed("agrégat", status) }
        aggregateID = device

        let interleaved = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
        status = AudioDeviceCreateIOProcIDWithBlock(&procID, device, queue) { _, input, _, _, _ in
            let list = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            if interleaved, let first = list.first, let data = first.mData {
                let channels = Int(max(first.mNumberChannels, 1))
                let frames = Int(first.mDataByteSize) / (MemoryLayout<Float>.size * channels)
                capture.appendInterleaved(data.assumingMemoryBound(to: Float.self), frames: frames, channels: channels)
            } else {
                let planes: [UnsafePointer<Float>] = list.compactMap { buffer in
                    buffer.mData.map { UnsafePointer($0.assumingMemoryBound(to: Float.self)) }
                }
                let frames = list.first.map { Int($0.mDataByteSize) / MemoryLayout<Float>.size } ?? 0
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

    private static func defaultOutputUID() -> String? {
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
        return uid.takeRetainedValue() as String
    }
}
