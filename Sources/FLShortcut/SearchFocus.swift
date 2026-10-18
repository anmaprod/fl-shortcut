// Recherche de la fenêtre principale active seulement quand on l'a choisie, comme une barre de recherche ordinaire.
// AppKit donne la main au premier champ de la fenêtre (la recherche de la barre latérale) dès qu'elle s'ouvre, ou
// quand une page change : toute frappe s'y écrivait sans qu'on ait cliqué dedans. Elle ne garde la main qu'après un
// clic dedans (ou ⌘F) ; sinon la fenêtre la lui reprend aussitôt. Rien ne tourne au repos : un observateur de la
// fenêtre et un moniteur local (clics et touches de cette fenêtre seulement), retirés avec la vue.
import AppKit
import SwiftUI

struct SearchFocusGuard: NSViewRepresentable {
    func makeNSView(context: Context) -> GuardView { GuardView() }
    func updateNSView(_ nsView: GuardView, context: Context) {}

    static func dismantleNSView(_ nsView: GuardView, coordinator: ()) { nsView.detach() }

    final class GuardView: NSView {
        private var observation: NSKeyValueObservation?
        private var monitor: Any?
        /// Dernière fois que l'utilisateur a choisi la recherche (clic dedans, ⌘F).
        private var chosenAt = Date.distantPast

        /// Délai pendant lequel la recherche qui prend la main est celle qu'on vient de choisir.
        static let choiceWindow: TimeInterval = 1

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            detach()
            guard let window else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .keyDown]) { [weak self] event in
                guard let self, let window = self.window, event.window === window else { return event }
                switch event.type {
                case .keyDown:
                    if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                       event.charactersIgnoringModifiers?.lowercased() == "f" {
                        self.chosenAt = Date()
                    }
                default:
                    if Self.searchField(at: event.locationInWindow, in: window) { self.chosenAt = Date() }
                }
                return event
            }
            observation = window.observe(\.firstResponder, options: [.new]) { [weak self] window, _ in
                DispatchQueue.main.async { self?.check(window) }
            }
            // Fenêtre qui s'ouvre : la recherche a pu prendre la main avant que l'observateur soit là.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.check(window) }
        }

        func detach() {
            observation = nil
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        /// La recherche a la main sans avoir été choisie : la fenêtre la reprend (plus rien n'est tapé dedans).
        private func check(_ window: NSWindow) {
            guard Self.isSearchEditor(window.firstResponder),
                  Date().timeIntervalSince(chosenAt) > Self.choiceWindow else { return }
            window.makeFirstResponder(nil)
        }

        /// Le champ qui a la main est celui d'une recherche (éditeur de texte partagé de la fenêtre).
        static func isSearchEditor(_ responder: NSResponder?) -> Bool {
            if responder is NSSearchField { return true }
            guard let editor = responder as? NSTextView, editor.isFieldEditor else { return false }
            return editor.delegate is NSSearchField
        }

        /// Un clic tombe dans une recherche (ou dans son texte en cours d'édition).
        static func searchField(at point: NSPoint, in window: NSWindow) -> Bool {
            guard let frame = window.contentView?.superview, var view = frame.hitTest(point) else { return false }
            while true {
                if view is NSSearchField || isSearchEditor(view) { return true }
                guard let parent = view.superview else { return false }
                view = parent
            }
        }
    }
}
