// Recherche de la fenêtre principale active seulement quand on l'a choisie, comme une barre de recherche ordinaire.
// AppKit donne la main au premier champ de la fenêtre (la recherche de la barre latérale) dès qu'elle s'ouvre, qu'elle
// reprend la main (après le menu de l'icône, une autre app) ou qu'une page change : toute frappe s'y écrivait sans
// qu'on ait cliqué dedans. Elle ne garde la main qu'après un clic dedans (ou ⌘F), et jusqu'au premier clic ailleurs
// (une page, une option de la barre latérale, un bouton) : sinon la fenêtre la lui reprend, tout de suite et encore
// une fois la page changée (retour de l'utilisateur : cliquée puis une option choisie dans la seconde, elle gardait
// la main pour de bon). Un clic hors de la fenêtre (une autre app, le bureau, une autre fenêtre de l'app) la lui
// reprend aussi, pour de bon : la fenêtre revenue, elle n'est plus active (retour de l'utilisateur, vidéo : cliquée,
// puis un clic hors de l'app, elle était encore active au retour). Son texte reste. Rien ne tourne au repos : des
// observateurs de la fenêtre et un moniteur local (clics et touches de cette fenêtre seulement), retirés avec la vue.
import AppKit
import SwiftUI

struct SearchFocusGuard: NSViewRepresentable {
    func makeNSView(context: Context) -> GuardView { GuardView() }
    func updateNSView(_ nsView: GuardView, context: Context) {}

    static func dismantleNSView(_ nsView: GuardView, coordinator: ()) { nsView.detach() }

    final class GuardView: NSView {
        private var observation: NSKeyValueObservation?
        private var monitor: Any?
        private var keyObserver: NSObjectProtocol?
        private var resignObserver: NSObjectProtocol?
        /// La recherche a été choisie (clic dedans, ⌘F) : elle garde la main jusqu'au premier clic ailleurs.
        private(set) var chosen = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            detach()
            guard let window else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
                guard let self, let window = self.window, event.window === window else { return event }
                if event.type == .keyDown {
                    if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                       event.charactersIgnoringModifiers?.lowercased() == "f" {
                        self.chosen = true
                    }
                } else {
                    self.clicked(inSearch: Self.searchField(at: event.locationInWindow, in: window), window: window)
                }
                return event
            }
            observation = window.observe(\.firstResponder, options: [.new]) { [weak self] window, _ in
                DispatchQueue.main.async { self?.check(window) }
            }
            // La fenêtre reprend la main : AppKit redonne la main à la recherche, parfois un peu après.
            keyObserver = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification,
                                                                 object: window, queue: .main) { [weak self] _ in
                self?.checkSoon(window)
            }
            // La fenêtre perd la main (clic hors d'elle) : la recherche la lâche aussi.
            resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
                                                                    object: window, queue: .main) { [weak self] _ in
                self?.left(window)
            }
            // Fenêtre qui s'ouvre : la recherche a pu prendre la main avant que l'observateur soit là.
            checkSoon(window)
        }

        func detach() {
            observation = nil
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            if let keyObserver { NotificationCenter.default.removeObserver(keyObserver) }
            keyObserver = nil
            if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
            resignObserver = nil
        }

        /// Clic hors de la fenêtre : comme un clic ailleurs, la recherche n'est plus choisie et lâche la main.
        func left(_ window: NSWindow) {
            chosen = false
            check(window)
        }

        /// Clic dans la fenêtre : dans la recherche, elle est choisie ; ailleurs, elle lâche la main (un autre champ
        /// cliqué la prend lui-même).
        func clicked(inSearch: Bool, window: NSWindow) {
            chosen = inSearch
            guard !inSearch else { return }
            DispatchQueue.main.async { [weak self, weak window] in
                guard let window else { return }
                self?.check(window)
            }
            checkSoon(window)
        }

        /// Vérifié encore un peu plus tard : la page changée, AppKit redonnait la main à la recherche.
        private func checkSoon(_ window: NSWindow) {
            for delay in [0.1, 0.35] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak window] in
                    guard let window else { return }
                    self?.check(window)
                }
            }
        }

        /// La recherche a la main sans avoir été choisie : la fenêtre la reprend (plus rien n'est tapé dedans).
        func check(_ window: NSWindow) {
            guard !chosen, Self.isSearchEditor(window.firstResponder) else { return }
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
