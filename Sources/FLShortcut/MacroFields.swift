// Champs de la fiche d'un raccourci de type « Macro » (modèle « Enregistrement rapide »).
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MacroFields: View {
    @Binding var macro: Macro
    @ObservedObject private var learner = MacroLearner.shared
    @ObservedObject private var status = AppStatus.shared

    private var fixedPreset: Bool { macro.presetPath != nil }

    private var presetMode: Binding<Bool> {
        Binding(get: { fixedPreset }, set: { fixed in
            if fixed {
                if macro.presetPath == nil { choosePreset() }
            } else {
                macro.presetPath = nil
            }
        })
    }

    private var menuLearned: Bool {
        macro.spots[Macro.Spot.menuFile] != nil && macro.spots[Macro.Spot.menuOpenState] != nil
    }

    private var armLearned: Bool { MacroLibrary.requiredSpots.allSatisfy { macro.spots[$0] != nil } }

    var body: some View {
        LabeledContent("Macro") {
            VStack(alignment: .leading, spacing: 2) {
                Text("Enregistrement rapide").fontWeight(.medium)
                Text("Clic droit sur la piste → File → Open mixer track state, preset, armement, entrée 1, REC.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }

        LabeledContent("Preset") {
            VStack(alignment: .leading, spacing: 6) {
                Picker("", selection: presetMode) {
                    Text("Choisir à chaque fois (liste de FL)").tag(false)
                    Text("Toujours le même preset").tag(true)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                if let path = macro.presetPath {
                    HStack(spacing: 8) {
                        Text(URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent)
                            .lineLimit(1).truncationMode(.middle)
                        Button("Changer…") { choosePreset() }
                    }
                }
            }
        }

        Toggle("Armer la piste et choisir la première entrée", isOn: $macro.armAndInput)
        Toggle("Allumer REC à la fin", isOn: Binding(get: { macro.startRecording }, set: { on in
            macro.startRecording = on
            if on { macro.recKey = AppMode.nativeEquivalent(of: 3, layout: SystemKeyboardLayout()) }
        }))

        LabeledContent("Positions") {
            VStack(alignment: .leading, spacing: 6) {
                learnRow(title: "Menu de la piste", done: menuLearned, optional: true, phase: .menu)
                if macro.armAndInput {
                    learnRow(title: "Armement et entrée", done: armLearned, optional: false, phase: .armInput)
                }
                if let step = learner.instruction {
                    Text(step).font(.callout).foregroundStyle(.tint)
                }
                if let note = learner.message {
                    Text(note).font(.caption).foregroundStyle(.orange)
                }
                Text("FL ne permet pas de lire ces boutons : montre-les une fois en cliquant dessus dans FL.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear {
            if macro.recKey == nil, macro.startRecording {
                macro.recKey = AppMode.nativeEquivalent(of: 3, layout: SystemKeyboardLayout())
            }
        }
        .onDisappear { learner.cancel() }

        if let last = status.lastMacro {
            LabeledContent("Dernier essai") {
                Label(last.text, systemImage: last.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(last.ok ? Color.green : Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func learnRow(title: String, done: Bool, optional: Bool, phase: MacroLearner.Phase) -> some View {
        HStack(spacing: 8) {
            Image(systemName: done ? "checkmark.circle.fill" : (optional ? "circle.dashed" : "exclamationmark.circle"))
                .foregroundStyle(done ? Color.green : Color.secondary)
            Text(title)
            Spacer()
            if learner.isActive {
                Button("Annuler") { learner.cancel() }
            } else {
                Button(done ? "Refaire" : "Apprendre") {
                    learner.begin(phase) { spots in
                        for (name, spot) in spots { macro.spots[name] = spot }
                    }
                }
            }
        }
    }

    private func choosePreset() {
        let panel = NSOpenPanel()
        panel.title = "Choisis un état de piste du Mixer (.fst)"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if let type = UTType(filenameExtension: "fst") { panel.allowedContentTypes = [type] }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = ["Documents/Image-Line", "Music/Image-Line", "Documents"]
        panel.directoryURL = candidates.map { home.appendingPathComponent($0) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        macro.presetPath = url.path
    }
}
