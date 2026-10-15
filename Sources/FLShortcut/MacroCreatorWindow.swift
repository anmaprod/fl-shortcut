// Créateur de macros DANS la fenêtre principale, comme un dossier dans le Finder : on y entre depuis la page Macros,
// la flèche ← en haut à gauche ramène aux raccourcis (EditorView). Plus de fenêtre à part à chercher.
// - Le modèle du créateur n'existe que pendant qu'il est affiché : au retour, brouillon enregistré (ou supprimé /
//   rétabli, au choix de l'utilisateur), « Montrer dans FL… » et essai en préparation arrêtés, besoins rendus
//   (MacroEditorModel.close), puis vue et modèle lâchés, mémoire rendue au système (mesure de la CI).
// - Pendant qu'il est affiché, la fenêtre reste devant FL (niveau flottant tant que FL ou l'app est au premier plan) ;
//   elle passe derrière pendant « Montrer dans FL… », « Enregistrer des clics », un essai ou une macro (leurs clics ne
//   doivent jamais tomber sur elle), puis revient devant. Rien au repos : l'observateur d'activation n'existe que
//   pendant que le créateur est affiché.
import AppKit
import SwiftUI

enum CreatorPresence {
    /// Fenêtre qui montre le créateur (nil sinon) : les macros et l'apprentissage la font passer derrière.
    private static weak var window: NSWindow?
    /// Niveau de la fenêtre avant le créateur, rendu au retour.
    private static var previousLevel: NSWindow.Level = .normal
    /// Derrière FL : « Montrer dans FL… », « Enregistrer des clics », essai ou macro en cours.
    private static var aside = false
    private static var activationObserver: NSObjectProtocol?

    /// Le créateur s'affiche dans `w` : devant FL dès maintenant, et tant qu'il reste affiché.
    static func attach(_ w: NSWindow) {
        guard window !== w else { return }
        detach()
        window = w
        previousLevel = w.level
        aside = false
        refreshLevel()
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { _ in refreshLevel() }
    }

    /// Le créateur n'est plus affiché : la fenêtre reprend son niveau, l'observateur disparaît.
    static func detach() {
        if let o = activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(o) }
        activationObserver = nil
        if let w = window, w.level != previousLevel { w.level = previousLevel }
        window = nil
        aside = false
    }

    /// FL va recevoir des clics de l'utilisateur ou de la macro : la fenêtre du créateur passe derrière.
    static func stepAside() {
        guard let w = window, !w.isMiniaturized else { return }
        aside = true
        w.level = .normal
        if w.isVisible { w.orderBack(nil) }
    }

    /// Fini : le créateur revient devant FL, sans lui prendre le premier plan.
    static func comeBack() {
        guard aside else { return }
        aside = false
        refreshLevel()
        if let w = window, w.level == .floating, w.isVisible, !w.isMiniaturized { w.orderFront(nil) }
    }

    /// Devant les fenêtres de FL tant que FL (ou l'app) est au premier plan ; une autre app au premier plan : à sa
    /// place parmi les fenêtres, comme d'habitude.
    private static func refreshLevel() {
        guard let w = window, !aside else { return }
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let besideFL = front == getpid() || front.map { EventTap.shared.currentConfig.flPIDs.contains($0) } ?? false
        let level: NSWindow.Level = besideFL ? .floating : previousLevel
        if w.level != level { w.level = level }
    }

    /// App au repos après le créateur : AppKit ne vide sa réserve d'objets « autoreleased » qu'au prochain
    /// événement. Un événement la vide tout de suite ; puis la mémoire libérée est rendue au système.
    static func releaseMemory() {
        DispatchQueue.main.async {
            if let wake = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0,
                                             windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) {
                NSApplication.shared.postEvent(wake, atStart: false)
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) {
                _ = malloc_zone_pressure_relief(nil, 0)
            }
        }
    }
}

/// Donne la fenêtre AppKit qui affiche la vue (dès qu'elle y est posée).
struct WindowReader: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> ReaderView {
        let v = ReaderView()
        v.onWindow = onWindow
        return v
    }

    func updateNSView(_ nsView: ReaderView, context: Context) { nsView.onWindow = onWindow }

    final class ReaderView: NSView {
        var onWindow: ((NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { onWindow?(window) }
        }
    }
}
