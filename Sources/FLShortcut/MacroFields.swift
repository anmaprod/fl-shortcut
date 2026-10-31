// Champs de la fiche d'un raccourci de type « Macro » (modèle « Enregistrement rapide »).
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MacroFields: View {
    @Binding var macro: Macro
    /// « Personnaliser dans le créateur… » (modèle automatique seulement) : nil, pas de bouton.
    var customize: (() -> Void)? = nil
    @ObservedObject private var learner = MacroLearner.shared
    @ObservedObject private var status = AppStatus.shared
    /// Compte à rebours du bouton « Tester » (nil : rien en cours).
    @State private var countdown: Int?
    @State private var testNote: String?
    @ObservedObject private var link = MIDILink.shared
    @State private var checking = false
    @State private var linkNote: String?
    @State private var spotsLearned = MacroSpots.anyLearned

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

    /// Titre du bouton « Tester » (compte à rebours pendant l'attente).
    private var testTitle: String {
        guard let left = countdown else { return String(localized: "Tester dans FL") }
        return String(localized: "Départ dans \(left) s…")
    }

    var body: some View {
        LabeledContent("Macro") {
            VStack(alignment: .leading, spacing: 2) {
                Text("Enregistrement rapide").fontWeight(.medium)
                Text(automatic
                     ? String(localized: "Clique au milieu de la tranche d'une piste du Mixer, puis tape le raccourci : ton preset fixe est déposé sur la piste (sinon File › Open mixer track state pour le choisir), armement, REC, entrée 1, et le larsen vérifié en dernier. Ce qui est déjà allumé n'est pas touché.")
                     : String(localized: "Clic droit sur la piste → File → Open mixer track state, preset, armement, entrée 1, REC."))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if automatic, let customize {
                    Button {
                        customize()
                    } label: {
                        Label("Personnaliser dans le créateur…", systemImage: "wand.and.stars")
                    }
                    .secondaryButton()
                    .padding(.top, 4)
                    .help("Développe le modèle en blocs que tu modifies un par un (le raccourci lance alors ta version)")
                }
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
                        Button("Changer…") { choosePreset() }.secondaryButton()
                    }
                }
            }
        }

        Toggle(automatic ? String(localized: "Armer la piste (si elle ne l'est pas) et choisir l'entrée 1")
                         : String(localized: "Choisir l'entrée 1 et armer la piste"), isOn: $macro.armAndInput)
        Toggle(automatic ? String(localized: "Allumer le REC à la fin (s'il est éteint)")
                         : String(localized: "Allumer REC à la fin"), isOn: Binding(get: { macro.startRecording }, set: { on in
            macro.startRecording = on
            if on { macro.recKey = AppMode.nativeEquivalent(of: 3, layout: SystemKeyboardLayout()) }
        }))

        Group {
        if automatic {
            if macro.armAndInput || macro.startRecording {
                LabeledContent("Lien avec FL") {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            if link.snapshot.hasKey {
                                Button(checking ? String(localized: "Vérification…") : String(localized: "Vérifier")) { checkLink() }.secondaryButton().disabled(checking)
                                Button("Réinstaller…") { FLScriptInstaller.installWithAlert() }.secondaryButton()
                            } else {
                                Button("Installer le lien avec FL…") { FLScriptInstaller.installWithAlert() }.primaryButton()
                            }
                        }
                        Text(linkNote ?? String(localized: "Sert seulement pendant la macro, à vérifier si la piste et le REC sont déjà armés. Le reste du temps, rien ne circule : FL ne ralentit pas. Une fois dans FL : Options › MIDI Settings, Input « FL Shortcuts » : Enable et Controller type « FL Shortcuts » ; Output « FL Shortcuts » : même numéro de port."))
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            LabeledContent("Clics appris") {
                VStack(alignment: .leading, spacing: 4) {
                    if spotsLearned {
                        Button("Réapprendre…") { MacroSpots.forgetAll(); spotsLearned = false }.secondaryButton()
                    }
                    Text(spotsLearned
                         ? String(localized: "L'entrée 1 est retenue. Réapprends-la si tu changes la disposition de FL.")
                         : String(localized: "« File › Open mixer track state » s'ouvre tout seul, au clavier (lettres soulignées du menu de FL). La première fois, une bulle te demande seulement de cliquer sur « (none) » puis sur l'entrée « 1 »."))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else {
            LabeledContent("Positions") {
                VStack(alignment: .leading, spacing: 6) {
                    learnRow(title: String(localized: "Menu de la piste"), done: menuLearned, optional: true, phase: .menu)
                    if macro.armAndInput {
                        learnRow(title: String(localized: "Armement et entrée"), done: armLearned, optional: false, phase: .armInput)
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
        .onAppear {
            spotsLearned = MacroSpots.anyLearned
            if macro.recKey == nil, macro.startRecording {
                macro.recKey = AppMode.nativeEquivalent(of: 3, layout: SystemKeyboardLayout())
            }
        }
        .onDisappear { learner.cancel() }

        LabeledContent("Essai") {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Button { startTest() } label: {
                        Label(testTitle, systemImage: "play.fill")
                    }
                    .secondaryButton()
                    .disabled(countdown != nil || learner.isActive)
                }
                Text(testNote ?? (automatic
                    ? String(localized: "FL passe devant et la macro vise la dernière piste sur laquelle tu as cliqué. Échap l'arrête.")
                    : String(localized: "FL passe devant : place la souris sur une piste du Mixer avant la fin du compte à rebours. Échap arrête la macro.")))
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

        LabeledContent("Journal") {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Button { MacroLogExport.run() } label: {
                        Label("Exporter le journal…", systemImage: "square.and.arrow.up")
                    }
                    .secondaryButton()
                    Button { MacroLogExport.revealInFinder() } label: {
                        Label("Afficher dans le Finder", systemImage: "folder")
                    }
                    .secondaryButton()
                }
                Text("Étapes, fenêtres de FL et clics de chaque macro, pour comprendre un échec. Aucune frappe, aucun nom de fichier.")
                    .font(.caption).foregroundStyle(.secondary)
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
                Button("Annuler") { learner.cancel() }.secondaryButton()
            } else {
                Button(done ? String(localized: "Refaire") : String(localized: "Apprendre")) {
                    learner.begin(phase) { spots in
                        for (name, spot) in spots { macro.spots[name] = spot }
                    }
                }
                .secondaryButton()
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
            testNote = String(localized: "Ouvre FL Studio, puis recommence.")
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
                case .busy: testNote = String(localized: "Une macro tourne déjà.")
                case .refused: testNote = String(localized: "FL Studio n'était pas au premier plan : recommence sans changer de fenêtre.")
                }
            }
        }
        tick()
    }

    /// Réveil bref du script : FL répond-il ? (MIDI Settings réglés, script à jour)
    private func checkLink() {
        checking = true
        linkNote = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let why = MIDILink.shared.runBriefly([])
            DispatchQueue.main.async {
                checking = false
                linkNote = why.map { String(localized: "Pas de réponse : \($0).") } ?? String(localized: "FL répond : le lien est prêt.")
            }
        }
    }

    private func choosePreset() {
        if let path = PresetPanel.choose() { macro.presetPath = path }
    }
}

/// Boîte « Ouvrir » d'un état de piste du Mixer (.fst), ouverte dans le dossier d'Image-Line s'il existe.
enum PresetPanel {
    /// Chemin choisi, nil si la boîte est annulée.
    static func choose() -> String? {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Choisis un état de piste du Mixer (.fst)")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if let type = UTType(filenameExtension: "fst") { panel.allowedContentTypes = [type] }
        panel.directoryURL = startFolder(home: FileManager.default.homeDirectoryForCurrentUser) {
            FileManager.default.fileExists(atPath: $0.path)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url.path
    }

    /// Dossier où la boîte s'ouvre : directement Image-Line › FL Studio › Presets › Mixer presets (demande du
    /// propriétaire, 25/10), sinon le plus proche qui existe.
    static func startFolder(home: URL, exists: (URL) -> Bool) -> URL? {
        let candidates = ["Documents/Image-Line/FL Studio/Presets/Mixer presets", "Documents/Image-Line/FL Studio/Presets",
                          "Documents/Image-Line/FL Studio", "Documents/Image-Line", "Music/Image-Line", "Documents"]
        return candidates.map { home.appendingPathComponent($0, isDirectory: true) }.first(where: exists)
    }
}
