// Style « Liquid Glass » : verre natif sur macOS 26 (SDK Xcode 26, Swift 6.2), repli en matériau translucide
// sur macOS 13–15 ou avec un compilateur plus ancien. Audit 05 : touches affichées avec leur nom en clair.
import SwiftUI

extension View {
    /// Carte en verre (arrondie).
    @ViewBuilder
    func glassCard(cornerRadius: CGFloat = 18) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            self.fallbackGlass(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        #else
        self.fallbackGlass(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        #endif
    }

    /// Pastille en verre (capsule).
    @ViewBuilder
    func glassCapsule() -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: Capsule())
        } else {
            self.fallbackGlass(Capsule())
        }
        #else
        self.fallbackGlass(Capsule())
        #endif
    }

    /// Bouton principal (accent) : verre teinté sur macOS 26, bouton accentué ailleurs.
    @ViewBuilder
    func primaryGlassButton() -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
        }
        #else
        self.buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
        #endif
    }

    /// Bouton secondaire en verre.
    @ViewBuilder
    func secondaryGlassButton() -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered).buttonBorderShape(.capsule)
        }
        #else
        self.buttonStyle(.bordered).buttonBorderShape(.capsule)
        #endif
    }

    private func fallbackGlass<S: InsettableShape>(_ shape: S) -> some View {
        self
            .background(.ultraThinMaterial, in: shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0.35), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
    }
}

/// Une touche de clavier : symbole + nom en clair (« ⌃ ctrl »), comme dans la simulation validée.
struct KeyCap: View {
    let symbol: String
    var name: String? = nil
    var large = false

    var body: some View {
        VStack(spacing: 2) {
            Text(symbol)
                .font(.system(size: large ? 17 : 13, weight: .semibold, design: .rounded))
            if large, let name {
                Text(name)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: large ? 44 : 26, minHeight: large ? 46 : 26)
        .padding(.horizontal, large ? 8 : 6)
        .background(
            RoundedRectangle(cornerRadius: large ? 10 : 7, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.85))
                .shadow(color: .black.opacity(0.12), radius: 0, y: 1.5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: large ? 10 : 7, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
        )
        .accessibilityHidden(true)
    }
}

extension KeyCombo {
    /// Touches à dessiner, dans l'ordre macOS (⌃ ⌥ ⇧ ⌘ puis la touche).
    var caps: [(symbol: String, name: String)] {
        var out: [(symbol: String, name: String)] = []
        if control { out.append((symbol: "⌃", name: "ctrl")) }
        if option { out.append((symbol: "⌥", name: "option")) }
        if shift { out.append((symbol: "⇧", name: "maj")) }
        if command { out.append((symbol: "⌘", name: "cmd")) }
        out.append((symbol: KeyNames.name(for: keyCode), name: ""))
        return out
    }

    /// Texte lu par VoiceOver : « contrôle option R ».
    var spoken: String {
        var parts: [String] = []
        if control { parts.append("contrôle") }
        if option { parts.append("option") }
        if shift { parts.append("majuscule") }
        if command { parts.append("commande") }
        parts.append(KeyNames.name(for: keyCode))
        return parts.joined(separator: " ")
    }
}

/// Rangée de touches.
struct KeyCaps: View {
    let combo: KeyCombo?
    var large = false
    var placeholder = "—"

    var body: some View {
        HStack(spacing: large ? 6 : 4) {
            if let combo {
                ForEach(Array(combo.caps.enumerated()), id: \.offset) { _, cap in
                    KeyCap(symbol: cap.symbol, name: cap.name.isEmpty ? nil : cap.name, large: large)
                }
            } else {
                Text(placeholder).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(combo?.spoken ?? "Aucun raccourci")
    }
}

/// Description courte de chaque action (retours des tests utilisateurs : dire ce que fait l'action).
extension FLActionInfo {
    var detail: String {
        switch key {
        case "play": return "Lance ou met en pause la lecture"
        case "stop": return "Arrête la lecture"
        case "rec": return "Démarre ou arrête l'enregistrement"
        case "metro": return "Active ou coupe le métronome"
        case "count": return "Décompte avant l'enregistrement"
        case "loop": return "Enchaîne les prises sur la boucle"
        case "wait": return "Le REC démarre à la première note jouée"
        case "marker": return "Repère « bonne prise » à la position de lecture"
        case "arm": return "Prépare la piste du Mixer sélectionnée à enregistrer"
        case "tap": return "Tape le tempo en rythme"
        case "newpat": return "Crée un pattern vide et ouvre le Piano Roll"
        case "clone": return "Duplique le pattern en cours pour une variation"
        case "pnext": return "Passe au pattern suivant"
        case "pprev": return "Revient au pattern précédent"
        case "chnext": return "Instrument suivant, sans quitter le Piano Roll"
        case "chprev": return "Instrument précédent, sans quitter le Piano Roll"
        case "snap": return "Change le magnétisme : 1/4, 1/8, triolets…"
        case "quant": return "Aligne les notes de l'instrument sélectionné"
        case "presetnext": return "Preset suivant du plugin ouvert"
        case "presetprev": return "Preset précédent du plugin ouvert"
        case "mute": return "Coupe la piste du Mixer sélectionnée"
        case "solo": return "Écoute seulement la piste sélectionnée"
        case "unsolo": return "Réécoute tout le morceau"
        case "bypass": return "Compare la piste avec et sans effets"
        case "mono": return "Vérifie que le mix tient en mono"
        case "trnext": return "Sélectionne la piste suivante du Mixer"
        case "trprev": return "Sélectionne la piste précédente du Mixer"
        case "volup": return "Monte la piste sélectionnée"
        case "voldn": return "Baisse la piste sélectionnée"
        case "pl": return "Affiche la Playlist"
        case "cr": return "Affiche le Channel Rack"
        case "pr": return "Affiche le Piano Roll"
        case "mx": return "Affiche le Mixer"
        case "br": return "Affiche le Browser"
        case "plmx": return "Bascule entre la Playlist et le Mixer"
        case "undo": return "Annule la dernière action"
        case "redo": return "Rétablit l'action annulée"
        case "save": return "Sauvegarde le projet"
        default: return label
        }
    }
}
