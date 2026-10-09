import CoreMIDI

/// Port MIDI virtuel "FL Shortcut" que FL Studio voit comme un contrôleur.
final class MIDIOut {
    static let shared = MIDIOut()
    private var client = MIDIClientRef()
    private var source = MIDIEndpointRef()
    private(set) var ready = false

    private init() {
        guard MIDIClientCreate("FL Shortcut" as CFString, nil, nil, &client) == noErr else { return }
        ready = MIDISourceCreate(client, "FL Shortcut" as CFString, &source) == noErr
        // ID fixe : FL Studio retrouve la même configuration à chaque lancement
        if ready { MIDIObjectSetIntegerProperty(source, kMIDIPropertyUniqueID, 0x464C5250) }
    }

    /// Envoie un Control Change sur le canal 16 (0-indexé : 15).
    func send(cc: UInt8, channel: UInt8 = 15) {
        guard ready else { return }
        let bytes: [UInt8] = [0xB0 | (channel & 0x0F), cc, 127]
        var list = MIDIPacketList()
        withUnsafeMutablePointer(to: &list) { ptr in
            let packet = MIDIPacketListInit(ptr)
            _ = MIDIPacketListAdd(ptr, MemoryLayout<MIDIPacketList>.size, packet, 0, bytes.count, bytes)
            MIDIReceived(source, ptr)
        }
    }
}
