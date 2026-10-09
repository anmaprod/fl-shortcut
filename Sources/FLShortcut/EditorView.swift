import SwiftUI
import AppKit

struct EditorView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var status: AppStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !status.accessibilityOK {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text("FL Shortcut a besoin de l'autorisation Accessibilité pour lire le clavier.")
                    Spacer()
                    Button("Ouvrir les réglages") { status.openAccessibilitySettings() }
                }
                .padding(10)
                .background(Color.orange.opacity(0.12))
            }

            HStack {
                Text("Raccourci").frame(width: 190, alignment: .leading)
                Text("Fait…").frame(width: 150, alignment: .leading)
                Text("Action")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
            .padding(.top, 10)

            List {
                ForEach($store.remaps) { $remap in
                    RemapRow(remap: $remap, isDuplicate: store.isDuplicate(remap)) {
                        let id = remap.id
                        DispatchQueue.main.async { store.remaps.removeAll { $0.id == id } }
                    }
                }
            }

            Divider()
            HStack {
                Button {
                    store.remaps.append(Remap())
                } label: {
                    Label("Ajouter un raccourci", systemImage: "plus")
                }
                Button("Restaurer les défauts") { store.resetToDefaults() }
                Spacer()
                Text("Actifs uniquement quand FL Studio est au premier plan · ⌃⌥⌘F pour couper")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
        }
    }
}

struct RemapRow: View {
    @Binding var remap: Remap
    var isDuplicate: Bool
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: $remap.enabled).labelsHidden()
            ShortcutField(combo: $remap.trigger)
                .frame(width: 140)
            Image(systemName: isDuplicate ? "exclamationmark.triangle.fill" : "arrow.right")
                .foregroundStyle(isDuplicate ? Color.orange : Color.secondary)
                .help(isDuplicate ? "Ce raccourci est utilisé plusieurs fois : seul le premier compte." : "")
                .frame(width: 20)
            Picker("", selection: $remap.kind) {
                Text("Action FL").tag(Remap.Kind.flAction)
                Text("Autre raccourci").tag(Remap.Kind.keystroke)
            }
            .labelsHidden()
            .frame(width: 150)

            switch remap.kind {
            case .flAction:
                Picker("", selection: $remap.action) {
                    ForEach(FLAction.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .frame(maxWidth: 260)
            case .keystroke:
                ShortcutField(combo: $remap.target)
                    .frame(width: 140)
            }

            Spacer()
            Button(action: onDelete) { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .help("Supprimer")
        }
        .padding(.vertical, 3)
        .opacity(remap.enabled ? 1 : 0.5)
    }
}

/// Bouton qui enregistre la prochaine combinaison de touches. Échap annule.
struct ShortcutField: View {
    @Binding var combo: KeyCombo?
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            recording ? stop() : start()
        } label: {
            Text(recording ? "Appuie sur une touche…" : (combo?.display ?? "Cliquer pour définir"))
                .frame(maxWidth: .infinity)
                .foregroundStyle(recording ? Color.accentColor : (combo == nil ? Color.secondary : Color.primary))
        }
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if event.keyCode != 53 || !mods.isEmpty {
                combo = KeyCombo(keyCode: event.keyCode, modifiers: mods)
            }
            stop()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
    }
}
