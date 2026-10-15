// Touches seules (sans ⌘ ⌃ ⌥) : elles lancent leur raccourci, SAUF quand FL s'en sert à ce moment-là. Plus de
// question « Touche seule… Garder quand même ? » à la création du raccourci.
// - Menu de FL ouvert : ses lettres choisissent un élément.
// - Boîte de FL devant (renommer, taper une valeur, recherche…) : niveau des boîtes de dialogue, ou petite fenêtre
//   devant la fenêtre principale.
// - Champ de texte qui a le focus dans FL (si FL l'expose à l'Accessibilité).
// - Clavier-piano actif : coche de « Typing keyboard to piano keyboard » dans le menu Options de la barre de macOS
//   (FL 2024.2 et plus ; le script de FL ne sait pas lire cet état). L'élément du menu est trouvé une fois, puis
//   seule sa coche est relue.
// Évalué seulement quand une touche seule lance un raccourci (EventTap), jamais au repos ; métadonnées des fenêtres
// et Accessibilité seulement, délais courts : jamais l'écran, jamais le texte tapé.
import AppKit
import ApplicationServices

final class TypingGuard {
    static let shared = TypingGuard()

    enum Reason: String {
        case menu, dialog, textField, pianoKeyboard
    }

    /// Titres possibles de l'élément du clavier-piano (FL en anglais ou en français).
    static let pianoTitles = ["typing keyboard to piano", "clavier d'ordinateur", "typing keyboard"]

    private struct PianoItem {
        let pid: Int32
        let element: AXUIElement?
        let searchedAt: TimeInterval
    }

    private let piano = Locked<PianoItem?>(nil)

    private init() {}

    /// Raison de laisser une touche seule à FL en ce moment, sinon nil (le raccourci est lancé).
    func reason(pid: Int32) -> Reason? {
        let snap = WinSnapshot.take(pid: pid)
        if snap.fl.contains(where: { $0.layer > 8 && $0.isMenuLike }) { return .menu }
        if let front = snap.fl.first(where: { (0...8).contains($0.layer) }), Self.isDialog(front, among: snap.fl) {
            return .dialog
        }
        if focusedIsText(pid: pid) { return .textField }
        if pianoKeyboardOn(pid: pid) { return .pianoKeyboard }
        return nil
    }

    /// Fenêtre de FL tout devant qui est une boîte : niveau des boîtes de dialogue, ou petite fenêtre devant la
    /// fenêtre principale (moins d'un sixième de sa surface).
    static func isDialog(_ front: WinInfo, among windows: [WinInfo]) -> Bool {
        if front.layer == 8 { return true }
        guard front.layer == 0,
              let main = windows.filter({ $0.layer == 0 }).max(by: { area($0) < area($1) }),
              main.number != front.number else { return false }
        return area(front) < area(main) / 6
    }

    private static func area(_ w: WinInfo) -> CGFloat { w.bounds.width * w.bounds.height }

    private func focusedIsText(pid: Int32) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.05)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return false }
        let focused = value as! AXUIElement
        AXUIElementSetMessagingTimeout(focused, 0.05)
        let role = AXProbe.string(focused, kAXRoleAttribute as String) ?? ""
        let textRoles: Set<String> = [kAXTextFieldRole as String, kAXTextAreaRole as String, kAXComboBoxRole as String]
        return textRoles.contains(role)
    }

    /// Coche du clavier-piano. L'élément du menu est cherché une fois par processus de FL (puis au plus toutes les
    /// 10 s s'il manque ou ne répond plus) ; ensuite seule sa coche est relue.
    private func pianoKeyboardOn(pid: Int32) -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        var known = piano.value
        if known?.pid != pid || (known?.element == nil && now - (known?.searchedAt ?? 0) > 10) {
            known = PianoItem(pid: pid, element: MenuBarAX.item(pid: pid, titleContains: Self.pianoTitles), searchedAt: now)
            piano.withLock { $0 = known }
        }
        guard let item = known?.element else { return false }
        AXUIElementSetMessagingTimeout(item, 0.05)
        guard AXProbe.string(item, kAXRoleAttribute as String) != nil else {
            piano.withLock { $0 = PianoItem(pid: pid, element: nil, searchedAt: 0) }   // menus reconstruits : recherche
            return false
        }
        return !(AXProbe.string(item, kAXMenuItemMarkCharAttribute as String) ?? "").isEmpty
    }
}
