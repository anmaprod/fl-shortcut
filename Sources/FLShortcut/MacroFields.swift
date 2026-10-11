// Champs de la fiche d'un raccourci de type « Macro » (modèle « Enregistrement rapide »).
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MacroFields: View {
    @Binding var macro: Macro
    @ObservedObject private var learner = MacroLearner.shared
    @ObservedObject private var status = AppStatus.shared
    /// Compte à rebours du bouton « Tester » (nil : rien en cours).
    @State private var countdown: Int?
    @State private var testNote: String?
    @State private var screenGranted = ScreenAccess.granted
    @State private var capturing = false

    private var automatic: Bool { macro.template == .autoRecord }

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
                Text(automatic
                     ? "Clique sur une piste du Mixer, puis tape le raccourci : File › Open mixer track state, ton preset, entrée 1, armement, REC. Ce qui est déjà allumé n'est pas touché."
                     : "Clic droit sur la piste → File → Open mixer track state, preset, armement, entrée 1, REC.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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

        Toggle("Choisir l'entrée 1 et armer la piste", isOn: $macro.armAndInput)
        Toggle("Allumer REC à la fin", isOn: Binding(get: { macro.startRecording }, set: { on in
            macro.startRecording = on
            if on { macro.recKey = AppMode.nativeEquivalent(of: 3, layout: SystemKeyboardLayout()) }
        }))

        Group {
        if automatic {
            LabeledContent("Lecture de FL") {
                VStack(alignment: .leading, spacing: 4) {
                    if screenGranted {
                        Label("Autorisée", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Autoriser l'enregistrement de l'écran…") { ScreenAccess.request() }
                    }
                    Text("La macro regarde la fenêtre de FL pendant qu'elle travaille (menus, boutons allumés). Rien n'est enregistré ni envoyé.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else {
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
        }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            screenGranted = ScreenAccess.granted
        }
        .onAppear {
            screenGranted = ScreenAccess.granted
            if macro.recKey == nil, macro.startRecording {
                macro.recKey = AppMode.nativeEquivalent(of: 3, layout: SystemKeyboardLayout())
            }
        }
        .onDisappear { learner.cancel() }

        LabeledContent("Essai") {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Button(countdown.map { "Départ dans \($0) s…" } ?? "Tester dans FL") { startTest() }
                        .disabled(countdown != nil || learner.isActive || capturing)
                    if automatic {
                        Button(capturing ? "Capture…" : "Capturer FL") { startCapture() }
                            .disabled(countdown != nil || capturing)
                            .help("Enregistre sur ton Bureau ce que l'app voit de FL, pour régler la macro si elle se trompe.")
                    }
                }
                Text(testNote ?? (automatic
                    ? "FL passe devant et la macro vise la dernière piste sur laquelle tu as cliqué. Échap l'arrête."
                    : "FL passe devant : place la souris sur une piste du Mixer avant la fin du compte à rebours. Échap arrête la macro."))
                    .font(.caption).foregroundStyle(testNote == nil ? Color.secondary : Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

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

    /// Lance la macro du brouillon (même enregistrée nulle part) : FL au premier plan, puis 3 s pour viser la piste.
    private func startTest() {
        testNote = nil
        if let why = MacroLibrary.problem(in: macro, forbidden: EventTap.shared.currentConfig.forbidden) {
            testNote = why
            return
        }
        guard let pid = EventTap.shared.currentConfig.flPIDs.first,
              let fl = NSRunningApplication(processIdentifier: pid) else {
            testNote = "Ouvre FL Studio, puis recommence."
            return
        }
        let draft = macro
        fl.activate(options: [])
        countdown = 3
        func tick() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                guard let left = countdown else { return }
                if left > 1 { countdown = left - 1; tick(); return }
                countdown = nil
                switch MacroRunner.shared.start(draft, flPID: pid) {
                case .started: break
                case .busy: testNote = "Une macro tourne déjà."
                case .refused: testNote = "FL Studio n'était pas au premier plan : recommence sans changer de fenêtre."
                }
            }
        }
        tick()
    }

    /// « Capturer FL » : FL passe devant, puis 3 s pour ouvrir ce qu'on veut montrer (menu, liste des entrées…).
    private func startCapture() {
        testNote = nil
        guard ScreenAccess.granted else {
            ScreenAccess.request()
            testNote = "Autorise d'abord l'enregistrement de l'écran."
            return
        }
        guard let pid = EventTap.shared.currentConfig.flPIDs.first,
              let fl = NSRunningApplication(processIdentifier: pid) else {
            testNote = "Ouvre FL Studio, puis recommence."
            return
        }
        fl.activate(options: [])
        capturing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            FLCapture.run(pid: pid) { dir in
                capturing = false
                if let dir {
                    NSWorkspace.shared.activateFileViewerSelecting([dir])
                    testNote = "Capture enregistrée sur ton Bureau (dossier « FL Shortcut – captures »)."
                } else {
                    testNote = "Capture impossible."
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
