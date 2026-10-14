// Créateur de macros : fenêtre AppKit créée à la demande et VRAIMENT libérée à sa fermeture. Une scène `Window`
// SwiftUI refermée n'était que masquée : vue, modèle et brouillon restaient en mémoire (mesure de la CI).
// - Le contrôleur possède la fenêtre et le modèle ; à la fermeture : brouillon enregistré, « Montrer dans FL… » et
//   essai en préparation arrêtés, besoins rendus (MacroEditorModel.close), puis vue et fenêtre lâchées.
// - Rien au repos : ni minuterie ni observateur, seulement le délégué de la fenêtre ouverte.
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
        w.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func close() { window?.close() }

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow, closing === window else { return }
        model?.close()
        closing.delegate = nil
        model = nil
        window = nil
        // Vue SwiftUI (et avec elle le modèle) détruite au tour suivant : la fermeture peut venir d'une action de
        // la vue elle-même. La fenêtre est lâchée avec.
        DispatchQueue.main.async { closing.contentViewController = nil }
    }
}
