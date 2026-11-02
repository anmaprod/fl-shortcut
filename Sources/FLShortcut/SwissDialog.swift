// Questions de l'app au style suisse (02/11 : « la petite page Enregistrer la nouvelle macro… dans le style suisse,
// pour que ça soit en cohérence avec le logiciel ») : à la place des fenêtres de macOS (NSAlert), un panneau noir,
// le titre en gras souligné de blanc, le texte en gris, les boutons rectangulaires en capitales ; le premier est le
// bouton principal (blanc, Entrée), à droite ; le dernier annule (Échap) ; une action qui supprime est rouge.
import AppKit
import SwiftUI

enum SwissDialog {
    /// Montre la question et attend la réponse (comme une alerte de macOS) : l'indice du bouton choisi.
    /// `image` : une image sous le texte (fenêtre MIDI Settings) ; `list` : des lignes dans une liste qui défile.
    static func run(_ title: String, _ text: String, buttons: [String], destructive: Int? = nil,
                    image: NSImage? = nil, list: [String]? = nil) -> Int {
        let choice = Box(max(buttons.count - 1, 0))
        // Sans barre de titre : coins carrés (02/11 : une fenêtre à barre de titre a les coins arrondis de macOS),
        // un trait fin #333 tout autour (SwissDialogView).
        let panel = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: SwissDialogView.width, height: 160),
                             styleMask: [.borderless], backing: .buffered, defer: false)
        panel.hasShadow = true
        panel.backgroundColor = .black
        panel.isMovableByWindowBackground = true
        panel.level = .modalPanel
        panel.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: SwissDialogView(title: title, text: text, buttons: buttons,
                                                           destructive: destructive, image: image,
                                                           list: list) { index in
            choice.value = index
            NSApp.stopModal()
        })
        panel.contentView = host
        panel.setContentSize(host.fittingSize)
        if let parent = NSApp.keyWindow ?? NSApp.mainWindow {
            let f = parent.frame
            panel.setFrameOrigin(NSPoint(x: f.midX - panel.frame.width / 2, y: f.midY - panel.frame.height / 2 + 60))
        } else {
            panel.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        NSApp.runModal(for: panel)
        panel.orderOut(nil)
        return choice.value
    }

    private final class Box {
        var value: Int
        init(_ value: Int) { self.value = value }
    }

    /// Une fenêtre sans barre de titre ne prend pas le clavier d'elle-même : Entrée et Échap doivent y arriver.
    private final class KeyPanel: NSPanel {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { true }
    }
}

struct SwissDialogView: View {
    static let width: CGFloat = 460
    let title: String
    let text: String
    let buttons: [String]
    var destructive: Int? = nil
    var image: NSImage? = nil
    var list: [String]? = nil
    let answer: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(Swiss.title(22)).tracking(Swiss.titleTracking(22))
                .foregroundStyle(Swiss.text)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .swissRule()
            if !text.isEmpty {
                Text(text)
                    .font(.system(size: 13))
                    .foregroundStyle(Swiss.soft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let image {
                let width = Self.width - 48
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: width)
                    .overlay(Rectangle().strokeBorder(Swiss.line, lineWidth: 1))
            }
            if let list, !list.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(list.indices, id: \.self) { i in
                            Text(list[i])
                                .font(.system(size: 11))
                                .foregroundStyle(Swiss.text)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(10)
                }
                .frame(height: 200)
                .overlay(Rectangle().strokeBorder(Swiss.line, lineWidth: 1))
            }
            // Le principal à droite, puis les autres vers la gauche ; le dernier (annuler) tout à gauche.
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                ForEach(Array(buttons.indices.reversed()), id: \.self) { index in
                    button(index)
                }
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 24)
        .padding(.top, 30)
        .padding(.bottom, 22)
        .frame(width: Self.width, alignment: .leading)
        .background(Swiss.background)
        .overlay(Rectangle().strokeBorder(Swiss.line, lineWidth: 1))
    }

    @ViewBuilder private func button(_ index: Int) -> some View {
        let b = Button(buttons[index]) { answer(index) }
            .buttonStyle(CapsuleButtonStyle(prominent: index == 0 && index != destructive, danger: index == destructive))
            .controlSize(.large)
            .fixedSize()
        if index == 0 {
            b.keyboardShortcut(.defaultAction)
        } else if index == buttons.count - 1 {
            b.keyboardShortcut(.cancelAction)
        } else {
            b
        }
    }
}
