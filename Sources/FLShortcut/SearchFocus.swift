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
// La main est reprise des deux côtés (25/10, « toujours là ») : par AppKit (la fenêtre la reprend) et par SwiftUI
// (`release`, qui met `searchFocused` à faux sur macOS 15 et plus : SwiftUI pouvait la lui redonner aussitôt). La
// recherche est reconnue même quand le champ qui a la main n'en est qu'une partie (dessinée par SwiftUI). Vérifié à
// vrais clics sur la CI (macOS 26, `AppKitSearchField` de SwiftUI, une NSSearchField, éditée par `SearchTextView`) :
// elle lâche la main à chaque clic ailleurs, dans l'app comme dehors.
import AppKit
import SwiftUI

struct SearchFocusGuard: NSViewRepresentable {
    /// SwiftUI : la recherche n'a plus la main (son `searchFocused` à faux).
    var release: () -> Void = {}

    func makeNSView(context: Context) -> GuardView {
        let view = GuardView()
        view.release = release
        return view
    }

    func updateNSView(_ nsView: GuardView, context: Context) { nsView.release = release }

    static func dismantleNSView(_ nsView: GuardView, coordinator: ()) { nsView.detach() }

    final class GuardView: NSView {
        private var observation: NSKeyValueObservation?
        private var monitor: Any?
        private var keyObserver: NSObjectProtocol?
        private var resignObserver: NSObjectProtocol?
        /// La recherche a été choisie (clic dedans, ⌘F) : elle garde la main jusqu'au premier clic ailleurs.
        private(set) var chosen = false
        /// La dernière posée dans une fenêtre (rapport du mode capture : l'essai de la barre de recherche de la CI).
        static weak var latest: GuardView?
        var release: () -> Void = {}

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            detach()
            guard let window else { return }
            Self.latest = self
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
            release()
            check(window)
        }

        /// Clic dans la fenêtre : dans la recherche, elle est choisie ; ailleurs, elle lâche la main (un autre champ
        /// cliqué la prend lui-même).
        func clicked(inSearch: Bool, window: NSWindow) {
            chosen = inSearch
            guard !inSearch else { return }
            release()
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
            release()
            window.makeFirstResponder(nil)
        }

        /// Le champ qui a la main est celui d'une recherche (éditeur de texte partagé de la fenêtre) : le champ édité,
        /// ou l'un de ses parents, est une recherche.
        static func isSearchEditor(_ responder: NSResponder?) -> Bool {
            if let view = responder as? NSView, isSearchView(view) { return true }
            guard let editor = responder as? NSTextView, editor.isFieldEditor else { return false }
            var view = editor.delegate as? NSView
            while let current = view {
                if isSearchView(current) { return true }
                view = current.superview
            }
            return false
        }

        /// Une recherche d'AppKit, un champ dessiné comme elle, ou celle de SwiftUI à son nom de classe (macOS 26 :
        /// `AppKitSearchField`, une NSSearchField ; le nom, au cas où une autre version de macOS en ferait une vue
        /// ordinaire), sans ses paramètres (un hôte `NSHostingView<…SearchField…>` n'en est pas une).
        static func isSearchView(_ view: NSView) -> Bool {
            if view is NSSearchField || (view as? NSTextField)?.cell is NSSearchFieldCell { return true }
            let name = String(describing: type(of: view))
            return name.prefix { $0 != "<" }.contains("SearchField")
        }

        /// Recherches posées par l'app (SidebarSearchField) : hébergées par SwiftUI, AppKit ne les trouvait pas sous la
        /// souris, et la garde lui reprenait aussitôt la main (vrai clic de la CI du 29/10). Un clic dans leur capsule
        /// (un peu plus grande que le champ) compte comme un clic dedans.
        static let fields = NSHashTable<NSView>.weakObjects()

        /// Un clic tombe dans une recherche (ou dans son texte en cours d'édition).
        static func searchField(at point: NSPoint, in window: NSWindow) -> Bool {
            for field in fields.allObjects where field.window === window && !field.isHiddenOrHasHiddenAncestor {
                if field.convert(field.bounds, to: nil).insetBy(dx: -8, dy: -10).contains(point) { return true }
            }
            guard let frame = window.contentView?.superview, var view = frame.hitTest(point) else { return false }
            while true {
                if isSearchEditor(view) { return true }
                guard let parent = view.superview else { return false }
                view = parent
            }
        }
    }
}

/// La main de la recherche suivie par SwiftUI (macOS 15 et plus) ; avant, la garde n'agit que côté AppKit.
struct SearchFocusBinding: ViewModifier {
    var focused: FocusState<Bool>.Binding

    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.searchFocused(focused)
        } else {
            content
        }
    }
}
