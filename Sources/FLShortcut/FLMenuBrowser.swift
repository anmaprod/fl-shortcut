// « Menu de FL » dans la palette : les menus de FL parcourus comme dans FL. On choisit un menu de la barre (File,
// Edit, Tools…), puis ce qu'il contient, sous-menu après sous-menu (File › Export › …), jusqu'à l'élément que la
// macro choisira. Lu dans la barre des menus de macOS (Accessibilité, FL 2024.2 et plus), sans clic ; un menu que FL
// ne remplit qu'à son ouverture est ouvert le temps de le lire, puis refermé. Les titres ne sont jamais journalisés.
import ApplicationServices
import SwiftUI

/// Pur (testé) : où mène un élément touché.
enum FLMenuNav {
    enum Step: Equatable {
        /// Sous-menu : ses éléments sont montrés.
        case open([String])
        /// Élément choisi : le chemin du bloc.
        case choose([String])
        /// Sous-menu trop profond pour être rejoué.
        case none
    }

    /// Un sous-menu s'ouvre tant que ses éléments restent rejouables (`MenuBarAX.maxDepth` titres au plus) ; un
    /// élément est choisi dès qu'il est sous un menu de la barre. Un élément grisé se choisit aussi : FL en grise
    /// selon le moment (Coller…), il peut être actif quand la macro tourne.
    static func step(path: [String], entry: MenuBarAX.Entry) -> Step {
        let next = path + [entry.title]
        if entry.submenu { return next.count < MenuBarAX.maxDepth ? .open(next) : .none }
        return next.count >= 2 ? .choose(next) : .none
    }

    /// Niveau montré d'abord : celui de l'élément déjà choisi (avec ses voisins), sinon les menus de la barre.
    static func start(for titles: [String]) -> [String] {
        titles.count >= 2 ? Array(titles.dropLast()) : []
    }
}

/// Un niveau des menus de FL à la fois, lu hors du fil principal ; les niveaux déjà lus reviennent tout de suite.
/// Rien n'est ouvert dans FL sans un clic de l'utilisateur (signalé : le menu Tools s'ouvrait tout seul).
final class FLMenuBrowser: ObservableObject {
    enum State: Equatable {
        case loading
        case loaded([MenuBarAX.Entry])
        /// FL ne remplit ce menu qu'à son ouverture : bouton « Lire ce menu dans FL ».
        case needsOpening
        case unavailable(String)
    }

    @Published private(set) var path: [String] = []
    @Published private(set) var state: State = .loading

    /// Partagé par tous les blocs (thread principal) ; vidé par « Relire ».
    private static var cache: [[String]: [MenuBarAX.Entry]] = [:]
    /// Une lecture à la fois (une lecture demandée ouvre et referme un menu de FL).
    private static let queue = DispatchQueue(label: "fl-menu-browser", qos: .userInitiated)
    private var generation = 0

    /// `open` : seulement sur un clic de l'utilisateur. `fallBack` : un chemin introuvable (bloc enregistré pour un
    /// autre FL) montre le niveau au-dessus qui existe.
    func show(_ path: [String], reload: Bool = false, open: Bool = false, fallBack: Bool = false) {
        self.path = path
        generation += 1
        if reload { Self.cache = [:] }
        if !open, let cached = Self.cache[path] {
            state = .loaded(cached)
            return
        }
        guard AXIsProcessTrusted() else {
            state = .unavailable("Autorise l'Accessibilité à FL Shortcuts pour parcourir les menus de FL.")
            return
        }
        guard let pid = OrganizerEnvironment.flPID() else {
            state = .unavailable("Ouvre FL Studio pour parcourir ses menus.")
            return
        }
        state = .loading
        let ticket = generation
        Self.queue.async {
            var shown = path
            var read = MenuBarAX.level(pid: pid, under: shown, open: open)
            while fallBack, read == .missing, !shown.isEmpty {
                shown.removeLast()
                read = MenuBarAX.level(pid: pid, under: shown)
            }
            DispatchQueue.main.async {
                guard ticket == self.generation else { return }
                self.path = shown
                switch read {
                case .entries(let entries):
                    Self.cache[shown] = entries
                    self.state = .loaded(entries)
                case .needsOpening:
                    self.state = .needsOpening
                case .missing:
                    self.state = .unavailable(shown.isEmpty
                        ? "Menus de FL introuvables dans la barre des menus de macOS (FL Studio 2024.2 ou plus récent)."
                        : "Ce menu est vide, ou FL l'a changé : reviens en arrière, ou relis les menus.")
                }
            }
        }
    }
}

/// Réglage du bloc « Menu de FL » : l'élément choisi, puis les menus de FL à parcourir.
struct MenuBarField: View {
    let titles: [String]
    let set: ([String]) -> Void
    @StateObject private var browser = FLMenuBrowser()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            chosen
            Divider()
            navigation
            content
        }
        .onAppear { browser.show(FLMenuNav.start(for: titles), fallBack: true) }
    }

    private var chosen: some View {
        Group {
            if titles.count >= 2 {
                Label(titles.map { $0.displaySafe(max: 40) }.joined(separator: " › "), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Color.green)
            } else {
                Label("Choisis un menu de FL, puis ce qu'il contient, jusqu'à l'élément voulu.",
                      systemImage: "hand.point.down")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 12, weight: .medium))
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Titre du niveau précédent (bouton retour) ; nil sur les menus de la barre.
    private var backTitle: String? {
        guard !browser.path.isEmpty else { return nil }
        return browser.path.count > 1 ? browser.path[browser.path.count - 2] : "Menus de FL"
    }

    private var navigation: some View {
        HStack(spacing: 8) {
            if let parent = backTitle {
                Button {
                    browser.show(Array(browser.path.dropLast()))
                } label: {
                    Label(parent.displaySafe(max: 24), systemImage: "chevron.left")
                        .lineLimit(1)
                }
                .buttonStyle(.borderless)
                .help("Revenir au menu précédent")
            }
            Text(browser.path.last.map { $0.displaySafe(max: 40) } ?? "Menus de FL")
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: browser.path.isEmpty ? .leading : .trailing)
            Button { browser.show(browser.path, reload: true) } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
                .help("Relire les menus dans FL")
        }
        .font(.system(size: 12))
    }

    @ViewBuilder private var content: some View {
        switch browser.state {
        case .loading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Lecture du menu dans FL…").foregroundStyle(.secondary)
            }
            .font(.system(size: 12))
        case .needsOpening:
            VStack(alignment: .leading, spacing: 6) {
                Text("FL ne remplit ce menu qu'en l'ouvrant.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Lire ce menu dans FL") { browser.show(browser.path, open: true) }
                    .help("Le menu s'ouvre un instant dans FL, le temps de le lire, puis se referme")
            }
        case .unavailable(let why):
            Text(why)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        case .loaded(let entries):
            VStack(spacing: 0) {
                ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                    MenuEntryRow(entry: entry, step: FLMenuNav.step(path: browser.path, entry: entry),
                                 selected: browser.path + [entry.title] == titles) { step in
                        switch step {
                        case .open(let next): browser.show(next)
                        case .choose(let path): set(path)
                        case .none: break
                        }
                    }
                }
            }
            .padding(4)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.04)))
        }
    }
}

/// Une ligne, comme dans un menu : titre, flèche d'un sous-menu, coche de l'élément choisi.
private struct MenuEntryRow: View {
    let entry: MenuBarAX.Entry
    let step: FLMenuNav.Step
    let selected: Bool
    let action: (FLMenuNav.Step) -> Void
    @State private var hovering = false

    var body: some View {
        Button { action(step) } label: {
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .opacity(selected ? 1 : 0)
                Text(entry.title.displaySafe(max: 60))
                    .lineLimit(1)
                    .foregroundStyle(entry.enabled && step != .none ? Color.primary : Color.secondary)
                Spacer(minLength: 4)
                if entry.submenu {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 12))
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(hovering && step != .none ? Color.accentColor.opacity(0.18) : Color.clear))
        }
        .buttonStyle(.plain)
        .disabled(step == .none)
        .onHover { hovering = $0 }
        .help(step == .none ? "Trop profond pour être rejoué par la macro" : entry.enabled ? "" : "Grisé dans FL en ce moment")
        .accessibilityLabel(entry.submenu ? "\(entry.title), sous-menu" : entry.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
