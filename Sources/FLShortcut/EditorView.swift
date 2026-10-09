// Interface minimale (la version « Liquid Glass » sera refaite ensuite).
// Audit : REL-06 / PROTOCOL.md §5 (statut du lien affiché), audit 04 §8.2 (actions grisées selon le masque de
//         capacités ou la version de FL, « Disponible à partir de FL X »), audit 05 §4.2-4.4 (conflits macOS /
//         FL, avertissement touche seule avec confirmation, pause visible, libellés d'accessibilité),
//         REL-19 (un seul enregistreur actif, ⌫ efface, Échap annule, ⌃⌥⌘F refusé, délai de 5 s, arrêt quand la
//         fenêtre perd le focus, tap suspendu pendant l'enregistrement), REL-20 (avertissements issus de
//         l'analyse qui construit l'index), REL-21 (remplacement de profil confirmé et annulable),
//         SEC-05 (cibles interdites refusées à la saisie ; import validé avec récapitulatif et confirmation).
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct EditorView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var status: AppStatus
    @EnvironmentObject var link: MIDILink
    @EnvironmentObject var fl: FLMonitor
    @StateObject private var recorder = Recorder.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            banners

            HStack {
                Text("Raccourci").frame(width: 170, alignment: .leading)
                Text("Où").frame(width: 120, alignment: .leading)
                Text("Fait…").frame(width: 150, alignment: .leading)
                Text("Action")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
            .padding(.top, 10)

            List {
                ForEach($store.remaps) { $remap in
                    RemapRow(remap: $remap, issues: store.issues(for: remap.id)) {
                        let id = remap.id
                        DispatchQueue.main.async { store.delete(id) }
                    }
                }
            }

            if let hint = recorder.hint {
                Text(hint).font(.caption).foregroundStyle(.orange).padding(.horizontal, 12)
            }

            Divider()
            footer.padding(12)
        }
    }

    @ViewBuilder private var banners: some View {
        if !store.enabled {
            Banner(symbol: "pause.circle.fill", color: .orange,
                   text: "FL Shortcut est en pause : aucun raccourci n'est actif. ⌃⌥⌘F pour reprendre.") {
                Button("Reprendre") { store.enabled = true }
            }
        }
        if !status.accessibilityOK {
            Banner(symbol: "exclamationmark.triangle.fill", color: .orange,
                   text: "FL Shortcut a besoin de l'autorisation Accessibilité pour lire le clavier.") {
                Button("Ouvrir les réglages") { status.openAccessibilitySettings() }
            }
        }
        if status.secureInput {
            Banner(symbol: "lock.fill", color: .orange,
                   text: "Saisie sécurisée activée par une autre appli (ex. Terminal) : macOS ne transmet plus les touches.") {
                EmptyView()
            }
        }
        Banner(symbol: linkSymbol, color: linkColor, text: linkText) {
            Button("Tester") { link.testLink() }
        }
        if let error = store.saveError {
            Banner(symbol: "xmark.octagon.fill", color: .red, text: error) { EmptyView() }
        }
        if let warning = store.loadWarning {
            Banner(symbol: "info.circle.fill", color: .blue, text: warning) {
                Button("OK") { store.loadWarning = nil }
            }
        }
    }

    private var linkSymbol: String {
        switch link.status {
        case .linked: return "checkmark.circle.fill"
        case .inactive: return "exclamationmark.circle.fill"
        case .flClosed: return "moon.zzz.fill"
        }
    }

    private var linkColor: Color {
        switch link.status {
        case .linked: return .green
        case .inactive: return .orange
        case .flClosed: return .secondary
        }
    }

    private var linkText: String {
        let version = fl.version.map { " (FL \($0))" } ?? ""
        switch link.status {
        case .linked:
            let api = link.snapshot.hello.map { " · API \($0.apiVersion)" } ?? ""
            return "Relié à FL Studio\(version)\(api)."
        case .inactive:
            if !link.snapshot.hasKey { return "Lien inactif\(version) : installe le script depuis le menu, puis redémarre FL." }
            if let p = link.snapshot.incompatibleProtocol {
                return "Lien inactif\(version) : script FL incompatible (protocole \(p)). Réinstalle-le."
            }
            return "Lien inactif\(version) : vérifie dans FL › MIDI Settings l'entrée ET la sortie « FL Shortcut » "
                + "(même numéro de port). Les « Actions dans FL » laissent passer la touche en attendant."
        case .flClosed:
            return "FL fermé\(version)."
        }
    }

    private var footer: some View {
        HStack {
            Button { store.add() } label: { Label("Ajouter un raccourci", systemImage: "plus") }
            Menu("Profil") {
                ForEach(ProfilePreset.allCases) { preset in
                    Button(preset.label) {
                        if Dialogs.confirm("Charger le profil « \(preset.label) » ?",
                                           preset.summary + "\n\nTes raccourcis actuels seront remplacés (annulable).") {
                            store.apply(preset: preset)
                        }
                    }
                }
                if store.undoSnapshot != nil {
                    Divider()
                    Button("Annuler le dernier remplacement") { store.undoReplace() }
                }
            }
            .fixedSize()
            Button("Importer…") { importProfile() }
            Button("Exporter…") { exportProfile() }
            Spacer()
            Text("Actifs seulement quand FL Studio reçoit le clavier · ⌃⌥⌘F pour mettre en pause")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func importProfile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            guard let data = try SecureFile.read(url.resolvingSymlinksInPath(), maxBytes: ProfileImporter.maxBytes) else { return }
            let preview = try store.prepareImport(data)
            var lines = Array(preview.summary.prefix(25))
            if preview.summary.count > 25 { lines.append("… et \(preview.summary.count - 25) autre(s)") }
            if !preview.rejected.isEmpty {
                lines.append("")
                lines.append("Refusé :")
                lines += preview.rejected.prefix(15)
            }
            if Dialogs.confirm("Importer \(preview.remaps.count) raccourci(s) ?",
                               lines.joined(separator: "\n") + "\n\nTes raccourcis actuels seront remplacés (annulable).") {
                store.applyImport(preview)
            }
        } catch {
            Dialogs.inform("Import impossible", error.localizedDescription)
        }
    }

    private func exportProfile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Profil FL Shortcut.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.exportData().write(to: url, options: .atomic)
        } catch {
            Dialogs.inform("Export impossible", error.localizedDescription)
        }
    }
}

struct Banner<Accessory: View>: View {
    let symbol: String
    let color: Color
    let text: String
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack {
            Image(systemName: symbol).foregroundStyle(color)
            Text(text).fixedSize(horizontal: false, vertical: true)
            Spacer()
            accessory()
        }
        .padding(10)
        .background(color.opacity(0.12))
        .accessibilityElement(children: .combine)
    }
}

struct RemapRow: View {
    @Binding var remap: Remap
    var issues: [ShortcutIssue]
    var onDelete: () -> Void
    @EnvironmentObject var status: AppStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 10) {
                Toggle("", isOn: $remap.enabled)
                    .labelsHidden()
                    .accessibilityLabel("Activer ce raccourci")
                ShortcutField(id: "\(remap.id)-trigger", role: .trigger, combo: $remap.trigger)
                    .frame(width: 140)
                Picker("", selection: $remap.context) {
                    ForEach(ShortcutContext.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .frame(width: 120)
                .accessibilityLabel("Fenêtre FL")
                Picker("", selection: kindBinding) {
                    Text("Action dans FL").tag(Remap.Kind.flAction)
                    Text("Touche de FL").tag(Remap.Kind.keystroke)
                }
                .labelsHidden()
                .frame(width: 150)
                .accessibilityLabel("Type de raccourci")

                switch remap.kind {
                case .flAction:
                    actionMenu.frame(maxWidth: 280)
                case .keystroke:
                    ShortcutField(id: "\(remap.id)-target", role: .target, combo: $remap.target)
                        .frame(width: 140)
                }

                Spacer()
                Button(action: onDelete) { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .help("Supprimer")
                    .accessibilityLabel("Supprimer ce raccourci")
            }
            ForEach(issues.prefix(3), id: \.self) { issue in
                Label(issue.message, systemImage: issue.isBlocking ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(issue.isBlocking ? Color.red : Color.orange)
                    .padding(.leading, 40)
            }
        }
        .padding(.vertical, 3)
        .opacity(remap.enabled ? 1 : 0.5)
    }

    private var kindBinding: Binding<Remap.Kind> {
        Binding(get: { remap.kind }, set: { kind in
            remap.kind = kind
            if kind == .flAction && remap.actionID == nil && remap.unknownAction == nil { remap.actionID = 1 }
        })
    }

    private var actionMenu: some View {
        Menu(currentActionLabel) {
            ForEach(FLActionInfo.Category.allCases, id: \.self) { category in
                Section(category.rawValue) {
                    ForEach(FLActions.all.filter { $0.category == category }) { info in
                        let availability = status.availability(info.id)
                        Button(label(for: info, availability)) {
                            remap.actionID = info.id
                            remap.unknownAction = nil
                        }
                        .disabled(!availability.isUsable)
                    }
                }
            }
        }
        .accessibilityLabel("Action FL")
    }

    private var currentActionLabel: String {
        guard let id = remap.actionID, let info = FLActions.info(id) else {
            return "Action inconnue (\(remap.unknownAction ?? "?"))"
        }
        return info.label
    }

    private func label(for info: FLActionInfo, _ availability: ActionAvailability) -> String {
        if case .unavailable(let reason) = availability { return "\(info.label) — \(reason)" }
        return info.label
    }
}

/// Un seul enregistrement de raccourci à la fois (REL-19) ; le tap laisse tout passer pendant ce temps.
final class Recorder: ObservableObject {
    static let shared = Recorder()

    @Published private(set) var activeID: String? = nil
    @Published private(set) var hint: String? = nil

    private var monitor: Any?
    private var handler: ((NSEvent) -> Void)?
    private var timeout: DispatchWorkItem?
    private var resignObserver: NSObjectProtocol?

    private init() {}

    func start(_ id: String, handler: @escaping (NSEvent) -> Void) {
        stop()
        hint = nil
        activeID = id
        self.handler = handler
        Store.shared.recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let h = self.handler else { return event }
            self.stop()
            DispatchQueue.main.async { h(event) }
            return nil
        }
        let work = DispatchWorkItem { [weak self] in
            self?.stop()
            self?.hint = "Aucune touche reçue : macOS utilise peut-être ce raccourci."
        }
        timeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            self?.stop()
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        timeout?.cancel()
        timeout = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        handler = nil
        if activeID != nil { activeID = nil }
        if Store.shared.recording { Store.shared.recording = false }
    }
}

/// Bouton qui enregistre la prochaine combinaison. Échap annule, ⌫ seul efface.
struct ShortcutField: View {
    enum Role { case trigger, target }

    let id: String
    let role: Role
    @Binding var combo: KeyCombo?
    @ObservedObject private var recorder = Recorder.shared

    private var recording: Bool { recorder.activeID == id }

    var body: some View {
        Button {
            recording ? recorder.stop() : recorder.start(id, handler: accept)
        } label: {
            Text(recording ? "Appuie sur une touche…" : (combo?.display ?? "Cliquer pour définir"))
                .frame(maxWidth: .infinity)
                .foregroundStyle(recording ? Color.accentColor : (combo == nil ? Color.secondary : Color.primary))
        }
        .accessibilityLabel(role == .trigger ? "Raccourci déclencheur" : "Touche envoyée à FL")
        .onDisappear { if recording { recorder.stop() } }
    }

    private func accept(_ event: NSEvent) {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let candidate = KeyCombo(keyCode: event.keyCode, modifiers: mods)
        if !candidate.hasModifiers && event.keyCode == 53 { return }           // Échap : annuler
        if !candidate.hasModifiers && event.keyCode == 51 { combo = nil; return } // ⌫ : effacer
        guard candidate.isValidKey else { return }

        switch role {
        case .target:
            if let why = Store.shared.forbiddenReason(candidate) {
                Dialogs.inform("Touche interdite", "\(candidate.display) ne peut pas être envoyée à FL : \(why).")
                return
            }
        case .trigger:
            if candidate == Store.shared.toggleCombo {
                Dialogs.inform("Raccourci réservé", "⌃⌥⌘F sert à mettre FL Shortcut en pause.")
                return
            }
            if !candidate.hasModifiers && !KeyNames.functionKeys.contains(candidate.keyCode) {
                guard Dialogs.confirm("Touche seule : « \(candidate.display) »",
                                      "Elle ne pourra plus servir à taper du texte dans FL (noms, recherche, tempo) "
                                      + "ni au clavier-piano. Ajoute plutôt ⌃, ou limite-la à une fenêtre. Garder quand même ?")
                else { return }
            }
        }
        combo = candidate
    }
}

enum Dialogs {
    static func confirm(_ title: String, _ text: String) -> Bool {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.addButton(withTitle: "Continuer")
        a.addButton(withTitle: "Annuler")
        return a.runModal() == .alertFirstButtonReturn
    }

    static func inform(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.runModal()
    }
}
