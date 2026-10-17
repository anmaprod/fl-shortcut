// Menu de l'icône de la barre des menus (MenuBarExtra en fenêtre), réglé là où SwiftUI ne le fait pas :
// - il se ferme dès qu'on choisit une ligne, ou qu'on clique une fenêtre de l'app (il restait ouvert par-dessus) ;
// - refermé d'un clic sur l'icône, il laisse devant la fenêtre de l'app qui y était (SwiftUI rendait le premier plan
//   à FL, dont la fenêtre recouvrait tout : on aurait dit que tout se fermait) ;
// - à chaque ouverture, son contenu sort de l'icône : fondu et léger agrandissement depuis le haut, puis les lignes
//   l'une après l'autre, avec un ressort doux. « Réduire les animations » : fondu seul.
// Fermer passe par le bouton de l'icône (comme un clic dessus) : SwiftUI reste d'accord sur l'état du menu, et le
// clic suivant sur l'icône l'ouvre du premier coup.
import AppKit
import SwiftUI

final class MenuPanel: ObservableObject {
    static let shared = MenuPanel()

    /// Contenu déployé : faux pendant que le menu est fermé, vrai (animé) à chaque ouverture.
    @Published private(set) var revealed = false

    private weak var panel: NSWindow?
    private var observers: [NSObjectProtocol] = []
    /// Dernière fois que l'app est passée au premier plan.
    private var activeSince = Date.distantPast
    /// Fenêtre de l'app qui était devant à l'ouverture (l'app au premier plan) : elle y revient à la fermeture.
    private weak var frontWindow: NSWindow?
    /// Fermeture demandée (ligne choisie) : ne pas recliquer l'icône une seconde fois.
    private var closing = false

    private init() {
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.activeSince = Date()
        })
    }

    /// Fenêtre du menu, donnée par son contenu dès qu'il y est posé ; suivie une seule fois.
    func attach(_ window: NSWindow) {
        guard panel !== window else { return }
        panel = window
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window,
                                            queue: .main) { [weak self] _ in self?.opened() })
        observers.append(center.addObserver(forName: NSWindow.didResignKeyNotification, object: window,
                                            queue: .main) { [weak self] _ in self?.resigned() })
        observers.append(center.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: window,
                                            queue: .main) { [weak self] _ in self?.visibilityChanged() })
        if window.isKeyWindow || window.occlusionState.contains(.visible) { opened() }
    }

    /// Contenu affiché : si la fenêtre n'a rien signalé (cas imprévu), le contenu se montre quand même.
    func appeared() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, !self.revealed, self.panel?.isVisible ?? true else { return }
            self.reveal()
        }
    }

    /// Ligne choisie : le menu se ferme, comme un vrai menu.
    func close() {
        guard let panel, panel.isVisible, !closing else { return }
        closing = true
        statusButton?.performClick(nil)
    }

    // MARK: Ouverture, fermeture

    private func opened() {
        guard !revealed else { return }
        closing = false
        // L'app était déjà au premier plan avant le clic sur l'icône (pas activée par l'ouverture du menu).
        let alreadyFront = NSApp.isActive && Date().timeIntervalSince(activeSince) > 0.4
        frontWindow = alreadyFront ? appWindows.first : nil
        reveal()
    }

    private func reveal() {
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        withAnimation(reduce ? .easeOut(duration: 0.15) : .spring(response: 0.42, dampingFraction: 0.84)) {
            revealed = true
        }
    }

    /// Une autre fenêtre a pris la main (ligne choisie, clic sur une fenêtre de l'app ou sur une autre app) : le menu
    /// se ferme s'il est encore là.
    private func resigned() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let panel = self.panel else { return }
            // Clic sur une fenêtre de l'app : elle reste devant une fois le menu fermé. Clic dans une autre app :
            // SwiftUI ferme le menu lui-même (le refermer ici pourrait le rouvrir pendant qu'il s'efface).
            if panel.isVisible, !panel.isKeyWindow, NSApp.isActive {
                if let key = NSApp.keyWindow, key !== panel, key.isVisible { self.frontWindow = key }
                self.close()
            }
            if !panel.isVisible { self.closed() }
        }
    }

    private func visibilityChanged() {
        guard let panel else { return }
        if panel.occlusionState.contains(.visible) {
            if panel.isVisible { opened() }
        } else if !panel.isVisible {
            closed()
        }
    }

    private func closed() {
        guard revealed else { return }
        revealed = false                                   // sans animation : prêt pour la prochaine ouverture
        // Fermé par une ligne choisie ou d'un clic sur l'icône (pas d'un clic dans une autre app) alors qu'une
        // fenêtre de l'app était devant : elle y reste.
        let byItemOrIcon = closing || (statusButton?.window?.frame.contains(NSEvent.mouseLocation) ?? false)
        closing = false
        guard let window = frontWindow, byItemOrIcon else { frontWindow = nil; return }
        frontWindow = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard window.isVisible, !window.isMiniaturized else { return }
            // Une fenêtre de l'app a déjà la main (celle qu'une ligne vient d'ouvrir, l'Organiser…) : elle la garde.
            if let key = NSApp.keyWindow, key !== self?.panel, key.isVisible { return }
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: Outils

    /// Fenêtres de l'app qu'on peut avoir devant soi (principale, guide…), de la plus en avant à la plus en arrière.
    private var appWindows: [NSWindow] {
        NSApp.orderedWindows.filter { $0 !== panel && $0.isVisible && !$0.isMiniaturized && $0.canBecomeMain }
    }

    /// Bouton de l'icône dans la barre des menus (créé par SwiftUI pour MenuBarExtra).
    private var statusButton: NSStatusBarButton? {
        for window in NSApp.windows where window.className.contains("NSStatusBarWindow") {
            if let button = Self.find(NSStatusBarButton.self, in: window.contentView) { return button }
        }
        return nil
    }

    private static func find<T: NSView>(_ type: T.Type, in view: NSView?) -> T? {
        guard let view else { return nil }
        if let match = view as? T { return match }
        for sub in view.subviews {
            if let match = find(type, in: sub) { return match }
        }
        return nil
    }
}

extension View {
    /// Contenu du menu : sort de l'icône (fondu, léger agrandissement depuis le haut).
    func menuReveal(_ revealed: Bool) -> some View {
        modifier(MenuReveal(revealed: revealed, index: nil))
    }

    /// Ligne du menu : arrive juste après la précédente (`index` : sa place dans le menu).
    func menuRevealRow(_ revealed: Bool, index: Int) -> some View {
        modifier(MenuReveal(revealed: revealed, index: index))
    }
}

private struct MenuReveal: ViewModifier {
    let revealed: Bool
    let index: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content.opacity(revealed ? 1 : 0)
        } else if let index {
            content
                .opacity(revealed ? 1 : 0)
                .offset(y: revealed ? 0 : -7)
                .animation(revealed ? .spring(response: 0.36, dampingFraction: 0.86).delay(0.02 + Double(index) * 0.016)
                                    : nil, value: revealed)
        } else {
            content
                .opacity(revealed ? 1 : 0)
                .scaleEffect(revealed ? 1 : 0.94, anchor: .top)
        }
    }
}
