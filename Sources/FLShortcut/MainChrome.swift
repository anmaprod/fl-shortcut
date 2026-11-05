// Fenêtre principale comme la maquette du 28/10 (29/10, le propriétaire : « j'ai vraiment besoin que tu fasses à
// l'identique ») : fond noir plein, barre de gauche dans une plaque claire arrondie (les boutons fermer / réduire /
// agrandir dedans, en haut), en-tête de la page (titre en gras, capsule du compte à droite), raccourcis en cartes
// titrées sur deux colonnes. Pièces communes à la page des raccourcis et au créateur de macros ; tout est dessiné,
// rien n'est du verre de macOS.
import AppKit
import SwiftUI

/// Réglage AppKit de la fenêtre principale : titre caché, barre de titre transparente au-dessus du contenu, barre
/// d'outils vide (les boutons fermer / réduire / agrandir descendent à 19 points du coin, dans la plaque de gauche).
/// Cette bande de 52 points ne laisse pas passer les clics (vrai clic de la CI du 29/10) : les boutons de la page sont
/// posés dessous (`contentTop`).
enum MainWindowChrome {
    /// Hauteur de la barre de titre (barre d'outils unifiée) : rien de cliquable au-dessus.
    static let titleBarHeight: CGFloat = 52
    /// Haut de l'en-tête des pages, sous la barre de titre (la fenêtre a 8 points de marge).
    static let contentTop: CGFloat = titleBarHeight - 8

    private static var watched = Set<ObjectIdentifier>()

    /// Réglé tout de suite, encore juste après (SwiftUI règle la fenêtre après l'avoir posée : il remettait le titre
    /// et une bande opaque) et chaque fois qu'elle reprend la main.
    static func keep(_ window: NSWindow) {
        apply(to: window)
        for delay in [0.05, 0.3, 1.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak window] in
                if let window { apply(to: window) }
            }
        }
        let id = ObjectIdentifier(window)
        guard !watched.contains(id) else { return }
        watched.insert(id)
        _ = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window,
                                                   queue: .main) { note in
            if let window = note.object as? NSWindow { apply(to: window) }
        }
    }

    static func apply(to window: NSWindow) {
        if window.titleVisibility != .hidden { window.titleVisibility = .hidden }
        if !window.titlebarAppearsTransparent { window.titlebarAppearsTransparent = true }
        if !window.styleMask.contains(.fullSizeContentView) { window.styleMask.insert(.fullSizeContentView) }
        window.backgroundColor = Swiss.NS.background       // style suisse (01/11) : fond plein du thème
        if window.titlebarSeparatorStyle != .none { window.titlebarSeparatorStyle = .none }
        if window.toolbar == nil {
            let toolbar = NSToolbar(identifier: "fl.fenetre-principale")
            toolbar.allowsUserCustomization = false
            toolbar.displayMode = .iconOnly
            window.toolbar = toolbar
        }
        if window.toolbar?.isVisible == false { window.toolbar?.isVisible = true }
        if window.toolbarStyle != .unified { window.toolbarStyle = .unified }
    }
}

extension View {
    /// Titre et fond de la barre de titre cachés aussi côté SwiftUI (qui les remettait), sans bande ni effet de bord
    /// en haut (macOS 26).
    @ViewBuilder func hiddenWindowChrome() -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            toolbar(removing: .title)
                .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
                .scrollEdgeEffectHidden(true, for: .top)
        } else if #available(macOS 15.0, *) {
            toolbar(removing: .title).toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        } else {
            self
        }
        #else
        if #available(macOS 15.0, *) {
            toolbar(removing: .title).toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        } else {
            self
        }
        #endif
    }
}

/// Plaque claire des maquettes : dégradé blanc (plus clair en haut), bord fin, reflet en haut, ombre douce.
struct MockPlate: View {
    var cornerRadius: CGFloat
    var top = 0.10
    var bottom = 0.045
    var border = 0.15

    var body: some View {
        if Swiss.flat {
            // Style suisse (01/11) : plus de plaque, le noir de la fenêtre. Une carte (Mon compte, Aide, Communauté…)
            // devient un bloc posé entre deux traits fins ; les colonnes (barre de gauche, créateur) n'ont rien.
            if cornerRadius >= 19 {
                Color.clear.accessibilityHidden(true)
            } else {
                Rectangle().fill(Swiss.background)
                    .overlay(alignment: .top) { Rectangle().fill(Swiss.line).frame(height: 1) }
                    .overlay(alignment: .bottom) { Rectangle().fill(Swiss.line).frame(height: 1) }
                    .accessibilityHidden(true)
            }
        } else {
            plate
        }
    }

    private var plate: some View {
        let shape = Rectangle()
        return shape.fill(LinearGradient(colors: [Color.white.opacity(top), Color.white.opacity(bottom)],
                                  startPoint: .top, endPoint: .bottom))
            .overlay(shape.strokeBorder(Color.white.opacity(border), lineWidth: 1))
            .overlay(shape.inset(by: 1).strokeBorder(LinearGradient(colors: [Color.white.opacity(0.2), Color.clear],
                                                                    startPoint: .top, endPoint: .center),
                                                     lineWidth: 1))
            .shadow(color: Color.black.opacity(0.22), radius: 12, y: 8)
            .accessibilityHidden(true)
    }
}

/// Capsule claire de l'en-tête de page (maquette : le bouton du compte dedans).
struct HeaderCapsule<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        // Style suisse : les boutons côte à côte, sans capsule.
        HStack(spacing: 8) { content }
    }
}

/// Bouton rond de l'en-tête (44 points) : une icône seule, son nom en bulle d'aide ; au survol, plein de bleu.
struct HeaderIconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        // Style suisse : un carré de 34 points bordé de blanc ; au survol, blanc plein.
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 34, height: 34)
                .overlay(Rectangle().strokeBorder(Swiss.text, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.35)
        .menuHover(tint: Swiss.text, cornerRadius: 0, enabled: enabled)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Titre de groupe de la barre de gauche (« FL Studio », « Automatiser »…) et ses lignes.
struct SidebarGroup<Content: View>: View {
    private let title: Text
    private let content: Content

    init(_ title: Text, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            title
                .swissLabel(size: 10)
                .padding(.horizontal, 10)
                .padding(.bottom, 4)
                .accessibilityAddTraits(.isHeader)
            content
        }
    }
}

/// Une ligne de la barre de gauche (style suisse) : le carré de la page (PageSquare), puis le nom.
struct SidebarLabel: View {
    let title: Text
    let symbol: String
    let tint: Color
    /// Page ouverte : son carré est rouge.
    var selected = false

    var body: some View {
        HStack(spacing: 10) {
            PageSquare(selected: selected)
            title.font(.system(size: 13)).lineLimit(1)
            Spacer(minLength: 0)
        }
    }
}

/// Carré d'une page (barre de gauche, résultats de la recherche), proposition A choisie le 05/11 (« le A est
/// parfait ») à la place d'une couleur par page : creux, d'un trait fin à l'encre ; plein du rouge de la marque pour
/// la page ouverte. Ligne survolée (pleine d'encre) : le trait prend la couleur du fond.
struct PageSquare: View {
    var selected = false
    @Environment(\.hoverFilled) private var filled

    var body: some View {
        Group {
            if selected {
                Rectangle().fill(Swiss.brandRed)
            } else {
                Rectangle().strokeBorder(filled ? Swiss.background : Swiss.text, lineWidth: 1)
            }
        }
        .frame(width: 8, height: 8)
        .accessibilityHidden(true)
    }
}

/// Recherche de la barre de gauche : la loupe (dessinée par SwiftUI à côté), puis un champ de texte d'AppKit sans cadre.
/// La garde de la recherche (SearchFocusGuard) la reconnaît : elle n'a la main qu'après un clic dedans ou ⌘F.
struct SidebarSearchField: NSViewRepresentable {
    @Binding var text: String
    let prompt: String
    /// Augmenté pour lui donner la main (⌘F).
    let focusSerial: Int

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSTextField {
        let field = PlainSearchField()
        let font = NSFont.systemFont(ofSize: 13)
        field.font = font
        field.textColor = Swiss.NS.text
        field.placeholderAttributedString = NSAttributedString(
            string: prompt, attributes: [.font: font, .foregroundColor: SwissPalette.adaptive(.text, alpha: 0.55)])
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.lineBreakMode = .byClipping
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.delegate = context.coordinator
        field.setAccessibilityLabel(prompt)
        field.setAccessibilityRole(.textField)
        field.stringValue = text
        SearchFocusGuard.GuardView.fields.add(field)          // un clic dans sa capsule la choisit
        context.coordinator.serial = focusSerial
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        // Le thème : texte de la couleur de la barre (noire sous Orange, d'après l'apparence de SwiftUI).
        let appearance: NSAppearance.Name = context.environment.colorScheme == .dark ? .darkAqua : .aqua
        if field.appearance?.name != appearance { field.appearance = NSAppearance(named: appearance) }
        context.coordinator.text = $text
        if field.stringValue != text { field.stringValue = text }
        if context.coordinator.serial != focusSerial {
            context.coordinator.serial = focusSerial
            DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var serial = 0

        init(text: Binding<String>) { self.text = text }

        func controlTextDidChange(_ note: Notification) {
            guard let field = note.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
        }

        /// Échap vide la recherche, comme avant (recherche de macOS).
        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.cancelOperation(_:)), !textView.string.isEmpty else { return false }
            textView.string = ""
            text.wrappedValue = ""
            return true
        }
    }
}

/// Champ de recherche dont rien ne bouge au clic. Vidéos du 03/11 puis du 04/11 (« quand on clique dans la barre de
/// recherche, la barre et le mot rechercher se décalent… j'aimerais que la barre soit blanche pas bleue ») : la recherche
/// de macOS (NSSearchField) dessinait « Rechercher » au repos et le texte tapé à deux places différentes, et son curseur
/// prenait la couleur d'accent. Un simple champ de texte sans cadre écrit au même endroit au repos et pendant la frappe ;
/// la loupe est à côté, dessinée par SwiftUI. Curseur blanc, sélection grise. Le nom de la classe contient
/// « SearchField » : la garde de la recherche et le relevé de la CI la reconnaissent.
final class PlainSearchField: NSTextField {
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted, let editor = currentEditor() as? NSTextView {
            editor.insertionPointColor = Swiss.NS.text
            editor.selectedTextAttributes = [.backgroundColor: SwissPalette.adaptive(.text, alpha: 0.25),
                                             .foregroundColor: Swiss.NS.text]
        }
        return accepted
    }
}

/// Carte de raccourcis : son titre gris au-dessus, ses lignes dans une plaque claire, un trait fin entre deux lignes.
struct TitledCard<Item: Identifiable, Row: View>: View {
    let title: String
    let items: [Item]
    let tint: Color
    @ViewBuilder let row: (Item) -> Row

    var body: some View {
        // Style suisse : le titre en petites capitales blanches souligné de blanc, puis les lignes séparées d'un trait
        // fin ; au survol, la ligne entière en blanc.
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .swissLabel(Swiss.text)
                .padding(.bottom, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .swissRule()
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { _, item in
                    row(item)
                        .padding(.horizontal, 4)
                        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                        .swissRule(Swiss.faint)
                        .menuHover(tint: Swiss.text, cornerRadius: 0)
                }
            }
        }
        // Thème Orange : une carte noire, comme la maquette.
        .swissCard(padding: 14)
    }
}

/// Cartes sur une ou deux colonnes, comme les colonnes de la maquette : la première de haut en bas, puis la suivante,
/// coupées là où les colonnes ont la hauteur la plus proche. Une seule carte sur deux colonnes : la moitié gauche.
struct CardMasonry<Card: Identifiable, CardView: View>: View {
    let cards: [Card]
    let columns: Int
    let size: (Card) -> Int
    @ViewBuilder let card: (Card) -> CardView

    var body: some View {
        let split = OrganizerView.familyColumns(cards, count: columns, size: size)
        HStack(alignment: .top, spacing: 28) {
            ForEach(Array(split.enumerated()), id: \.offset) { _, column in
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(column) { card($0) }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
            if columns > 1, split.count < columns {
                Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
            }
        }
    }
}
