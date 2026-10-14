// Créateur de macros : fenêtre AppKit créée à la demande et VRAIMENT libérée à sa fermeture. Une scène `Window`
// SwiftUI refermée n'était que masquée : vue, modèle et brouillon restaient en mémoire (mesure de la CI).
// - Le contrôleur possède la fenêtre et le modèle ; à la fermeture : brouillon enregistré, « Montrer dans FL… » et
//   essai en préparation arrêtés, besoins rendus (MacroEditorModel.close), puis vue et fenêtre lâchées.
// - Rien au repos : ni minuterie ni observateur, seulement le délégué de la fenêtre ouverte.
// - Ouvert, il reste devant FL (niveau flottant tant que FL ou l'app est au premier plan : plus besoin de le chercher
//   parmi les fenêtres) ; il passe derrière pendant « Montrer dans FL… », « Enregistrer des clics », un essai ou une
//   macro (leurs clics ne doivent jamais tomber sur lui), puis revient devant.
import AppKit
import SwiftUI

final class MacroCreatorWindowController: NSObject, NSWindowDelegate {
    static let shared = MacroCreatorWindowController()

    private let store: Store
    private var window: NSWindow?
    private var model: MacroEditorModel?

    /// `store` : celui de l'app ; un Store en mémoire dans les tests.
    init(store: Store = .shared) {
        self.store = store
        super.init()
    }

    var isOpen: Bool { window != nil }

    // MARK: Devant FL

    /// Créateur ouvert (nil sinon) : les macros et l'apprentissage le font passer derrière sans jamais le créer.
    private static weak var open: MacroCreatorWindowController?
    /// Derrière FL : « Montrer dans FL… », « Enregistrer des clics », essai ou macro en cours.
    private var aside = false
    private var activationObserver: NSObjectProtocol?

    /// FL va recevoir des clics de l'utilisateur ou de la macro : le créateur passe derrière (jamais un clic dessus).
    static func stepAside() {
        guard let c = open, let window = c.window, !window.isMiniaturized else { return }
        c.aside = true
        window.level = .normal
        if window.isVisible { window.orderBack(nil) }
    }

    /// Fini : le créateur revient devant FL, sans lui prendre le premier plan.
    static func comeBack() {
        guard let c = open, c.aside else { return }
        c.aside = false
        c.refreshLevel()
        if let window = c.window, window.level == .floating, window.isVisible, !window.isMiniaturized { window.orderFront(nil) }
    }

    /// Devant les fenêtres de FL tant que FL (ou l'app) est au premier plan : plus besoin de le chercher parmi les
    /// fenêtres ouvertes. Une autre app au premier plan : à sa place parmi les fenêtres, comme d'habitude.
    private func refreshLevel() {
        guard let window, !aside else { return }
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let besideFL = front == getpid() || front.map { EventTap.shared.currentConfig.flPIDs.contains($0) } ?? false
        let level: NSWindow.Level = besideFL ? .floating : .normal
        if window.level != level { window.level = level }
    }

    /// Ouvre la fenêtre, ou la ramène devant. La macro montrée vient de la demande de MacroCreatorLink.
    func show() {
        if let window {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }
        let model = MacroEditorModel(store: store)
        let host = NSHostingController(rootView: MacroCreatorView(model: model)
            .environmentObject(store)
            .frame(minWidth: 900, minHeight: 600))
        host.sizingOptions = [.minSize]                  // taille libre au-dessus du minimum de la vue
        if #available(macOS 14.0, *) { host.sceneBridgingOptions = [.toolbars, .title] }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.contentViewController = host
        w.title = "Créateur de macros"
        w.contentMinSize = NSSize(width: 900, height: 600)
        w.setContentSize(NSSize(width: 1100, height: 700))
        w.isReleasedWhenClosed = false
        w.isRestorable = false                           // jamais rouvert tout seul au lancement
        w.tabbingMode = .disallowed
        w.delegate = self
        w.center()
        w.setFrameAutosaveName("macro-creator")          // place et taille retrouvées d'une ouverture à l'autre
        model.window = w
        self.model = model
        window = w
        Self.open = self
        aside = false
        w.level = .floating
        // Seulement pendant que le créateur est ouvert : suit l'app au premier plan (devant FL, pas devant les autres).
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refreshLevel()
        }
        w.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func close() { autoreleasepool { window?.close() } }

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow, closing === window else { return }
        if let o = activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(o) }
        activationObserver = nil
        if Self.open === self { Self.open = nil }
        aside = false
        model?.close()
        closing.delegate = nil
        model = nil
        window = nil
        // Vue SwiftUI détruite au tour suivant (la fermeture peut venir d'une action de la vue elle-même), barre
        // d'outils aussi : ses boutons tiennent le modèle, même si AppKit garde la fenêtre un instant.
        DispatchQueue.main.async {
            autoreleasepool {
                closing.contentViewController = nil
                closing.toolbar = nil
            }
            Self.releaseNow()
        }
    }

    /// App au repos : AppKit ne vide sa réserve d'objets « autoreleased » qu'au prochain événement. Un événement
    /// vide la vide tout de suite ; puis la mémoire libérée est rendue au système (une fois, après la fermeture).
    private static func releaseNow() {
        if let wake = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0,
                                         windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) {
            NSApplication.shared.postEvent(wake, atStart: false)
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) {
            _ = malloc_zone_pressure_relief(nil, 0)
        }
    }
}
