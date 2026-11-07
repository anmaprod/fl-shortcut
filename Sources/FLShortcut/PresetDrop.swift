// Dépôt d'un preset sur une piste du Mixer, comme un glisser-déposer depuis le Finder. Essai de l'utilisateur sur
// son FL : déposé n'importe où sur la tranche, le .fst charge l'état de CETTE piste (un double-clic dans le Finder,
// lui, le charge sur le Master). Plus de menu ni de boîte « Open » pour un preset fixe.
// - Une petite fenêtre de l'app, transparente, posée sous le point de la piste, reçoit un appui synthétique et
//   ouvre une vraie session de glisser avec le fichier ; elle disparaît aussitôt. Quelques déplacements puis le
//   relâchement, par le flux du système comme une vraie souris, déposent le fichier sur la piste. Rien n'est lu à
//   l'écran.
// - FL dit lui-même s'il a pris le fichier (opération rendue à la fin de la session) : refus → échec expliqué.
// - La fenêtre et la session n'existent que pendant le dépôt : rien ne reste au repos.
import AppKit
import CoreGraphics

enum PresetDrop {
    enum Outcome: Equatable {
        case done
        case failed(String)
    }

    /// Fil de la macro, jamais le fil principal (la session de glisser y tourne). `p` : point de la piste (repère
    /// CoreGraphics, origine en haut à gauche de l'écran principal).
    static func drop(path: String, at p: CGPoint, source: CGEventSource?,
                     log: (String) -> Void = { MacroLog.shared.write("DROP", $0) }) -> Outcome {
        let started = DispatchSemaphore(value: 0)
        let ended = DispatchSemaphore(value: 0)
        let operation = Locked<NSDragOperation?>(nil)
        let dragSource: DropSource = DispatchQueue.main.sync {
            let s = DropSource(url: URL(fileURLWithPath: path), at: p, started: started, ended: ended, operation: operation)
            s.show()
            return s
        }
        defer { DispatchQueue.main.async { dragSource.close() } }

        func post(_ type: CGEventType, _ q: CGPoint) {
            guard let e = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: q, mouseButton: .left) else { return }
            e.flags = []
            e.setIntegerValueField(.mouseEventClickState, value: 1)
            e.setIntegerValueField(.eventSourceUserData, value: EventTap.mark)
            e.post(tap: .cghidEventTap)
        }
        let t0 = DispatchTime.now().uptimeNanoseconds
        func ms() -> Int { Int((DispatchTime.now().uptimeNanoseconds &- t0) / 1_000_000) }

        post(.mouseMoved, p)
        usleep(20_000)
        post(.leftMouseDown, p)
        guard started.wait(timeout: .now() + 0.8) == .success else {
            post(.leftMouseUp, p)
            log("drag not started · \(ms()) ms")
            return .failed(String(localized: "le glisser du preset n'a pas démarré (une fenêtre couvre la piste ?)"))
        }
        // Quelques pixels à droite puis retour : FL voit le fichier entrer sur la piste, puis le reçoit au point visé.
        for dx in [4.0, 8, 12, 8, 4, 0] {
            post(.leftMouseDragged, CGPoint(x: p.x + dx, y: p.y))
            usleep(16_000)
        }
        usleep(30_000)
        post(.leftMouseUp, p)
        guard ended.wait(timeout: .now() + 2) == .success else {
            log("drag not ended · \(ms()) ms")
            return .failed(String(localized: "FL n'a pas répondu au dépôt du preset"))
        }
        let op = operation.value ?? []
        log("drag ended · operation 0x\(String(op.rawValue, radix: 16)) · \(ms()) ms")
        return op.isEmpty ? .failed(String(localized: "FL n'a pas pris le preset : clique d'abord au milieu de la tranche de ta piste"))
                           : .done
    }
}

/// Source du glisser : petite fenêtre transparente sous le point de la piste, qui n'active jamais l'app.
private final class DropSource: NSView, NSDraggingSource {
    private let url: URL
    private let panel: NSPanel
    private let started: DispatchSemaphore
    private let ended: DispatchSemaphore
    private let operation: Locked<NSDragOperation?>

    init(url: URL, at p: CGPoint, started: DispatchSemaphore, ended: DispatchSemaphore, operation: Locked<NSDragOperation?>) {
        self.url = url
        self.started = started
        self.ended = ended
        self.operation = operation
        let side: CGFloat = 24
        // Repère CoreGraphics (origine en haut à gauche de l'écran principal) → repère AppKit (en bas à gauche).
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        let frame = NSRect(x: p.x - side / 2, y: mainHeight - p.y - side / 2, width: side, height: side)
        panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init(frame: NSRect(origin: .zero, size: frame.size))
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.ignoresMouseEvents = false               // reçoit l'appui même entièrement transparente
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        panel.contentView = self
    }

    required init?(coder: NSCoder) { return nil }

    func show() { panel.orderFrontRegardless() }

    func close() {
        panel.orderOut(nil)
        panel.contentView = nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        let item = NSPasteboardItem()
        item.setString(url.absoluteString, forType: .fileURL)
        // Ancien type de liste de fichiers, que le Finder fournit aussi (certaines apps ne lisent que lui).
        item.setPropertyList([url.path], forType: NSPasteboard.PasteboardType("NSFilenamesPboardType"))
        let dragging = NSDraggingItem(pasteboardWriter: item)
        dragging.setDraggingFrame(bounds, contents: NSWorkspace.shared.icon(forFile: url.path))
        let session = beginDraggingSession(with: [dragging], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = false
        // La piste n'est plus couverte (le dépôt va à FL) ; la fenêtre reste ouverte, hors de l'écran, tant que
        // dure la session : la cacher pourrait l'interrompre.
        panel.ignoresMouseEvents = true
        panel.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        started.signal()
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? [.copy, .link, .generic, .move] : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        self.operation.withLock { $0 = operation }
        ended.signal()
    }
}
