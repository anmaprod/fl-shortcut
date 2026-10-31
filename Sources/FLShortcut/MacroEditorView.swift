// Créateur de macros : affiché DANS la fenêtre principale (comme un dossier dans le Finder), à l'identique de la
// maquette du 28/10 (demande du 29/10) ; vue et modèle libérés au retour (EditorView, CreatorPresence).
// - À gauche, la palette dans une plaque claire (blocs par catégorie) ; au centre, l'en-tête (← rond, nom en gras,
//   touches du raccourci, « Enregistrer » bleu : ⌘S, sinon 0,5 s après la dernière modification), « Enregistrer
//   clics et touches », puis les étapes dans une carte (une phrase par ligne, valeurs en pastilles, icône colorée de
//   la catégorie, interrupteur) et la zone en pointillés où glisser un bloc ; à droite, les réglages du bloc choisi
//   dans une plaque (« Retirer ce bloc » en bas). Plus de barre d'outils, d'Exporter, de Dupliquer, de « Si le bloc
//   échoue » ni de note (29/10 : « le reste ça part »).
// - Essai : chaque ligne montre son état (bleu en cours, coche verte faite, rouge échouée avec la raison) ; un
//   bandeau flottant donne le résultat (« Échec au bloc 4 (…) : … » et « Montrer le bloc »). Échap arrête.
// Performance : lignes Equatable sans objet observé par ligne, aucun verre par ligne, aucune animation au repos ;
// seules les lignes dont l'état change pendant un essai sont redessinées.
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Demande d'ouverture du créateur : quelle macro montrer. La fenêtre principale (EditorView) l'affiche alors en son
/// sein ; déjà affiché, le créateur passe à cette macro.
final class MacroCreatorLink: ObservableObject {
    static let shared = MacroCreatorLink()

    struct Request: Equatable {
        let serial: Int
        let id: UUID?
        /// Macro d'exemple jamais enregistrée (mesure de l'interface).
        let sample: Bool
        /// Macro créée à l'instant (nouvelle, modèle) : au retour, l'enregistrer ou la supprimer.
        var isNew = false
        /// « Enregistrer une macro » : l'enregistrement des clics et des touches démarre dès l'ouverture.
        var record = false
    }

    @Published private(set) var request: Request?
    /// Retour aux raccourcis demandé sans question (mesure de l'interface).
    @Published private(set) var closeSerial = 0
    /// Dernière macro quittée par ← : la flèche → des raccourcis y ramène, comme dans le Finder.
    @Published var lastClosedID: UUID?
    private var serial = 0

    private init() {}

    func open(_ id: UUID?, isNew: Bool = false, record: Bool = false) {
        serial += 1
        request = Request(serial: serial, id: id, sample: false, isNew: isNew, record: record)
    }

    func openSample() {
        serial += 1
        request = Request(serial: serial, id: nil, sample: true)
    }

    /// Fermeture demandée (mesure de l'interface).
    func requestClose() { closeSerial += 1 }
}

/// Bandeau du créateur quand la bibliothèque ne peut pas être enregistrée : le brouillon n'est pas gardé.
private struct LibraryProblemBanner: View {
    @ObservedObject var library: MacroLibraryStore

    var body: some View {
        if library.problem != nil {
            MacroLibraryProblemLabel(library: library)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.12))
            Divider()
        }
    }
}

struct MacroCreatorView: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var link = MacroCreatorLink.shared
    /// Possédé par la fenêtre principale tant que le créateur y est affiché (libéré au retour).
    @ObservedObject var model: MacroEditorModel
    /// Flèche ← : retour aux raccourcis (avec la question « Enregistrer ou supprimer » si besoin).
    let onBack: () -> Void
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        HStack(spacing: 0) {
            MacroPaletteView(items: model.paletteItems, insert: { [model] item in
                withAnimation(MacroStepsPane.spring) { model.insert(item) }
            })
                .frame(width: EditorView.sidebarWidth)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(MockPlate(cornerRadius: 19, top: 0.10, bottom: 0.04, border: 0.16))
            // Colonnes souples : quand la fenêtre se resserre, les étapes puis les réglages rétrécissent (jamais rien
            // de coupé ; la fenêtre ne descend pas sous 820 points, et 252 + 280 + 240 y tiennent).
            VStack(spacing: 0) {
                LibraryProblemBanner(library: store.library)
                MacroStepsPane(model: model, monitor: model.monitor, paletteItems: model.paletteItems, onBack: onBack)
            }
            .frame(minWidth: 280, maxWidth: .infinity, maxHeight: .infinity)
            // Réglages du bloc : largeur fixe, les étapes gardent la place (photo de la CI : lignes coupées).
            MacroInspectorView(model: model)
                .padding(.top, MainWindowChrome.contentTop - 8)
                .frame(width: 270)
                .frame(maxHeight: .infinity)
                .background(MockPlate(cornerRadius: 19, top: 0.10, bottom: 0.04, border: 0.16))
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Appearance.windowColor)
        // Sous la barre de titre transparente, comme la page des raccourcis (MainWindowChrome).
        .ignoresSafeArea()
        // Titre de la fenêtre (menu Fenêtre, VoiceOver) ; jamais affiché.
        .navigationTitle(model.draft?.name ?? String(localized: "Créateur de macros"))
        .hiddenWindowChrome()
        // Fenêtre qui l'affiche : retour du focus après « Montrer dans FL… », et devant FL tant qu'il est affiché.
        .background(WindowReader { [model] window in
            model.window = window
            CreatorPresence.attach(window)
            MainWindowChrome.keep(window)
        })
        .onAppear {
            model.undoManager = undoManager
            model.handle(link.request)                  // déjà fait avant l'ouverture : sans effet
        }
        .onChange(of: link.request) { request in model.handle(request) }
    }
}

// MARK: - Liste des étapes

private struct MacroStepsPane: View {
    @ObservedObject var model: MacroEditorModel
    @ObservedObject var monitor: MacroRunMonitor
    let paletteItems: [PaletteItem]
    /// ← : retour aux raccourcis (avec la question « Enregistrer ou supprimer » si besoin).
    let onBack: () -> Void

    var body: some View {
        Group {
            if model.draft != nil {
                VStack(alignment: .leading, spacing: 12) {
                    MacroHeader(model: model, onBack: onBack)
                        .padding(.horizontal, 22)
                    list
                }
                // Sous la barre de titre : elle ne laisse passer aucun clic.
                .padding(.top, MainWindowChrome.contentTop)
            } else {
                VStack(spacing: 10) {
                    SectionIcon(symbol: "wand.and.stars", tint: .purple, size: 44)
                    Text("Aucune macro ouverte").font(.title3.weight(.semibold))
                    Text("Crée une macro, ou ouvre-en une depuis la fenêtre Raccourcis › Macros.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Button("Nouvelle macro") { model.newMacro() }
                        .primaryButton()
                        .controlSize(.large)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .topLeading) {
                    CreatorBackButton(action: onBack)
                        .padding(.leading, 22)
                        .padding(.top, MainWindowChrome.contentTop)
                }
            }
        }
        .floatingBar(.bottom) {
            MacroResultBanner(model: model, monitor: monitor)
        }
    }

    /// Ressort court et sans rebond visible, façon Apple : les lignes s'écartent pour le bloc ajouté, glissent quand
    /// on les range, se resserrent quand on en supprime. Seulement au moment du changement : rien ne tourne au repos.
    static let spring = Animation.spring(response: 0.32, dampingFraction: 0.86)

    /// Les étapes dans une carte (maquette : une plaque claire, un trait fin entre deux lignes), puis la zone en
    /// pointillés où lâcher un bloc. Toujours une liste : sélection, ⌫, rangement et dépôt entre deux lignes.
    private var list: some View {
        let rows = model.rows
        return List(selection: $model.selection) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                MacroStepRowView(row: row, status: status(row), current: monitor.current == row.blockID && row.kind == .block,
                                 selected: model.selection == row.id,
                                 onToggle: { on in model.setEnabled(row.blockID, on) })
                    .equatable()
                    // Survol : toute la ligne de la couleur de son bloc (pas la ligne choisie, ni une fin de boucle).
                    .cardRow(.position(index: index, count: rows.count),
                             hover: row.kind == .block && model.selection != row.id ? (row.category?.tint ?? .gray) : nil)
                    .tag(row.id)
                    .moveDisabled(row.kind != .block)          // les lignes de fin suivent leur boucle
                    .contextMenu { contextMenu(row) }
            }
            .onMove { offsets, to in
                withAnimation(Self.spring) { model.move(fromOffsets: offsets, toOffset: to) }
            }
            // Bloc glissé depuis la palette : lâché entre deux lignes, il prend cette place (3e, 4e…).
            .onInsert(of: [.plainText]) { index, providers in
                dropFromPalette(providers, beforeRow: index)
            }
            if !rows.isEmpty {
                dropZone
                    .moveDisabled(true)
                    .listRowInsets(EdgeInsets(top: 12, leading: CardRowBackground.inset, bottom: 8,
                                              trailing: CardRowBackground.inset))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.inset)
        .glassListBackground()
        .onDeleteCommand { withAnimation(Self.spring) { model.deleteSelection() } }
        .overlay {
            if model.rows.isEmpty {
                // Le plus simple d'abord : enregistrer ce qu'on fait dans FL ; les blocs de la palette ensuite.
                VStack(spacing: 10) {
                    Image(systemName: "record.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.red)
                        .accessibilityHidden(true)
                    Text("Enregistre ce que tu fais dans FL").font(.title3.weight(.semibold))
                    Text(String(localized: "Clique, utilise les flèches, tes raccourcis… : chaque geste devient un bloc, que tu peux ")
                         + String(localized: "ensuite modifier, ranger ou supprimer."))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 340)
                        .fixedSize(horizontal: false, vertical: true)
                    RecordStartButton(model: model)
                    Text("ou glisse des blocs de la palette, à gauche")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onDrop(of: [.plainText], isTargeted: nil) { providers in
                    dropFromPalette(providers, beforeRow: 0)
                    return true
                }
            }
        }
    }

    private func dropFromPalette(_ providers: [NSItemProvider], beforeRow row: Int) {
        let items = paletteItems
        PaletteDrag.load(providers) { [model] id in
            guard let item = items.first(where: { $0.id == id }) else { return }
            withAnimation(Self.spring) { model.insert(item, beforeRow: row) }
        }
    }

    private func status(_ row: MacroStepRow) -> MacroRunMonitor.Status? {
        guard row.kind == .block else { return nil }
        return monitor.statuses[row.blockID]
    }

    @ViewBuilder private func contextMenu(_ row: MacroStepRow) -> some View {
        if row.kind == .block {
            Button(row.ownEnabled ? String(localized: "Désactiver") : String(localized: "Activer")) {
                model.setEnabled(row.blockID, !row.ownEnabled)
            }
            Divider()
            Button("Supprimer", role: .destructive) {
                model.selection = row.id
                withAnimation(Self.spring) { model.deleteSelection() }
            }
        }
    }

    /// Zone en pointillés sous les étapes (maquette) : un bloc de la palette lâché ici va à la fin.
    private var dropZone: some View {
        Text("Glisse un bloc ici, ou clique-le dans la liste à gauche")
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 52)
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
            .contentShape(Rectangle())
            .onDrop(of: [.plainText], isTargeted: nil) { providers in
                dropFromPalette(providers, beforeRow: model.rows.count)
                return true
            }
    }
}

/// « Enregistrer clics et touches », le cœur des macros : FL passe devant, chaque clic, flèche ou raccourci devient
/// un bloc (panneau « Terminer » en haut à droite). En grand dans l'en-tête du créateur (⇧⌘R) ; seul l'enregistreur
/// est observé : le reste de l'en-tête n'est pas redessiné.
private struct RecordHero: View {
    let model: MacroEditorModel
    @ObservedObject private var recorder = ClickSequenceRecorder.shared

    var body: some View {
        Button {
            model.recordClicks()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: recorder.active ? "record.circle.fill" : "record.circle")
                    .font(.system(size: 22))
                    .hoverTint(.red)
                VStack(alignment: .leading, spacing: 1) {
                    Text(recorder.active ? String(localized: "Enregistrement en cours…")
                                         : String(localized: "Enregistrer clics et touches"))
                        .font(.system(size: 13, weight: .semibold))
                    // Une phrase seulement pendant l'enregistrement : comment le finir.
                    if recorder.active {
                        Text("Clique et tape dans FL, puis « Terminer » en haut à droite.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                Text("⇧⌘R").font(.system(size: 11).monospacedDigit()).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.red.opacity(0.09)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.red.opacity(0.3)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .menuHover(tint: .red)
        .keyboardShortcut("r", modifiers: [.command, .shift])
        .disabled(recorder.active)
        .help("FL passe devant : clique et tape dans l'ordre (menus, Options › Audio, boutons de ses fenêtres, flèches, raccourcis…), puis « Terminer ». Chaque clic et chaque touche devient un bloc, ajouté sous la ligne choisie.")
        .accessibilityLabel("Enregistrer clics et touches")
    }
}

/// Grand bouton rouge de la macro vide : « Commencer l'enregistrement ».
private struct RecordStartButton: View {
    let model: MacroEditorModel
    @ObservedObject private var recorder = ClickSequenceRecorder.shared

    var body: some View {
        Button {
            model.recordClicks()
        } label: {
            Label(recorder.active ? String(localized: "Enregistrement en cours…") : String(localized: "Commencer l'enregistrement"),
                  systemImage: "record.circle")
                .frame(minWidth: 220)
        }
        .primaryButton()
        .tint(.red)
        .controlSize(.large)
        .keyboardShortcut("r", modifiers: [.command, .shift])
        .disabled(recorder.active)
        .help("FL passe devant : clique et tape dans l'ordre, puis « Terminer » en haut à droite (⇧⌘R).")
    }
}

/// Une ligne : case « actif », numéro, icône de la catégorie, phrase avec sa valeur en pastille, badges, état.
private struct MacroStepRowView: View, Equatable {
    let row: MacroStepRow
    let status: MacroRunMonitor.Status?
    let current: Bool
    /// Bloc choisi : il ne s'allume pas au survol (le fond de la sélection, plus grand, dépassait du contour).
    let selected: Bool
    let onToggle: (Bool) -> Void

    static func == (a: MacroStepRowView, b: MacroStepRowView) -> Bool {
        a.row == b.row && a.status == b.status && a.current == b.current && a.selected == b.selected
    }

    private var indent: CGFloat { CGFloat(row.depth) * 22 }

    var body: some View {
        switch row.kind {
        case .block: blockRow
        case .end: endRow
        }
    }

    private var tint: Color { row.category?.tint ?? .gray }

    private var blockRow: some View {
        HStack(spacing: 8) {
            Text(row.number)
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 24, alignment: .trailing)
            SectionIcon(symbol: row.symbol, tint: tint, size: 24)
            VStack(alignment: .leading, spacing: 2) {
                sentence
                if let note = row.note {
                    Text(note).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                if let reason = failure {
                    Text(reason).font(.system(size: 11)).hoverTint(.red).lineLimit(2)
                }
            }
            Spacer(minLength: 6)
            ForEach(row.badges, id: \.self) { badge in
                BadgeCapsule(badge: badge)
            }
            stateIcon
            // Interrupteur à droite (maquette validée le 28/10), à la place de la case à cocher à gauche.
            Toggle("", isOn: Binding(get: { row.ownEnabled }, set: onToggle))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .help(row.ownEnabled ? String(localized: "Bloc actif : coupe-le pour le sauter sans le supprimer")
                                     : String(localized: "Bloc sauté : rallume-le pour le réactiver"))
        }
        .padding(.leading, indent)
        .frame(minHeight: 32)
        .opacity(row.enabled ? 1 : 0.45)
        .background(stateBackground)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder private var sentence: some View {
        if row.type == .comment {
            Text(row.verb).italic().foregroundStyle(.secondary).lineLimit(2)
        } else {
            HStack(spacing: 6) {
                Text(row.verb).font(.system(size: 14)).lineLimit(1).layoutPriority(1)
                if let value = row.value {
                    Text(value)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(0.12)))
                        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
                }
            }
        }
    }

    private var failure: String? {
        if case .failed(let reason)? = status { return reason }
        if case .warned(let reason)? = status { return reason }
        return nil
    }

    @ViewBuilder private var stateIcon: some View {
        if current {
            Image(systemName: "play.circle.fill").foregroundStyle(.blue).help("En cours")
        } else {
            switch status {
            case .done?:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).help("Fait")
            case .warned?:
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange).help("Fait, avec un avertissement")
            case .failed?:
                Image(systemName: "xmark.circle.fill").foregroundStyle(.red).help("Échec")
            case .cancelled?:
                Image(systemName: "stop.circle.fill").foregroundStyle(.orange).help("Arrêté")
            case .running?:
                Image(systemName: "play.circle.fill").foregroundStyle(.blue).help("En cours")
            case nil:
                EmptyView()
            }
        }
    }

    @ViewBuilder private var stateBackground: some View {
        if current {
            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.blue.opacity(0.13))
        } else if case .failed? = status {
            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.red.opacity(0.10))
        }
    }

    private var endRow: some View {
        HStack(spacing: 6) {
            Image(systemName: row.symbol).foregroundStyle(.secondary)
            Text(row.verb).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .font(.system(size: 11))
        .padding(.leading, indent + 62)
        .padding(.vertical, 1)
        .opacity(row.enabled ? 1 : 0.45)
        .help("Choisis cette ligne pour ajouter des blocs à la fin de la liste, ou glisses-en une ici")
    }

    private var accessibilityText: String {
        var parts = [String(localized: "Bloc \(row.number)"), row.verb]
        if let value = row.value { parts.append(value) }
        if !row.ownEnabled { parts.append(String(localized: "désactivé")) }
        parts += row.badges.map(\.title)
        if current { parts.append(String(localized: "en cours")) }
        if let failure { parts.append(String(localized: "échec : ") + failure) }
        return parts.joined(separator: ", ")
    }
}

/// Badge d'une ligne : petite capsule colorée, l'explication en bulle d'aide.
private struct BadgeCapsule: View {
    let badge: MacroBadge

    var body: some View {
        Label(badge.title, systemImage: badge.symbol)
            .labelStyle(.titleAndIcon)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(badge.tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Capsule().fill(badge.tint.opacity(0.13)))
            .lineLimit(1)
            .fixedSize()                                 // jamais replié lettre par lettre
            .help(badge.help)
    }
}

// MARK: - En-tête : nom, état, raccourci

private struct MacroHeader: View {
    @ObservedObject var model: MacroEditorModel
    let onBack: () -> Void

    private var nameBinding: Binding<String> {
        let editor = model
        return Binding(get: { editor.draft?.name ?? "" }, set: { editor.rename($0) })
    }

    private var triggerBinding: Binding<KeyCombo?> {
        let editor = model
        return Binding(get: { editor.trigger }, set: { editor.setTrigger($0) })
    }

    /// Maquette : ← rond, le nom en grand (champ), les touches du raccourci (clic : en taper d'autres), « Enregistrer »
    /// en bleu. Dessous, seulement ce qui demande d'agir (problème, conflit), puis « Enregistrer clics et touches ».
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                CreatorBackButton(action: onBack)
                TextField("Nom de la macro", text: nameBinding)
                    .textFieldStyle(.plain)
                    .font(.system(size: 22, weight: .bold))
                    .lineLimit(1)
                    .accessibilityLabel("Nom de la macro")
                CaptureField(id: "macro-trigger-\(model.draft?.id.uuidString ?? "")", role: .trigger, combo: triggerBinding,
                             compact: true)
                    .disabled(model.ephemeral)               // exemple de la mesure : jamais enregistré
                    .fixedSize()
                saveButton
            }
            .frame(minHeight: 52)
            if let problem = model.problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .symbolRenderingMode(.multicolor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !model.triggerIssues.isEmpty {
                IssuesView(issues: model.triggerIssues)
            }
            if !model.rows.isEmpty {
                RecordHero(model: model)
            }
        }
    }

    /// Toujours actif (30/10, « le bouton enregistrer ne fonctionne plus ») : chaque changement s'enregistre seul
    /// une demi-seconde après, le bouton restait donc grisé sur « Enregistrée ». Il enregistre ce qui reste et
    /// revient à la liste des macros.
    private var saveButton: some View {
        Button {
            model.saveNow()
            onBack()
        } label: {
            Text("Enregistrer")
        }
        .primaryButton()
        .controlSize(.large)
        .keyboardShortcut("s", modifiers: .command)
        .help("Enregistrer et revenir aux macros (⌘S)")
    }
}

/// ← rond de la maquette : retour aux raccourcis et aux macros (⌘[).
private struct CreatorBackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.backward")
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.white.opacity(0.10)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .menuHover(tint: Color.accentColor, cornerRadius: 22)
        .keyboardShortcut("[", modifiers: .command)
        .help("Revenir aux raccourcis et aux macros (⌘[)")
        .accessibilityLabel("Retour")
    }
}

// MARK: - Bandeau du résultat de l'essai

private struct MacroResultBanner: View {
    @ObservedObject var model: MacroEditorModel
    @ObservedObject var monitor: MacroRunMonitor

    var body: some View {
        Group {
            if model.preparingTest {
                banner(symbol: "arrow.up.forward.app", tint: .blue, text: String(localized: "FL Studio passe devant…"))
            } else if monitor.running {
                banner(symbol: "play.circle.fill", tint: .blue, text: String(localized: "Essai en cours dans FL… Échap pour l'arrêter."))
            } else if let outcome = monitor.outcome {
                outcomeBanner(outcome)
            } else if let notice = model.notice {
                banner(symbol: "info.circle.fill", tint: nil, text: notice, close: { model.notice = nil })
            } else if let refusal = monitor.refusal {
                banner(symbol: "exclamationmark.triangle.fill", tint: .orange, text: String(localized: "Essai non lancé : \(refusal)"),
                       close: { monitor.clear() })
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    @ViewBuilder private func outcomeBanner(_ outcome: MacroOutcome) -> some View {
        switch outcome {
        case .done, .stopped:
            banner(symbol: "checkmark.circle.fill", tint: .green, text: model.outcomeText(outcome), close: { monitor.clear() })
        case .doneWithWarning:
            banner(symbol: "exclamationmark.circle.fill", tint: .orange, text: model.outcomeText(outcome), close: { monitor.clear() })
        case .cancelled:
            banner(symbol: "stop.circle.fill", tint: .orange, text: model.outcomeText(outcome), close: { monitor.clear() })
        case .failed, .failedInBlock:
            let editor = model
            let text = model.outcomeText(outcome)
            let show: (String, () -> Void)? = monitor.failedBlock == nil ? nil
                : (String(localized: "Montrer le bloc"), { editor.showFailedBlock() })
            // « Signaler » : la page Aide, le formulaire prêt avec ce message d'erreur et le journal de l'essai.
            banner(symbol: "xmark.octagon.fill", tint: .red, text: text, action: show,
                   report: { HelpLink.shared.report("Macro « \(editor.draft?.name ?? "?") » : \(text)") },
                   close: { monitor.clear() })
        }
    }

    private func banner(symbol: String, tint: Color?, text: String, action: (String, () -> Void)? = nil,
                        report: (() -> Void)? = nil, close: (() -> Void)? = nil) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint ?? .secondary)
            Text(text)
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if let action {
                Button(action.0, action: action.1).controlSize(.small).onGlassButton()
            }
            if let report {
                Button("Signaler", action: report)
                    .controlSize(.small)
                    .onGlassButton()
                    .help("Écrire à l'équipe : le message d'erreur et le journal de cet essai sont joints, tu les vois avant l'envoi")
            }
            if let close {
                Button(action: close) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Fermer")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .glassSurface(RoundedRectangle(cornerRadius: 16, style: .continuous), tint: tint)
        .accessibilityElement(children: .contain)
    }
}
