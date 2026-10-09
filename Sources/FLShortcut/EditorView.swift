// Fenêtre « Raccourcis » en Liquid Glass, d'après la simulation validée par les tests utilisateurs :
// liste par rubriques (Composition, Enregistrement, Mix, Navigation, Touches de FL), une ligne par raccourci
// avec ce qu'elle fait, fiche d'édition en feuille, notification « Annuler » après une suppression.
// Audit : REL-06 / PROTOCOL.md §5 (statut du lien), audit 04 §8.2 (actions grisées, « Disponible à partir de
//         FL X »), audit 05 §4.2-4.4 (conflits, touche seule confirmée, pause visible, noms de touches en clair,
//         VoiceOver), REL-19 (un seul enregistreur, ⌫ efface, Échap annule, ⌃⌥⌘F refusé, délai 5 s, arrêt à la
//         perte du focus, tap suspendu), REL-20 (avertissements issus de l'analyse de l'index), REL-21
//         (remplacement de profil confirmé et annulable), SEC-05 (cibles interdites refusées, import validé).
import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Fenêtre principale

struct EditorView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var status: AppStatus
    @EnvironmentObject var link: MIDILink
    @EnvironmentObject var fl: FLMonitor

    @ViewState private var query = ""
    @ViewState private var editing: Remap? = nil
    @ViewState private var editingIsNew = false
    @ViewState private var toast: ToastMessage? = nil

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, 32)
                    .padding(.top, 18)
                    .padding(.bottom, 14)
                banners
                    .padding(.horizontal, 32)
                list
            }
            if let toast {
                ToastView(message: toast) { self.toast = nil }
                    .padding(.bottom, 22)
                    .transition(Motion.rise)
                    .id(toast.id)                       // une nouvelle notification remplace l'ancienne en douceur
            }
        }
        .motion(Motion.bouncy, value: toast)
        .windowGlassBackground()
        .sheet(item: $editing) { remap in
            EditSheet(original: remap, isNew: editingIsNew) { message in show(message) }
                .environmentObject(store)
                .environmentObject(status)
                .environmentObject(link)
        }
    }

    // MARK: En-tête

    private var header: some View {
        HStack(alignment: .bottom, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Raccourcis")
                    .font(.system(size: 30, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
                StatusLine(store: store, status: status, link: link, fl: fl)
            }
            Spacer(minLength: 12)

            GlassGroup(spacing: 8) {
                HStack(spacing: 10) {
                    profileMenu

                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Rechercher", text: $query)
                            .textFieldStyle(.plain)
                            .frame(width: 150)
                            .accessibilityLabel("Rechercher un raccourci")
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .glassCapsule(interactive: true)

                    Button {
                        editingIsNew = true
                        editing = Remap().with { $0.actionID = nil }
                    } label: {
                        Image(systemName: "plus").font(.system(size: 14, weight: .bold))
                            .frame(width: 20, height: 20)
                    }
                    .primaryGlassButton()
                    .help("Nouveau raccourci")
                    .accessibilityLabel("Nouveau raccourci")

                    HStack(spacing: 8) {
                        Text(store.enabled ? "Actif" : "En pause")
                            .font(.system(size: 12, weight: .semibold))
                            .contentTransition(.interpolate)
                            .frame(minWidth: 52, alignment: .trailing)
                        Toggle("", isOn: $store.enabled).toggleStyle(.switch).labelsHidden()
                            .accessibilityLabel("Raccourcis actifs (⌃⌥⌘F)")
                    }
                    .padding(.leading, 12)
                    .padding(.trailing, 6)
                    .frame(height: 32)
                    .glassCapsule()
                    .motion(Motion.snappy, value: store.enabled)
                }
            }
        }
    }

    private var profileMenu: some View {
        Menu {
            ForEach(ProfilePreset.allCases) { preset in
                Button(preset.label) {
                    if Dialogs.confirm("Charger le profil « \(preset.label) » ?",
                                       preset.summary + "\n\nTes raccourcis actuels seront remplacés (annulable).") {
                        store.apply(preset: preset)
                        show(ToastMessage(text: "Profil « \(preset.label) » chargé", undo: { store.undoReplace() }))
                    }
                }
            }
            Divider()
            Button("Importer un profil…") { importProfile() }
            Button("Exporter mon profil…") { exportProfile() }
            if store.undoSnapshot != nil {
                Divider()
                Button("Annuler le dernier remplacement") { store.undoReplace() }
            }
        } label: {
            Label("Profil", systemImage: "person.crop.square.on.square.angled")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .padding(.horizontal, 6)
        .frame(height: 32)
        .glassCapsule()
    }

    // MARK: Bandeaux (seulement quand il faut agir)

    @ViewBuilder private var banners: some View {
        VStack(spacing: 8) {
            if !store.enabled {
                Banner(symbol: "pause.circle.fill", tint: .orange,
                       text: "FL Shortcut est en pause : FL Studio utilise ses raccourcis d'origine.") {
                    Button("Reprendre") { Motion.run { store.enabled = true } }.secondaryGlassButton()
                }
            }
            if !status.accessibilityOK {
                Banner(symbol: "hand.raised.fill", tint: .orange,
                       text: "FL Shortcut doit pouvoir lire le clavier (Accessibilité) pour reconnaître tes raccourcis.") {
                    Button("Autoriser") { status.openAccessibilitySettings() }.secondaryGlassButton()
                }
            }
            if status.staleTCC {
                Banner(symbol: "exclamationmark.triangle.fill", tint: .orange,
                       text: "Permission périmée : retire FL Shortcut de la liste Accessibilité puis ajoute-le à nouveau.") {
                    Button("Ouvrir les réglages") { status.openAccessibilitySettings() }.secondaryGlassButton()
                }
            }
            if status.secureInput {
                Banner(symbol: "lock.fill", tint: .orange,
                       text: "Saisie sécurisée activée par une autre appli (ex. Terminal) : macOS ne transmet plus les touches.") {
                    EmptyView()
                }
            }
            if status.scriptState == .modified {
                Banner(symbol: "exclamationmark.shield.fill", tint: .red,
                       text: "Le script FL a été modifié depuis son installation. Réinstalle-le pour retrouver un lien sûr.") {
                    Button("Réinstaller") { FLScriptInstaller.installWithAlert() }.secondaryGlassButton()
                }
            }
            if let error = store.saveError {
                Banner(symbol: "xmark.octagon.fill", tint: .red, text: error) { EmptyView() }
            }
            if let warning = store.loadWarning {
                Banner(symbol: "info.circle.fill", tint: .blue, text: warning) {
                    Button("OK") { Motion.run { store.loadWarning = nil } }.secondaryGlassButton()
                }
            }
        }
        .padding(.bottom, 6)
        .motion(Motion.smooth, value: bannerSignature)
    }

    /// Change dès qu'un bandeau apparaît ou disparaît : sert de déclencheur d'animation.
    private var bannerSignature: [Bool] {
        [store.enabled, status.accessibilityOK, status.staleTCC, status.secureInput,
         status.scriptState == .modified, store.saveError != nil, store.loadWarning != nil]
    }

    // MARK: Liste par rubriques

    private struct RowGroup: Identifiable {
        let id: String
        let rows: [Remap]
    }

    private var groups: [RowGroup] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let visible = store.remaps.filter { r in
            guard !q.isEmpty else { return true }
            let hay = [r.title, r.subtitle, r.trigger?.display ?? ""].joined(separator: " ")
            return hay.localizedCaseInsensitiveContains(q)
        }
        let order = FLActionInfo.Category.allCases.map(\.rawValue) + ["Touches de FL", "À compléter"]
        return order.compactMap { name in
            let rows = visible.filter { $0.groupName == name }
            return rows.isEmpty ? nil : RowGroup(id: name, rows: rows)
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                if groups.isEmpty {
                    VStack(spacing: 6) {
                        Text(store.remaps.isEmpty ? "Aucun raccourci" : "Aucun raccourci trouvé")
                            .font(.system(size: 15, weight: .semibold))
                        Text(store.remaps.isEmpty ? "Clique sur + pour créer ton premier raccourci." : "Essaie un autre mot.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                    .transition(.opacity)
                }
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 7) {
                        Text(group.id)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 6)
                            .accessibilityAddTraits(.isHeader)
                        VStack(spacing: 0) {
                            ForEach(Array(group.rows.enumerated()), id: \.element.id) { index, remap in
                                if index > 0 { Divider().padding(.leading, 16) }
                                ShortcutRow(remap: remap, issues: store.issues(for: remap.id)) {
                                    editingIsNew = false
                                    editing = remap
                                } onToggle: {
                                    var copy = remap
                                    copy.enabled.toggle()
                                    Motion.run(Motion.snappy) { store.upsert(copy) }
                                } onDelete: {
                                    delete(remap)
                                }
                                .transition(Motion.pop)
                            }
                        }
                        .glassCard(cornerRadius: 16)
                    }
                    .transition(Motion.pop)
                }
            }
            // Ajout, suppression, recherche : les lignes glissent à leur place au lieu de sauter.
            .motion(Motion.smooth, value: store.remaps)
            .motion(Motion.snappy, value: query)
            .padding(.horizontal, 32)
            .padding(.top, 4)
            .padding(.bottom, 80)
        }
    }

    // MARK: Actions

    private func delete(_ remap: Remap) {
        Motion.run { store.delete(remap.id) }
        show(ToastMessage(text: "Raccourci supprimé", undo: { Motion.run { store.upsert(remap) } }))
    }

    private func show(_ message: ToastMessage) {
        toast = message
        let id = message.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
            if toast?.id == id { toast = nil }
        }
    }

    private func show(_ text: String) { show(ToastMessage(text: text, undo: nil)) }

    private func importProfile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            guard size <= ProfileImporter.maxBytes else { throw ProfileImporter.Failure.tooLarge }
            let preview = try store.prepareImport(try Data(contentsOf: url))
            var text = preview.summary.joined(separator: "\n")
            if !preview.rejected.isEmpty { text += "\n\nRefusé(s) par sécurité :\n• " + preview.rejected.joined(separator: "\n• ") }
            text += "\n\nTes raccourcis actuels seront remplacés (annulable)."
            guard Dialogs.confirm("Importer ce profil ?", text) else { return }
            store.applyImport(preview)
            show(ToastMessage(text: "Profil importé", undo: { store.undoReplace() }))
        } catch {
            Dialogs.inform("Import impossible", error.localizedDescription)
        }
    }

    private func exportProfile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "FL Shortcut – profil.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.exportData().write(to: url, options: .atomic)
            show("Profil exporté")
        } catch {
            Dialogs.inform("Export impossible", error.localizedDescription)
        }
    }
}

// MARK: - Statut du lien (une ligne sous le titre)

private struct StatusLine: View {
    @ObservedObject var store: Store
    @ObservedObject var status: AppStatus
    @ObservedObject var link: MIDILink
    @ObservedObject var fl: FLMonitor

    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(color).frame(width: 7, height: 7).shadow(color: color.opacity(0.7), radius: 3)
                .scaleEffect(link.status == .linked && store.enabled ? 1 : 0.85)
            Text(text).font(.system(size: 13)).foregroundStyle(.secondary)
                .contentTransition(.interpolate)
            if let action {
                Button(action.label, action: action.run)
                    .buttonStyle(.link)
                    .font(.system(size: 13, weight: .semibold))
            }
        }
        .motion(Motion.smooth, value: text)
        .accessibilityElement(children: .combine)
    }

    private var color: Color {
        if !store.enabled { return .gray }
        switch link.status {
        case .linked: return .green
        case .inactive: return .orange
        case .flClosed: return .gray
        }
    }

    private var text: String {
        if !store.enabled { return "En pause : FL Studio utilise ses raccourcis d'origine" }
        let version = fl.version.map { " \($0)" } ?? ""
        switch link.status {
        case .linked: return "Relié à FL Studio\(version) · actif quand FL est au premier plan"
        case .flClosed: return "FL Studio n'est pas ouvert · tes raccourcis marcheront dès que tu l'ouvres"
        case .inactive:
            if !link.snapshot.hasKey { return "Lien avec FL Studio pas encore installé" }
            if link.snapshot.incompatibleProtocol != nil { return "Script FL d'une autre version" }
            return "Lien inactif : dans FL, Options › MIDI Settings, active l'entrée et la sortie « FL Shortcut »"
        }
    }

    private var action: (label: String, run: () -> Void)? {
        guard store.enabled, link.status == .inactive else { return nil }
        if !link.snapshot.hasKey || link.snapshot.incompatibleProtocol != nil {
            return ("Installer", { FLScriptInstaller.installWithAlert() })
        }
        return ("Tester", { link.testLink() })
    }
}

// MARK: - Une ligne

private struct ShortcutRow: View {
    let remap: Remap
    let issues: [ShortcutIssue]
    let onOpen: () -> Void
    let onToggle: () -> Void
    let onDelete: () -> Void
    @ViewState private var hovering = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 14) {
                KeyCaps(combo: remap.trigger, placeholder: "Aucun")
                    .frame(minWidth: 118, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(remap.title).font(.system(size: 14, weight: .medium))
                    Text(remap.subtitle).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                if remap.context != .everywhere {
                    Text(remap.context.label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .glassCapsule()
                }
                if !issues.isEmpty {
                    Image(systemName: issues.contains(where: \.isBlocking) ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(issues.contains(where: \.isBlocking) ? Color.red : Color.orange)
                        .help(issues.map(\.message).joined(separator: "\n"))
                        .accessibilityLabel("Attention : " + issues.map(\.message).joined(separator: " "))
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .offset(x: hovering && !Motion.reduce ? 2 : 0)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
            .background(hovering ? Color.primary.opacity(0.05) : .clear)
        }
        .buttonStyle(PressableRowStyle())
        .opacity(remap.enabled ? 1 : 0.5)
        .onHover { hovering = $0 }
        .motion(Motion.hover, value: hovering)
        .contextMenu {
            Button(remap.enabled ? "Désactiver" : "Activer", action: onToggle)
            Button("Supprimer", role: .destructive, action: onDelete)
        }
        .accessibilityLabel("\(remap.trigger?.spoken ?? "Aucun raccourci") : \(remap.title)")
        .accessibilityHint("Ouvre la fiche du raccourci")
    }
}

// MARK: - Fiche d'édition

struct EditSheet: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var status: AppStatus
    @EnvironmentObject var link: MIDILink
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var recorder = Recorder.shared

    let isNew: Bool
    let onDone: (ToastMessage) -> Void
    @ViewState private var draft: Remap
    @ViewState private var category: FLActionInfo.Category
    @ViewState private var query = ""
    @Namespace private var chips
    @ViewState private var testCount = 0

    init(original: Remap, isNew: Bool, onDone: @escaping (ToastMessage) -> Void) {
        self.isNew = isNew
        self.onDone = onDone
        _draft = ViewState(wrappedValue: original)
        let cat = original.actionID.flatMap(FLActions.info)?.category ?? .composition
        _category = ViewState(wrappedValue: cat)
    }

    private var issues: [ShortcutIssue] {
        guard draft.trigger != nil || draft.target != nil else { return [] }
        return store.draftIssues(draft).filter {
            if case .noTrigger = $0 { return false }
            if case .noTarget = $0 { return false }
            return true
        }
    }

    private var canSave: Bool {
        guard recorder.activeID == nil, draft.trigger != nil else { return false }
        switch draft.kind {
        case .flAction: guard draft.actionID != nil else { return false }
        case .keystroke: guard draft.target != nil else { return false }
        }
        return !store.draftIssues(draft).contains(where: \.isBlocking)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isNew ? "Nouveau raccourci" : "Modifier le raccourci")
                .font(.system(size: 17, weight: .semibold))
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 7) {
                Text("Ton raccourci").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                CaptureField(id: "\(draft.id)-trigger", role: .trigger, combo: $draft.trigger)
                if !issues.isEmpty && recorder.activeID == nil {
                    IssuesView(issues: issues)
                        .transition(Motion.transition(.opacity.combined(with: .offset(y: -4))))
                }
            }
            .motion(Motion.smooth, value: issues.map(\.message))

            Picker("Ce que fait le raccourci", selection: kindBinding) {
                Text("Action dans FL").tag(Remap.Kind.flAction)
                Text("Touche de FL").tag(Remap.Kind.keystroke)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Group {
                switch draft.kind {
                case .flAction: actionPicker.transition(Motion.transition(.opacity.combined(with: .offset(x: -12))))
                case .keystroke: keystrokePicker.transition(Motion.transition(.opacity.combined(with: .offset(x: 12))))
                }
            }

            HStack(spacing: 8) {
                if !isNew {
                    Button("Supprimer", role: .destructive) {
                        let removed = draft
                        store.delete(draft.id)
                        onDone(ToastMessage(text: "Raccourci supprimé", undo: { store.upsert(removed) }))
                        dismiss()
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                }
                Spacer()
                Button("Annuler") { recorder.stop(); dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .secondaryGlassButton()
                Button("Valider") {
                    recorder.stop()
                    var final = draft
                    final.enabled = true
                    if final.kind == .flAction { final.target = nil } else { final.actionID = nil }
                    store.upsert(final)
                    onDone(ToastMessage(text: isNew ? "Raccourci ajouté" : "Raccourci modifié", undo: nil))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .primaryGlassButton()
                .disabled(!canSave)
            }
        }
        .padding(24)
        .frame(width: 520)
        .onDisappear { recorder.stop() }
    }

    private var kindBinding: Binding<Remap.Kind> {
        Binding(get: { draft.kind }, set: { kind in Motion.run { draft.kind = kind } })
    }

    private var actionPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Rechercher une action", text: $query).textFieldStyle(.plain)
                }
                .padding(.horizontal, 12)
                .frame(height: 32)
                .glassCapsule()
                Button {
                    if let id = draft.actionID { link.test(action: id); testCount += 1 }
                } label: {
                    Label("Tester", systemImage: "play.fill")
                        .bounceSymbol(on: testCount)
                }
                .secondaryGlassButton()
                .disabled(draft.actionID == nil || link.status != .linked)
                .help("Envoie l'action à FL Studio pour vérifier")
            }

            HStack(spacing: 6) {
                ForEach(FLActionInfo.Category.allCases, id: \.self) { c in
                    let selected = query.isEmpty && category == c
                    Button(c.rawValue) { Motion.run(Motion.snappy) { category = c; query = "" } }
                        .buttonStyle(PressableRowStyle())
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .foregroundStyle(selected ? Color.white : Color.primary)
                        .background {
                            // La pastille de sélection glisse d'une rubrique à l'autre.
                            if selected {
                                Capsule().fill(Color.accentColor).matchedGeometryEffect(id: "chip", in: chips)
                            } else {
                                Capsule().fill(Color.primary.opacity(0.06))
                            }
                        }
                        .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }

            ScrollView {
                VStack(spacing: 0) {
                    let list = actions
                    ForEach(Array(list.enumerated()), id: \.element.id) { index, info in
                        if index > 0 { Divider() }
                        actionRow(info)
                    }
                    if list.isEmpty {
                        Text("Aucune action trouvée").font(.caption).foregroundStyle(.secondary).padding(16)
                    }
                }
            }
            .frame(height: 190)
            .glassCard(cornerRadius: 14)
            .motion(Motion.snappy, value: query)

            HStack(spacing: 10) {
                Text("Où ?").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                Picker("Où ?", selection: $draft.context) {
                    ForEach(ShortcutContext.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
    }

    private var actions: [FLActionInfo] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return FLActions.all.filter { info in
            q.isEmpty ? info.category == category
                      : (info.label + " " + info.detail).localizedCaseInsensitiveContains(q)
        }
    }

    private func actionRow(_ info: FLActionInfo) -> some View {
        let availability = status.availability(info.id)
        let selected = draft.actionID == info.id
        return Button {
            Motion.run(Motion.snappy) {
                draft.actionID = info.id
                draft.unknownAction = nil
            }
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(info.label).font(.system(size: 13, weight: .semibold))
                    if case .unavailable(let reason) = availability {
                        Text(reason).font(.system(size: 11)).foregroundStyle(.secondary)
                    } else {
                        Text(info.detail).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Color.accentColor)
                        .transition(Motion.transition(.scale(scale: 0.4).combined(with: .opacity)))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(selected ? Color.accentColor.opacity(0.12) : .clear)
        }
        .buttonStyle(PressableRowStyle())
        .disabled(!availability.isUsable)
        .opacity(availability.isUsable ? 1 : 0.5)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var keystrokePicker: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Pour déplacer un raccourci de FL Studio sur une touche plus pratique.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            CaptureField(id: "\(draft.id)-target", role: .target, combo: $draft.target)
            if let t = draft.target, let name = store.conflicts.flConflict(t) {
                Text("Dans FL Studio : \(name.replacingOccurrences(of: "FL : ", with: ""))")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }
}

private struct IssuesView: View {
    let issues: [ShortcutIssue]

    var body: some View {
        let blocking = issues.contains(where: \.isBlocking)
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: blocking ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(blocking ? Color.red : Color.orange)
            Text(issues.map(\.message).joined(separator: " "))
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill((blocking ? Color.red : Color.orange).opacity(0.14)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder((blocking ? Color.red : Color.orange).opacity(0.35)))
        .transition(.opacity)
    }
}

// MARK: - Champ d'enregistrement d'un raccourci

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

/// Grand champ : clique, puis appuie sur tes touches. Échap annule, ⌫ seul efface.
struct CaptureField: View {
    enum Role { case trigger, target }

    let id: String
    let role: Role
    @Binding var combo: KeyCombo?
    @ObservedObject private var recorder = Recorder.shared

    private var recording: Bool { recorder.activeID == id }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                recording ? recorder.stop() : recorder.start(id, handler: accept)
            } label: {
                ZStack {
                    if recording {
                        Text("Appuie sur tes touches…").font(.system(size: 14)).foregroundStyle(Color.accentColor)
                            .transition(Motion.transition(.opacity.combined(with: .scale(scale: 0.96))))
                    } else if let combo {
                        KeyCaps(combo: combo, large: true)
                            .transition(Motion.transition(.opacity.combined(with: .scale(scale: 0.9))))
                    } else {
                        Text(role == .trigger ? "Clique ici, puis appuie sur tes touches" : "Clique ici, puis tape le raccourci de FL")
                            .font(.system(size: 14)).foregroundStyle(.secondary)
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 72)
                .contentShape(Rectangle())
                .motion(Motion.bouncy, value: recording)
                .motion(Motion.bouncy, value: combo)
            }
            .buttonStyle(PressableRowStyle())
            .glassCard(cornerRadius: 18)
            .overlay {
                // Contour présent seulement pendant l'enregistrement : la lueur pulse dans une vue qui disparaît
                // avec lui, donc la répétition infinie s'arrête à coup sûr (relecture 11).
                if recording {
                    ZStack {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.accentColor, lineWidth: 1.5)
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.accentColor, lineWidth: 1.5)
                            .shadow(color: Color.accentColor.opacity(0.5), radius: 8)
                            .pulsing(duration: 0.9, low: 0)
                    }
                    .allowsHitTesting(false)
                }
            }
            .motion(Motion.snappy, value: recording)
            .accessibilityLabel(role == .trigger ? "Raccourci déclencheur" : "Touche envoyée à FL")
            .accessibilityValue(recording ? "Enregistrement en cours" : (combo?.spoken ?? "aucun"))

            if recording, let hint = recorder.hint {
                Text(hint).font(.caption).foregroundStyle(.orange).transition(.opacity)
            } else if recording {
                Text("Échap pour annuler · ⌫ pour effacer").font(.caption).foregroundStyle(.secondary).transition(.opacity)
            }
        }
        .motion(Motion.smooth, value: recording)
        .onDisappear { if recording { recorder.stop() } }
    }

    private func accept(_ event: NSEvent) {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let candidate = KeyCombo(keyCode: event.keyCode, modifiers: mods)
        if !candidate.hasModifiers && event.keyCode == 53 { return }            // Échap : annuler
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

// MARK: - Éléments communs

struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let undo: (() -> Void)?

    static func == (a: ToastMessage, b: ToastMessage) -> Bool { a.id == b.id }
}

private struct ToastView: View {
    let message: ToastMessage
    let onClose: () -> Void
    @ViewState private var appeared = false

    var body: some View {
        HStack(spacing: 12) {
            if message.undo == nil {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    .bounceSymbol(on: appeared)
            }
            Text(message.text).font(.system(size: 13, weight: .medium))
            if let undo = message.undo {
                Button("Annuler") { undo(); onClose() }
                    .secondaryGlassButton()
                    .controlSize(.small)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, message.undo == nil ? 16 : 8)
        .frame(height: 44)
        .glassCapsule()
        .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { appeared = true } }
        .accessibilityElement(children: .contain)
    }
}

struct Banner<Accessory: View>: View {
    let symbol: String
    let tint: Color
    let text: String
    @ViewBuilder let accessory: () -> Accessory

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(text).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            accessory()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassCard(cornerRadius: 14)
        .transition(Motion.transition(.move(edge: .top).combined(with: .opacity)))
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

// MARK: - Aides de présentation

extension Remap {
    /// Copie modifiée (création d'un brouillon).
    func with(_ change: (inout Remap) -> Void) -> Remap {
        var copy = self
        change(&copy)
        return copy
    }

    var title: String {
        switch kind {
        case .keystroke: return target.map { "Envoie \($0.display)" } ?? "Touche de FL à choisir"
        case .flAction:
            if let id = actionID, let info = FLActions.info(id) { return info.label }
            return unknownAction.map { "Action inconnue (\($0.displaySafe()))" } ?? "Action à choisir"
        }
    }

    var subtitle: String {
        switch kind {
        case .keystroke: return "Raccourci de FL Studio"
        case .flAction:
            guard let id = actionID, let info = FLActions.info(id) else { return "Mets FL Shortcut à jour pour l'utiliser" }
            if case .unavailable(let reason) = AppStatus.shared.availability(id) { return reason }
            return info.detail
        }
    }

    var groupName: String {
        if trigger == nil { return "À compléter" }
        switch kind {
        case .keystroke: return "Touches de FL"
        case .flAction:
            guard let id = actionID, let info = FLActions.info(id) else { return "À compléter" }
            return info.category.rawValue
        }
    }
}

extension View {
    /// Fond de fenêtre translucide (macOS 15+), le contenu en verre flotte dessus.
    @ViewBuilder
    func windowGlassBackground() -> some View {
        #if compiler(>=6.0)
        if #available(macOS 15.0, *) {
            self.containerBackground(.thinMaterial, for: .window)
        } else {
            self.background(VisualEffectBackground())
        }
        #else
        self.background(VisualEffectBackground())
        #endif
    }
}

/// Fond translucide pour macOS 13–14.
struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .underWindowBackground
        v.blendingMode = .behindWindow
        v.state = .followsWindowActiveState
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
