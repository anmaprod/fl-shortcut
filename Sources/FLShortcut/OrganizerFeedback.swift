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
    /// Aider l'IA de tout le monde avec ces corrections (des nombres seulement).
    var share = false

    var asksSounds: Bool { reasons.contains { $0.aboutSounds } }
    private var text: String { other ? otherText.trimmingCharacters(in: .whitespacesAndNewlines) : "" }
    var canSend: Bool { !reasons.isEmpty || !text.isEmpty }

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

/// « Pas content ? » : ce qui n'allait pas (cases), « Autre » en bas, puis la bonne réponse des sons mal rangés.
struct OrganizerFeedbackView: View {
    @ObservedObject var controller: OrganizerController
    @State private var feedback = OrganizerFeedback()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Qu'est-ce qui n'allait pas ?").font(.system(size: 15, weight: .semibold))
            Text("Coche tout ce qui ne va pas : l'IA apprend de ses erreurs.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(OrganizerFeedback.Reason.allCases) { reason in
                        Toggle(reason.label, isOn: checked(reason)).toggleStyle(.checkbox)
                    }
                    Toggle("Autre", isOn: $feedback.other).toggleStyle(.checkbox)
                    if feedback.other {
                        TextField("Dis-nous ce qui ne va pas", text: $feedback.otherText, axis: .vertical)
                            .lineLimit(3...6)
                            .textFieldStyle(.roundedBorder)
                    }
                    if feedback.asksSounds { sounds }
                    if feedback.teamMessage() != nil {
                        Text(String(localized: """
                            Ces réponses partent à l'équipe de FL Shortcuts avec le diagnostic (des nombres, aucun nom \
                            de son).
                            """))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Spacer()
                Button("Annuler") { controller.feedbackShown = false }.keyboardShortcut(.cancelAction)
                Button("Envoyer") { controller.submitFeedback(feedback) }
                    .primaryButton()
                    .keyboardShortcut(.defaultAction)
                    .disabled(!feedback.canSend)
            }
        }
        .padding(18)
        .frame(width: 460, height: 520)
        .onAppear { feedback.share = controller.sharingCorrections }
    }

    private func checked(_ reason: OrganizerFeedback.Reason) -> Binding<Bool> {
        Binding(get: { feedback.reasons.contains(reason) },
                set: { on in
                    if on { feedback.reasons.insert(reason) } else { feedback.reasons.remove(reason) }
                })
    }

    /// Tous les sons : pour chacun mal rangé, sa bonne famille ou sorte (mêmes choix que l'aperçu).
    private var sounds: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Quels sons étaient mal rangés ?").font(.system(size: 13, weight: .semibold)).padding(.top, 6)
            VStack(spacing: 0) {
                ForEach(Array(controller.correctable.enumerated()), id: \.element.index) { number, item in
                    if number > 0 { Divider() }
                    row(item).padding(.vertical, 5)
                }
            }
            .padding(.horizontal, 10)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
            Text("Un son rangé d'après son nom : ta réponse est retenue pour ce nom, sur ce Mac.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if feedback.fixes.keys.contains(where: { index in
                controller.correctable.contains { $0.index == index && $0.soundPrint != nil }
            }) {
                Toggle(isOn: $feedback.share) {
                    Text(String(localized: """
                        Aider l'IA de tout le monde : envoyer des nombres qui décrivent ces sons (jamais le son, son \
                        nom ni ce que tu écris)
                        """))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .toggleStyle(.checkbox)
                .padding(.top, 4)
            }
        }
    }

    private func fix(_ item: OrganizerItem, _ family: SoundFamily, _ kind: SoundKind?) {
        feedback.fixes[item.index] = OrganizerFeedback.Fix(family: family, kind: kind)
    }

    private func row(_ item: OrganizerItem) -> some View {
        let chosen = feedback.fixes[item.index]
        let family = controller.families[item.index] ?? item.family
        let label = chosen.map { $0.kind?.name ?? $0.family.label }
            ?? controller.kind(of: item.index)?.name ?? family.label
        return HStack(spacing: 8) {
            Circle().fill(swiftColor(controller.style(of: family).color)).frame(width: 8, height: 8)
            Text(item.name.isEmpty ? String(localized: "(sans nom)") : item.name).lineLimit(1).truncationMode(.middle)
            Spacer()
            Menu {
                ForEach(SoundFamily.order, id: \.self) { choice in
                    if choice.kinds.isEmpty {
                        Button(choice.label) { fix(item, choice, nil) }
                    } else {
                        Menu(choice.label) {
                            Button(choice.label) { fix(item, choice, nil) }
                            Divider()
                            ForEach(choice.kinds, id: \.self) { kind in
                                Button(kind.name) { fix(item, choice, kind) }
                            }
                        }
                    }
                }
            } label: {
                Text(label).font(.system(size: 11))
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .fixedSize()
            .help("Ce qu'est vraiment ce son")
            Image(systemName: chosen == nil ? "circle" : "checkmark.circle.fill")
                .foregroundStyle(chosen == nil ? Color.secondary : Color.green)
        }
        .font(.system(size: 12))
    }
}
