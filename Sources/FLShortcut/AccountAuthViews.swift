// Pages du compte (maquette « Mon compte — connexion et profil » validée le 30/10) : une carte au centre pour se
// connecter, créer son compte ou entrer le code reçu par mail ; des champs bien lisibles, un œil pour voir le mot de
// passe, les règles du mot de passe qui passent au vert une par une, le pseudo vérifié en direct (« Libre ✓ »), le code
// en 6 cases. Utilisées par Mon compte et par la Communauté (CommunitySignIn).
import SwiftUI

// MARK: - Couleurs et carte

/// Couleurs de la maquette (HTML du 30/10, fond sombre) ; en mode clair, les mêmes en gris légers.
enum AuthLook {
    /// Fond creusé des champs, des onglets, des cases du code et des cases de la sauvegarde.
    static func well(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.black.opacity(0.28) : Color.primary.opacity(0.05)
    }
    static let wellStroke = Color.primary.opacity(0.12)
    static let blue = Color(red: 0.04, green: 0.52, blue: 1)                     // #0a84ff
    static let teal = [Color(red: 0.24, green: 0.85, blue: 0.79), Color(red: 0.12, green: 0.65, blue: 0.59)]
    static let sky = [Color(red: 0.35, green: 0.78, blue: 0.98), blue]
}

/// Carte centrée des pages du compte : coins arrondis, fond un peu plus clair que la page, fin contour.
struct AuthCard<Content: View>: View {
    var spacing: CGFloat = 18
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: spacing) { content() }
            .padding(.horizontal, 30)
            .padding(.vertical, 28)
            .frame(width: 420)
            .background(MockPlate(cornerRadius: 18))
    }
}

/// Pastille ronde en tête de carte (compte : personnage ; code : enveloppe).
struct AuthBadge: View {
    let symbol: String
    let colors: [Color]
    var size: CGFloat = 64

    var body: some View {
        Circle()
            .fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
            .overlay(Image(systemName: symbol).font(.system(size: size * 0.42, weight: .medium)).foregroundStyle(.white))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// Petite pastille d'un avantage (« Sauvegarde », « Tous tes Mac », « Communauté »).
struct AuthPill: View {
    let symbol: String
    let text: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(tint)
            Text(text).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(Capsule().fill(Color.primary.opacity(0.07)))
    }
}

/// Onglets « Se connecter » / « Créer un compte » : le fond de l'onglet choisi glisse de l'un à l'autre, et la carte
/// change de forme dans le même mouvement (vidéo du 30/10 : « plus fluide »).
struct AuthTabs: View {
    @Binding var creating: Bool
    @Environment(\.colorScheme) private var scheme
    @Namespace private var tabs

    /// Le mouvement de la carte quand on change d'onglet.
    static let change = Animation.spring(response: 0.42, dampingFraction: 0.9)

    var body: some View {
        HStack(spacing: 0) {
            tab(String(localized: "Se connecter"), selected: !creating) { choose(false) }
            tab(String(localized: "Créer un compte"), selected: creating) { choose(true) }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AuthLook.well(scheme)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }

    private func tab(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(selected ? Color.primary : Color.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color.primary.opacity(0.14))
                            .matchedGeometryEffect(id: "onglet", in: tabs)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private func choose(_ value: Bool) {
        guard value != creating else { return }
        if Motion.reduce { creating = value } else { withAnimation(Self.change) { creating = value } }
    }
}

/// Pastilles posées à la suite, sur plusieurs lignes s'il le faut, jamais coupées au milieu d'un mot (capture du
/// 30/10 : « 8 caractèr / es », « Minuscul / e »).
struct FlowRow: Layout {
    var spacing: CGFloat = 12
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                y += line + lineSpacing
                x = 0
                line = 0
            }
            widest = max(widest, x + size.width)
            x += size.width + spacing
            line = max(line, size.height)
        }
        return CGSize(width: proposal.width ?? widest, height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += line + lineSpacing
                x = bounds.minX
                line = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            line = max(line, size.height)
        }
    }
}

// MARK: - Champs

/// Champ d'une page du compte : titre au-dessus (lien facultatif à droite), zone haute et lisible, préfixe « @ »,
/// mot de passe avec un œil pour le voir, état à droite (« Libre ✓ »).
struct AuthField<Accessory: View>: View {
    let title: String
    @Binding var text: String
    var prompt: String = ""
    var prefix: String? = nil
    var secure = false
    var link: (title: String, action: () -> Void)? = nil
    @ViewBuilder var accessory: () -> Accessory
    @State private var revealed = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                if let link {
                    Button(link.title, action: link.action)
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(red: 0.29, green: 0.64, blue: 1))          // #4AA3FF
                }
            }
            HStack(spacing: 8) {
                if let prefix {
                    Text(prefix).font(.system(size: 14)).foregroundStyle(.secondary)
                }
                Group {
                    if secure && !revealed {
                        SecureField("", text: $text, prompt: Text(prompt))
                    } else {
                        TextField("", text: $text, prompt: Text(prompt))
                    }
                }
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                accessory()
                if secure {
                    Button { revealed.toggle() } label: {
                        Image(systemName: revealed ? "eye.slash" : "eye")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(revealed ? String(localized: "Cacher le mot de passe") : String(localized: "Voir le mot de passe"))
                    .accessibilityLabel(revealed ? String(localized: "Cacher le mot de passe") : String(localized: "Voir le mot de passe"))
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(AuthLook.well(scheme)))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(AuthLook.wellStroke))
        }
    }
}

extension AuthField where Accessory == EmptyView {
    init(title: String, text: Binding<String>, prompt: String = "", prefix: String? = nil, secure: Bool = false,
         link: (title: String, action: () -> Void)? = nil) {
        self.init(title: title, text: text, prompt: prompt, prefix: prefix, secure: secure, link: link) { EmptyView() }
    }
}

/// État du pseudo à droite de son champ : « Libre ✓ », « Déjà pris », « Ton pseudo », vérification…
struct UsernameStatus: View {
    let check: CommunityStore.NameCheck

    var body: some View {
        switch check {
        case .empty, .unknown:
            EmptyView()
        case .checking:
            ProgressView().controlSize(.small)
        case .free:
            Label(String(localized: "Libre"), systemImage: "checkmark").foregroundStyle(.green).modifier(StatusFont())
        case .mine:
            Label(String(localized: "Ton pseudo"), systemImage: "checkmark").foregroundStyle(.secondary).modifier(StatusFont())
        case .taken:
            Label(String(localized: "Déjà pris"), systemImage: "xmark").foregroundStyle(.red).modifier(StatusFont())
        case .invalid:
            Image(systemName: "exclamationmark.circle").foregroundStyle(.orange).font(.system(size: 13, weight: .semibold))
        }
    }

    private struct StatusFont: ViewModifier {
        func body(content: Content) -> some View {
            content.font(.system(size: 12, weight: .semibold)).labelStyle(.titleAndIcon).fixedSize()
        }
    }
}

/// Pseudo vérifié au fil de la frappe (0,4 s après la dernière lettre) : format, puis libre ou pris.
struct UsernameChecker: ViewModifier {
    let community: CommunityStore
    let name: String
    @Binding var check: CommunityStore.NameCheck
    @State private var task: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onChange(of: name) { _ in run() }
            .onAppear { run() }
    }

    private func run() {
        task?.cancel()
        let typed = name
        task = Task { @MainActor in
            let trimmed = typed.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || CommunityRules.usernameProblem(trimmed) != nil {
                check = await community.checkUsername(typed)
                return
            }
            check = .checking
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            let result = await community.checkUsername(typed)
            guard !Task.isCancelled else { return }
            check = result
        }
    }
}

/// Règles du mot de passe, en pastilles qui passent au vert une par une.
struct PasswordRules: View {
    let password: String

    var body: some View {
        let missing = Set(CommunityRules.passwordMissing(password).map(Self.key))
        FlowRow(spacing: 12, lineSpacing: 6) {
            ForEach(Self.rules, id: \.key) { rule in
                let ok = !password.isEmpty && !missing.contains(rule.key)
                HStack(spacing: 4) {
                    Image(systemName: ok ? "checkmark" : "circle")
                        .font(.system(size: ok ? 10 : 8, weight: .bold))
                    Text(rule.title)
                }
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(ok ? Color.green : Color.secondary)
                .fixedSize()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// Même ordre et mêmes exigences que CommunityRules.passwordMissing.
    private static let rules: [(key: String, title: String)] = [
        ("length", String(localized: "8 caractères")),
        ("lower", String(localized: "Minuscule")),
        ("upper", String(localized: "Majuscule")),
        ("digit", String(localized: "Chiffre")),
        ("symbol", String(localized: "Symbole")),
    ]

    /// Ce qui manque (texte de CommunityRules) → la règle concernée.
    private static func key(_ missing: String) -> String {
        let sets = CommunityRules.passwordSets.map(\.name)
        switch missing {
        case sets[0]: return "lower"
        case sets[1]: return "upper"
        case sets[2]: return "digit"
        case sets[3]: return "symbol"
        default: return "length"
        }
    }
}

/// Code reçu par mail en cases (6, ou plus si le serveur en envoie plus) : on tape ou on colle, les chiffres
/// remplissent les cases, la case suivante s'allume.
struct CodeBoxes: View {
    @Binding var code: String
    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var scheme

    private var digits: [Character] { Array(code.filter(\.isNumber).prefix(10)) }

    var body: some View {
        let count = max(6, digits.count)
        ZStack {
            TextField("", text: $code)
                .textContentType(.oneTimeCode)
                .focused($focused)
                .opacity(0.02)
                .frame(width: 1, height: 1)
                .onChange(of: code) { new in
                    let kept = String(new.filter(\.isNumber).prefix(10))
                    if kept != new { code = kept }
                }
                .accessibilityLabel(String(localized: "Code reçu par mail"))
            HStack(spacing: count > 6 ? 5 : 8) {
                ForEach(0..<count, id: \.self) { i in
                    let current = focused && i == min(digits.count, count - 1)
                    Text(i < digits.count ? String(digits[i]) : "")
                        .font(.system(size: 24, weight: .bold))
                        .frame(width: count > 6 ? 36 : 46, height: 56)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AuthLook.well(scheme)))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(current ? AuthLook.blue : Color.primary.opacity(0.14), lineWidth: current ? 2 : 1))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { focused = true }
            .accessibilityHidden(true)
        }
        .onAppear { focused = true }
    }
}

// MARK: - Boutons

/// Grand bouton bleu de la carte (« Se connecter », « Créer mon compte », « Valider »).
struct AuthPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(Capsule().fill(AuthLook.blue.opacity(configuration.isPressed ? 0.8 : 1)))
            .opacity(isEnabled ? 1 : 0.55)
            .contentShape(Capsule())
    }
}

/// Lien de la carte (« Renvoyer le code », « Changer d'adresse »).
struct AuthLinkButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(Color(red: 0.29, green: 0.64, blue: 1))                  // #4AA3FF
    }
}
