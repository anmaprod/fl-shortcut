// Questions de l'app au style suisse (02/11 : « la petite page Enregistrer la nouvelle macro… dans le style suisse,
// pour que ça soit en cohérence avec le logiciel ») : à la place des fenêtres de macOS (NSAlert), un panneau noir aux
// coins carrés, le titre en gras souligné de blanc, le texte en gris, les boutons rectangulaires en capitales, séparés ;
// le premier est le bouton principal (blanc, Entrée), à droite ; le dernier annule (Échap) ; une action qui supprime
// est rouge.
// Faite en AppKit, comme NSAlert (2e retour du 02/11 : « les boutons ne fonctionnaient pas et n'étaient pas séparés ») :
// la question s'ouvre souvent depuis l'action d'un bouton de SwiftUI ; une fenêtre de SwiftUI ouverte à ce moment-là
// dans une boucle modale ne recevait pas les clics. Des boutons d'AppKit, si.
import AppKit

enum SwissDialog {
    static let width: CGFloat = 460
    private static let margin: CGFloat = 24
    private static var inner: CGFloat { width - 2 * margin }

    /// Montre la question et attend la réponse (comme une alerte de macOS) : l'indice du bouton choisi. `image` : une
    /// image sous le texte (fenêtre MIDI Settings) ; `list` : des lignes dans une liste qui défile.
    static func run(_ title: String, _ text: String, buttons: [String], destructive: Int? = nil,
                    image: NSImage? = nil, list: [String]? = nil) -> Int {
        let names = buttons.isEmpty ? [String(localized: "OK")] : buttons
        let cancel = names.count - 1
        let answer = Answer()
        let panel = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: 160),
                             styleMask: [.borderless], backing: .buffered, defer: false)
        panel.hasShadow = true
        panel.backgroundColor = dialogColor(.background)
        panel.isMovableByWindowBackground = true
        panel.level = .modalPanel
        panel.isReleasedWhenClosed = false
        panel.appearance = NSAppearance(named: AppTheme.current.appearanceName)
        panel.onCancel = { answer.stop(cancel) }

        let content = makeContent(title: title, text: text, names: names, destructive: destructive,
                                  image: image, list: list, answer: answer)
        panel.contentView = content
        content.layoutSubtreeIfNeeded()
        panel.setContentSize(NSSize(width: width, height: content.fittingSize.height))
        if let parent = NSApp.keyWindow ?? NSApp.mainWindow {
            let f = parent.frame
            panel.setFrameOrigin(NSPoint(x: f.midX - panel.frame.width / 2, y: f.midY - panel.frame.height / 2 + 60))
        } else {
            panel.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        let code = NSApp.runModal(for: panel).rawValue - Answer.base
        panel.orderOut(nil)
        return names.indices.contains(code) ? code : cancel
    }

    // MARK: Contenu

    private static func makeContent(title: String, text: String, names: [String], destructive: Int?,
                                     image: NSImage?, list: [String]?, answer: Answer) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 30, left: margin, bottom: 22, right: margin)
        stack.translatesAutoresizingMaskIntoConstraints = false

        // Le titre, souligné d'un trait blanc sur toute la largeur.
        let heading = label(title, font: NSFont(name: "HelveticaNeue-Bold", size: 22) ?? .boldSystemFont(ofSize: 22),
                            color: dialogColor(.text), kern: -22 * 0.039)
        stack.addArrangedSubview(heading)
        stack.setCustomSpacing(10, after: heading)
        stack.addArrangedSubview(rule(dialogColor(.text)))

        if !text.isEmpty {
            stack.addArrangedSubview(label(text, font: .systemFont(ofSize: 13), color: dialogColor(.soft)))
        }
        if let image {
            let view = NSImageView(image: image)
            view.imageScaling = .scaleProportionallyUpOrDown
            view.wantsLayer = true
            view.layer?.borderColor = dialogColor(.line).cgColor
            view.layer?.borderWidth = 1
            view.translatesAutoresizingMaskIntoConstraints = false
            let ratio = image.size.height / max(image.size.width, 1)
            NSLayoutConstraint.activate([view.widthAnchor.constraint(equalToConstant: inner),
                                         view.heightAnchor.constraint(equalToConstant: (inner * ratio).rounded())])
            stack.addArrangedSubview(view)
        }
        if let list, !list.isEmpty {
            stack.addArrangedSubview(scrollingList(list))
        }

        // Les boutons à droite, séparés : le principal tout à droite, celui qui annule tout à gauche.
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        for index in names.indices.reversed() {
            let button = SwissButton(title: names[index], prominent: index == 0 && index != destructive,
                                     danger: index == destructive)
            button.tag = index
            button.target = answer
            button.action = #selector(Answer.pressed(_:))
            if index == 0 { button.keyEquivalent = "\r" }
            row.addView(button, in: .trailing)
        }
        row.widthAnchor.constraint(equalToConstant: inner).isActive = true
        stack.setCustomSpacing(22, after: stack.arrangedSubviews.last ?? heading)
        stack.addArrangedSubview(row)

        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = dialogColor(.background).cgColor
        root.layer?.borderColor = dialogColor(.line).cgColor                 // trait fin tout autour (#333 sous Noir)
        root.layer?.borderWidth = 1
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            root.widthAnchor.constraint(equalToConstant: width),
        ])
        return root
    }

    private static func label(_ string: String, font: NSFont, color: NSColor, kern: CGFloat = 0) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: string)
        field.attributedStringValue = NSAttributedString(string: string, attributes: [
            .font: font, .foregroundColor: color, .kern: kern,
        ])
        field.preferredMaxLayoutWidth = inner
        field.isSelectable = false
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: inner).isActive = true
        return field
    }

    private static func rule(_ color: NSColor) -> NSView {
        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = color.cgColor
        line.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([line.widthAnchor.constraint(equalToConstant: inner),
                                     line.heightAnchor.constraint(equalToConstant: 1)])
        return line
    }

    private static func scrollingList(_ lines: [String]) -> NSView {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: inner, height: 200))
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true
        scroll.backgroundColor = dialogColor(.background)
        scroll.borderType = .noBorder
        scroll.wantsLayer = true
        scroll.layer?.borderColor = dialogColor(.line).cgColor
        scroll.layer?.borderWidth = 1
        let textView = NSTextView(frame: NSRect(origin: .zero, size: scroll.contentSize))
        textView.isEditable = false
        textView.drawsBackground = true
        textView.backgroundColor = dialogColor(.background)
        textView.textColor = dialogColor(.text)
        textView.font = .systemFont(ofSize: 11)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.string = lines.joined(separator: "\n")
        scroll.documentView = textView
        scroll.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([scroll.widthAnchor.constraint(equalToConstant: inner),
                                     scroll.heightAnchor.constraint(equalToConstant: 200)])
        return scroll
    }

    // MARK: Réponse

    /// Reçoit le clic d'un bouton et arrête la boucle modale avec son indice.
    private final class Answer: NSObject {
        static let base = 1000

        func stop(_ index: Int) {
            NSApp.stopModal(withCode: NSApplication.ModalResponse(rawValue: Self.base + index))
        }

        @objc func pressed(_ sender: NSButton) { stop(sender.tag) }
    }

    /// Une fenêtre sans barre de titre ne prend pas le clavier d'elle-même : Entrée et Échap doivent y arriver.
    private final class KeyPanel: NSPanel {
        var onCancel: (() -> Void)?
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { true }
        override func cancelOperation(_ sender: Any?) { onCancel?() }
    }
}

/// Bouton du style suisse en AppKit (questions de l'app) : rectangle aux coins carrés, texte en capitales espacées ;
/// le principal blanc plein, texte noir ; les autres noirs bordés de blanc ; celui qui supprime rouge. Au survol, le
/// bordé devient blanc plein et le principal noir bordé (comme `SwissButtonBody`).
final class SwissButton: NSButton {
    private let prominent: Bool
    private let danger: Bool
    private var hovering = false { didSet { needsDisplay = true } }
    private var tracking: NSTrackingArea?

    init(title: String, prominent: Bool, danger: Bool) {
        self.prominent = prominent
        self.danger = danger
        super.init(frame: .zero)
        self.title = title
        isBordered = false
        setButtonType(.momentaryPushIn)
        focusRingType = .none
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityLabel(title)
    }

    required init?(coder: NSCoder) { nil }

    private func text(_ color: NSColor) -> NSAttributedString {
        NSAttributedString(string: title.uppercased(), attributes: [
            .font: NSFont(name: "HelveticaNeue-Bold", size: 12) ?? .boldSystemFont(ofSize: 12),
            .foregroundColor: color,
            .kern: 1.2,
        ])
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: ceil(text(.white).size().width) + 40, height: 38)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override func draw(_ dirtyRect: NSRect) {
        let lit = hovering && isEnabled
        let fill: NSColor, edge: NSColor, ink: NSColor
        if danger {
            fill = lit ? dialogColor(.red) : dialogColor(.background)
            edge = dialogColor(.red)
            ink = lit ? dialogColor(.background) : dialogColor(.red)
        } else {
            let filled = prominent != lit
            fill = filled ? dialogColor(.text) : dialogColor(.background)
            edge = dialogColor(.text)
            ink = filled ? dialogColor(.background) : dialogColor(.text)
        }
        fill.setFill()
        bounds.fill()
        edge.setStroke()
        let frame = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5))
        frame.lineWidth = 1
        frame.stroke()
        if isHighlighted {
            NSColor(white: 0.5, alpha: 0.35).setFill()
            bounds.fill(using: .sourceOver)
        }
        let label = text(ink)
        let size = label.size()
        label.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2))
    }
}

/// Couleur du thème en cours pour les questions (dessinées à leur ouverture ; elles ne restent pas ouvertes pendant un
/// changement de thème, qui se fait dans la page Mon compte).
private func dialogColor(_ token: SwissPalette.Token) -> NSColor {
    let theme = AppTheme.current
    return SwissPalette.nsColor(SwissPalette.of(theme, dark: theme == .noir).value(token))
}
