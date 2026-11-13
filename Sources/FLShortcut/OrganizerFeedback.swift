// Organiser : « Pas content ? » (demande du propriétaire : des questions à cocher, avec « Autre » en bas, pour que
// l'IA apprenne de ses erreurs). Ce qui n'allait pas (cases), la bonne famille ou sorte des sons mal rangés (l'IA les
// retient sur le Mac et, avec l'accord de la personne, les partage : CorrectionsIA), et un message pour l'équipe
// (Playlist, Mixer, aspect, « Autre » : ce que l'IA ne peut pas apprendre). Les changements faits dans l'aperçu
// comptent aussi comme corrections, sans rien demander.
import SwiftUI

struct OrganizerFeedback: Equatable {
    enum Reason: String, CaseIterable, Identifiable {
        case voice, family, kind, playlist, mixer, look

        var id: String { rawValue }

        var label: String {
            switch self {
            case .voice: return String(localized: "Une voix n'est pas rangée dans Voix")
            case .family: return String(localized: "Un son est dans la mauvaise famille")
            case .kind: return String(localized: "Un son a le mauvais nom (Kick, Snare, Pad…)")
            case .playlist: return String(localized: "La Playlist n'est pas bien rangée")
            case .mixer: return String(localized: "Le Mixer n'est pas bien rangé")
            case .look: return String(localized: "Les couleurs ou les noms ne me plaisent pas")
            }
        }

        /// Pour l'équipe (elle lit le français), quelle que soit la langue du Mac.
        var teamLabel: String {
            switch self {
            case .voice: return "voix mal rangée"
            case .family: return "mauvaise famille"
            case .kind: return "mauvais nom de son"
            case .playlist: return "Playlist"
            case .mixer: return "Mixer"
            case .look: return "couleurs ou noms"
            }
        }

        /// Une réponse sur les sons : on demande lesquels, et l'IA en apprend.
        var aboutSounds: Bool { self == .voice || self == .family || self == .kind }
    }

    /// La bonne réponse pour un son.
    struct Fix: Equatable {
        var family: SoundFamily
        var kind: SoundKind?
    }

    var reasons: Set<Reason> = []
    /// « Autre », en bas : un texte libre, pour l'équipe seulement (jamais pour l'IA, ni dans le journal).
    var other = false
    var otherText = ""
    /// Bonne réponse de chaque son corrigé (index du canal).
    var fixes: [Int: Fix] = [:]
    /// Aider l'ordinateur de tout le monde avec ces corrections (des nombres seulement).
    var share = false

    var asksSounds: Bool { reasons.contains { $0.aboutSounds } }
    /// 13/11 : « Autre chose ? » est un simple champ (plus de case « Autre ») : tout texte écrit compte.
    private var text: String { otherText.trimmingCharacters(in: .whitespacesAndNewlines) }
    var canSend: Bool { !reasons.isEmpty || !text.isEmpty || !fixes.isEmpty }

    /// Le message pour l'équipe : ce que l'IA ne peut pas apprendre (Playlist, Mixer, aspect) et « Autre » ; nil :
    /// rien à lui dire.
    func teamMessage() -> String? {
        let others = Reason.allCases.filter { reasons.contains($0) && !$0.aboutSounds }
        guard !others.isEmpty || !text.isEmpty else { return nil }
        let all = Reason.allCases.filter { reasons.contains($0) }.map(\.teamLabel)
        var lines = ["Organiser, pas content" + (all.isEmpty ? "." : " : " + all.joined(separator: ", ") + ".")]
        if !text.isEmpty { lines.append(text) }
        return lines.joined(separator: "\n\n")
    }

    /// Changements de l'aperçu : chaque son écouté dont la famille, ou la sorte choisie, n'est plus celle trouvée.
    static func previewFixes(_ items: [OrganizerItem], families: [Int: SoundFamily],
                             kinds: [Int: SoundKind]) -> [Int: Fix] {
        var out: [Int: Fix] = [:]
        for item in items where item.soundPrint != nil {
            guard let family = families[item.index] else { continue }
            let kind = OrganizerApplier.kind(item.index, families: families, kinds: kinds)
            if family != item.family || (kind != nil && kind != item.kind) {
                out[item.index] = Fix(family: family, kind: kind)
            }
        }
        return out
    }
}

/// « Pas content ? » (13/11, maquette validée : « faut vraiment que ça soit beaucoup plus simple… pour chaque case
/// qu'on puisse modifier un truc ») : plus de cases à cocher. Une ligne par chose à corriger, qui ouvre l'endroit où on
/// la corrige : un son mal rangé (sa famille), le Mixer (départ de chaque famille, bus, pré-master), la Playlist (ordre
/// des familles), les couleurs (la fenêtre de couleur de FL). « Autre chose ? » part à l'équipe. « C'est noté » garde
/// tout pour les prochains rangements ; « Annuler » remet tout comme à l'ouverture.
struct OrganizerFeedbackView: View {
    @ObservedObject var controller: OrganizerController
    @State private var feedback = OrganizerFeedback()
    @State private var page: Page?
    @State private var before: (styles: [SoundFamily: FamilyStyle], options: OrganizerOptions)?

    enum Page { case sounds, mixer, playlist, colors }

    var body: some View {
        Group {
            switch page {
            case nil: list
            case .sounds: FeedbackSoundsPage(controller: controller, feedback: $feedback) { page = nil }
            case .mixer:
                FeedbackMixerPage(controller: controller, changed: { feedback.reasons.insert(.mixer) }) { page = nil }
            case .playlist:
                FeedbackPlaylistPage(controller: controller, changed: { feedback.reasons.insert(.playlist) }) { page = nil }
            case .colors:
                FeedbackColorsPage(controller: controller, changed: { feedback.reasons.insert(.look) }) { page = nil }
            }
        }
        .padding(EdgeInsets(top: 32, leading: 28, bottom: 28, trailing: 28))
        .frame(width: 480, height: 640, alignment: .topLeading)
        .background(Swiss.background)
        .onAppear {
            feedback.share = controller.sharingCorrections
            if before == nil { before = (controller.styles, controller.options) }
        }
    }

    private var soundsState: String? {
        let n = feedback.fixes.count
        guard n > 0 else { return nil }
        return n == 1 ? String(localized: "1 son corrigé") : String(localized: "\(n) sons corrigés")
    }

    private func changed(_ reason: OrganizerFeedback.Reason) -> String? {
        feedback.reasons.contains(reason) ? String(localized: "Changé") : nil
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 20) {
            FeedbackHead(title: String(localized: "pas content"),
                         sentence: String(localized: "Touche ce qui ne va pas et corrige-le. L'ordinateur s'en souviendra la prochaine fois."))
            VStack(spacing: 0) {
                FeedbackLine(number: 1, title: String(localized: "Un son est mal rangé"), state: soundsState) { page = .sounds }
                FeedbackLine(number: 2, title: String(localized: "Le Mixer"), state: changed(.mixer)) { page = .mixer }
                FeedbackLine(number: 3, title: String(localized: "La Playlist"), state: changed(.playlist)) { page = .playlist }
                FeedbackLine(number: 4, title: String(localized: "Les couleurs"), state: changed(.look)) { page = .colors }
            }
            .overlay(alignment: .top) { Rectangle().fill(Swiss.line).frame(height: 1) }
            VStack(alignment: .leading, spacing: 6) {
                Text("Autre chose ?").swissLabel(size: 10.5)
                TextField(String(localized: "Écris-le ici, ça part à l'équipe"), text: $feedback.otherText)
                    .swissField(minHeight: 40)
            }
            Spacer(minLength: 0)
            HStack(spacing: 12) {
                Button {
                    if let before { controller.restore(styles: before.styles, options: before.options) }
                    controller.feedbackShown = false
                } label: { Text("Annuler").frame(maxWidth: .infinity) }
                    .secondaryButton()
                    .keyboardShortcut(.cancelAction)
                Button { controller.submitFeedback(feedback) } label: { Text("C'est noté").frame(maxWidth: .infinity) }
                    .primaryButton()
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
        }
    }
}

/// Titre d'une page de « Pas content ? » : « ← Pas content » pour revenir (pages), le titre en minuscules avec son
/// point carré, une phrase grise, un trait d'encre dessous.
private struct FeedbackHead: View {
    let title: String
    let sentence: String
    var back: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let back {
                Button(action: back) {
                    HStack(spacing: 6) {
                        Text(verbatim: "←")
                        Text("Pas content")
                    }
                    .font(.system(size: 12, weight: .bold)).tracking(1.3)
                    .textCase(.uppercase)
                    .foregroundStyle(Swiss.text)
                    .frame(minHeight: 28)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            SwissPageTitle(text: title, size: 44)
            Text(sentence).font(.system(size: 13.5)).foregroundStyle(Swiss.soft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .swissRule()
    }
}

/// Une ligne de la liste : son numéro gris, son nom en gras, à droite ce qui a été corrigé (carré rouge) ou une flèche.
private struct FeedbackLine: View {
    let number: Int
    let title: String
    let state: String?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Text(verbatim: String(format: "%02d", number)).font(.system(size: 11)).tracking(1.3).foregroundStyle(Swiss.gray)
                    .frame(width: 18, alignment: .leading)
                Text(title).font(.system(size: 16, weight: .bold)).foregroundStyle(Swiss.text)
                Spacer(minLength: 8)
                if let state {
                    HStack(spacing: 8) {
                        Rectangle().fill(Swiss.red).frame(width: 8, height: 8)
                        Text(state).font(.system(size: 12)).foregroundStyle(Swiss.text)
                    }
                } else {
                    Text(verbatim: "→").foregroundStyle(hovering ? Swiss.text : Swiss.gray)
                }
            }
            .frame(minHeight: 60)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) { Rectangle().fill(Swiss.line).frame(height: 1) }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// « C'est bon » en bas à droite d'une page : retour à la liste.
private struct FeedbackDone: View {
    let action: () -> Void

    var body: some View {
        HStack {
            Spacer()
            Button(action: action) { Text("C'est bon").frame(minWidth: 120) }
                .primaryButton()
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
        }
    }
}

// MARK: - Un son est mal rangé

private struct FeedbackSoundsPage: View {
    @ObservedObject var controller: OrganizerController
    @Binding var feedback: OrganizerFeedback
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            FeedbackHead(title: String(localized: "les sons"),
                         sentence: String(localized: "Choisis la bonne famille du son qui n'est pas à sa place."), back: done)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(controller.correctable, id: \.index) { item in
                        FeedbackSoundRow(controller: controller, item: item, feedback: $feedback)
                    }
                }
            }
            if feedback.fixes.keys.contains(where: { index in
                controller.correctable.contains { $0.index == index && $0.soundPrint != nil }
            }) {
                Toggle(isOn: $feedback.share) {
                    Text("Aider l'ordinateur de tout le monde") + Text(verbatim: " · ").foregroundColor(Swiss.gray)
                        + Text("des nombres, jamais le son").foregroundColor(Swiss.gray)
                }
                .toggleStyle(SwissCheckboxStyle())
            }
            FeedbackDone(action: done)
        }
    }
}

/// Un son : la couleur de sa famille, son nom, la case de sa famille et de sa sorte (liste suisse ; blanche une fois
/// corrigée).
private struct FeedbackSoundRow: View {
    @ObservedObject var controller: OrganizerController
    let item: OrganizerItem
    @Binding var feedback: OrganizerFeedback
    @StateObject private var anchor = ScreenAnchor()

    private var family: SoundFamily { feedback.fixes[item.index]?.family ?? controller.families[item.index] ?? item.family }
    private var label: String {
        if let fix = feedback.fixes[item.index] { return fix.kind.map { "\(fix.family.label) · \($0.name)" } ?? fix.family.label }
        let current = controller.families[item.index] ?? item.family
        return controller.kind(of: item.index).map { "\(current.label) · \($0.name)" } ?? current.label
    }

    private func fix(_ family: SoundFamily, _ kind: SoundKind?) {
        feedback.fixes[item.index] = OrganizerFeedback.Fix(family: family, kind: kind)
        feedback.reasons.insert(.family)
    }

    private func open() {
        guard let frame = anchor.screenFrame else { return }
        var items: [RightClickMenu.Item?] = []
        for choice in SoundFamily.order {
            if choice.kinds.isEmpty {
                items.append(RightClickMenu.Item(title: choice.label, checked: family == choice) { fix(choice, nil) })
                continue
            }
            items.append(RightClickMenu.Item(title: choice.label, enabled: false, header: true) {})
            for kind in choice.kinds {
                let checked = feedback.fixes[item.index].map { $0.family == choice && $0.kind == kind } ?? false
                items.append(RightClickMenu.Item(title: kind.name, checked: checked) { fix(choice, kind) })
            }
        }
        SwissContextMenu.shared.showList(items, below: frame)
    }

    var body: some View {
        let fixed = feedback.fixes[item.index] != nil
        HStack(spacing: 10) {
            Rectangle().fill(swiftColor(controller.style(of: family).color)).frame(width: 12, height: 12)
            Text(item.name.isEmpty ? String(localized: "(sans nom)") : item.name)
                .font(.system(size: 13.5)).foregroundStyle(Swiss.text)
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 8)
            Button(action: open) {
                HStack {
                    Text(label).lineLimit(1)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                }
                .font(.system(size: 12.5, weight: fixed ? .bold : .regular))
                .foregroundStyle(fixed ? Swiss.background : Swiss.text)
                .padding(.horizontal, 10)
                .frame(width: 180, height: 30)
                .background(Rectangle().fill(fixed ? Swiss.text : Swiss.background))
                .overlay(Rectangle().strokeBorder(fixed ? Swiss.text : Swiss.keyLine, lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(ScreenAnchor.Reader(anchor: anchor))
        }
        .frame(minHeight: 46)
        .overlay(alignment: .bottom) { Rectangle().fill(Swiss.faint).frame(height: 1) }
    }
}

// MARK: - Le Mixer

private struct FeedbackMixerPage: View {
    @ObservedObject var controller: OrganizerController
    let changed: () -> Void
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            FeedbackHead(title: String(localized: "le mixer"),
                         sentence: String(localized: "Où commence chaque famille dans le Mixer ?"), back: done)
            VStack(spacing: 0) {
                ForEach(SoundFamily.order.filter { $0 != .unsure }, id: \.self) { family in
                    let style = controller.style(of: family)
                    HStack(spacing: 12) {
                        Rectangle().fill(swiftColor(style.color)).frame(width: 12, height: 12)
                        Text(family.label).swissLabel(Swiss.text, size: 12.5)
                        Spacer(minLength: 8)
                        Text("piste").font(.system(size: 11)).foregroundStyle(Swiss.gray)
                        MixerSlotBox(value: style.mixerStart, chosen: style.mixerStart != nil, last: controller.mixerLast,
                                     tint: swiftColor(style.color)) { start in
                            controller.setMixerStart(family, start)
                            changed()
                        }
                    }
                    .frame(minHeight: 46)
                    .overlay(alignment: .bottom) { Rectangle().fill(Swiss.faint).frame(height: 1) }
                }
            }
            .overlay(alignment: .top) { Rectangle().fill(Swiss.line).frame(height: 1) }
            VStack(spacing: 0) {
                switchRow(String(localized: "Un bus par famille"), Binding(get: { controller.options.buses }, set: {
                    controller.options.buses = $0
                    changed()
                }))
                switchRow(String(localized: "Pré-master avant le Master"), Binding(get: { controller.options.premaster }, set: {
                    controller.options.premaster = $0
                    changed()
                }))
                .disabled(!controller.options.buses)
            }
            Text("Tire la case vers le haut ou le bas, comme dans FL, ou clique pour écrire.")
                .font(.system(size: 11.5)).foregroundStyle(Swiss.gray)
            Spacer(minLength: 0)
            FeedbackDone(action: done)
        }
    }

    private func switchRow(_ title: String, _ on: Binding<Bool>) -> some View {
        HStack {
            Text(title).font(.system(size: 13.5)).foregroundStyle(Swiss.text)
            Spacer()
            SwissSwitch(isOn: on, label: title)
        }
        .frame(minHeight: 40)
        .overlay(alignment: .bottom) { Rectangle().fill(Swiss.faint).frame(height: 1) }
    }
}

// MARK: - La Playlist

private struct FeedbackPlaylistPage: View {
    @ObservedObject var controller: OrganizerController
    let changed: () -> Void
    let done: () -> Void
    @State private var dragging: SoundFamily?
    @State private var dragOffset: CGFloat = 0

    private static let rowHeight: CGFloat = 54
    private var order: [SoundFamily] { controller.options.familyOrder.filter { $0 != .unsure } }

    private func move(_ family: SoundFamily, by steps: Int) {
        var list = order
        guard let from = list.firstIndex(of: family), steps != 0 else { return }
        list.remove(at: from)
        list.insert(family, at: min(max(from + steps, 0), list.count))
        controller.setFamilyOrder(list)
        changed()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            FeedbackHead(title: String(localized: "la playlist"),
                         sentence: String(localized: "Range les familles dans l'ordre que tu veux, de haut en bas."), back: done)
            VStack(spacing: 6) {
                ForEach(Array(order.enumerated()), id: \.element) { index, family in
                    let lifted = dragging == family
                    HStack(spacing: 14) {
                        SixDots()
                        Text(verbatim: String(format: "%02d", index + 1)).font(.system(size: 11)).tracking(1.3)
                            .foregroundStyle(lifted ? Swiss.background : Swiss.gray)
                            .frame(width: 18, alignment: .leading)
                        Rectangle().fill(swiftColor(controller.style(of: family).color)).frame(width: 12, height: 12)
                        Text(family.label).swissLabel(lifted ? Swiss.background : Swiss.text, size: 12.5)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .frame(height: Self.rowHeight - 6)
                    .background(Rectangle().fill(lifted ? Swiss.text : Swiss.background))
                    .overlay(Rectangle().strokeBorder(lifted ? Color.clear : Swiss.line, lineWidth: 1))
                    .gumroadLift(lifted)
                    .offset(y: lifted ? dragOffset : 0)
                    .zIndex(lifted ? 1 : 0)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 2)
                        .onChanged { g in
                            dragging = family
                            dragOffset = g.translation.height
                        }
                        .onEnded { g in
                            move(family, by: Int((g.translation.height / Self.rowHeight).rounded()))
                            dragging = nil
                            dragOffset = 0
                        })
                }
            }
            Text("Le Channel rack et le Mixer suivent le même ordre.").font(.system(size: 11.5)).foregroundStyle(Swiss.gray)
            Spacer(minLength: 0)
            FeedbackDone(action: done)
        }
    }
}

// MARK: - Les couleurs

private struct FeedbackColorsPage: View {
    @ObservedObject var controller: OrganizerController
    let changed: () -> Void
    let done: () -> Void
    @State private var family: SoundFamily = .drums

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            FeedbackHead(title: String(localized: "les couleurs"),
                         sentence: String(localized: "Choisis la couleur de chaque famille."), back: done)
            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 0) {
                    ForEach(SoundFamily.order.filter { $0 != .unsure }, id: \.self) { choice in
                        let chosen = choice == family
                        Button { family = choice } label: {
                            HStack(spacing: 10) {
                                Rectangle().fill(swiftColor(controller.style(of: choice).color)).frame(width: 18, height: 18)
                                    .overlay(Rectangle().strokeBorder(Swiss.keyLine, lineWidth: 1))
                                Text(choice.label).swissLabel(chosen ? Swiss.background : Swiss.text, size: 11.5)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 46)
                            .background(Rectangle().fill(chosen ? Swiss.text : Swiss.background))
                            .overlay(alignment: .bottom) { Rectangle().fill(Swiss.faint).frame(height: 1) }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(width: 120)
                .overlay(alignment: .top) { Rectangle().fill(Swiss.line).frame(height: 1) }
                FLColorSelector(initial: controller.style(of: family).color) { picked in
                    controller.setBaseColor(family, picked)
                    changed()
                }
                .id(family)
            }
            Spacer(minLength: 0)
            FeedbackDone(action: done)
        }
    }
}
