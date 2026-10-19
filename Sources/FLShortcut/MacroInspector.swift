// Créateur de macros : inspecteur du bloc choisi, à droite, construit à partir de ses réglages (ParamSpec du
// registre) : capture de touche (le champ d'enregistrement des raccourcis), nombres bornés, choix du preset,
// action de FL du catalogue, endroit d'un clic montré dans FL, « Si le bloc échoue », note.
// Construit seulement pour le bloc choisi ; chaque réglage passe par le brouillon (annulable, enregistré 0,5 s après).
import AppKit
import ApplicationServices
import CoreAudio
import SwiftUI
import UniformTypeIdentifiers

struct MacroInspectorView: View {
    @ObservedObject var model: MacroEditorModel

    var body: some View {
        Group {
            if let block = model.selectedBlock {
                BlockInspector(model: model, block: block)
                    .id(block.id)                         // nouveau bloc : champs neufs
            } else if let row = model.selectedRow, case .end = row.kind {
                hint(symbol: "arrow.turn.left.up", title: row.verb,
                     text: "Les blocs ajoutés maintenant (palette à gauche) vont à la fin de cette liste. Tu peux aussi y glisser une ligne.")
            } else if model.draft != nil {
                hint(symbol: "slider.horizontal.3", title: "Aucun bloc choisi",
                     text: "Choisis une ligne pour la régler. Ajoute des blocs depuis la palette, glisse les lignes pour les ranger ; ⌘D duplique, ⌫ supprime, ⌘Z annule.")
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Autre bloc choisi : ses réglages arrivent en fondu flou, vite (les flèches du clavier le suivent).
        .softSwitch(inspectorKey, quick: true)
    }

    /// Ce que montre l'inspecteur : un bloc, une fin de liste, le conseil, ou rien.
    private var inspectorKey: String {
        if let block = model.selectedBlock { return block.id.uuidString }
        if let row = model.selectedRow, case .end = row.kind { return "fin-\(row.id)" }
        return model.draft != nil ? "conseil" : "vide"
    }

    private func hint(symbol: String, title: String, text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Bloc choisi

private struct BlockInspector: View {
    @ObservedObject var model: MacroEditorModel
    @ObservedObject private var teacher = ClickTeacher.shared
    let block: Block

    private var spec: BlockSpec? { block.body.type.map(BlockRegistry.spec) }

    var body: some View {
        Form {
            Section {
                header
            }
            if let spec {
                Section {
                    if spec.params.filter({ $0.kind.editable }).isEmpty {
                        noSettings
                    } else {
                        ForEach(spec.params.filter { $0.kind.editable }, id: \.id) { param in
                            control(param)
                        }
                    }
                } header: {
                    Text("Réglages")
                }
            } else {
                Section {
                    Text("Ce bloc vient d'une version plus récente de FL Shortcuts. Il est gardé tel quel, mais la macro ne tourne pas tant qu'il est là : mets l'app à jour, ou supprime-le.")
                        .font(.system(size: 12))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let row = model.selectedRow, !row.badges.isEmpty {
                Section {
                    ForEach(row.badges, id: \.self) { badge in
                        Label(badge.help, systemImage: badge.symbol)
                            .font(.system(size: 12))
                            .foregroundStyle(badge.tint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } header: {
                    Text("À savoir")
                }
            }
            Section {
                Toggle("Bloc actif", isOn: Binding(get: { block.enabled }, set: { model.setEnabled(block.id, $0) }))
                Picker("Si le bloc échoue", selection: Binding(get: { block.onFailure }, set: { policy in
                    model.updateBlock(block.id, key: "onFailure") { $0.onFailure = policy }
                })) {
                    Text("Arrêter la macro").tag(FailurePolicy.stop)
                    Text("Continuer").tag(FailurePolicy.keepGoing)
                }
                TextField("Note", text: Binding(get: { block.note ?? "" }, set: { text in
                    let clean = String(text.prefix(MacroValidation.maxNoteLength))
                    model.updateBlock(block.id, key: "note", actionName: "Modifier la note") {
                        $0.note = clean.isEmpty ? nil : clean
                    }
                }), prompt: Text("Pour toi (facultatif)"))
            } header: {
                Text("Bloc")
            }
        }
        .formStyle(.grouped)
        .glassListBackground()
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            SectionIcon(symbol: spec?.symbol ?? "questionmark.square.dashed", tint: spec?.category.tint ?? .gray, size: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(spec?.label ?? "Bloc inconnu").font(.headline)
                if let aide = spec?.aide {
                    Text(aide)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var noSettings: some View {
        switch block.body {
        case .menuBar(let titles):
            MenuBarField(titles: titles) { path in
                setBody(key: "titles") { $0 = .menuBar(titles: path) }
            }
        case .selectInput:
            VStack(alignment: .leading, spacing: 6) {
                Text(MacroSpots.loadPath(.input) != nil
                     ? "L'entrée « 1 » est retenue sur ce Mac (montrée une fois)."
                     : "Pas encore montrée : la première fois, une bulle te demande de cliquer sur « (none) » puis sur l'entrée « 1 ».")
                    .font(.system(size: 12))
                    .fixedSize(horizontal: false, vertical: true)
                if MacroSpots.loadPath(.input) != nil {
                    Button("Réapprendre l'entrée") {
                        UserDefaults.standard.removeObject(forKey: MacroSpots.PathKind.input.rawValue)
                        model.refreshLearnedState()
                    }
                    .secondaryButton()
                }
            }
        case .soundCard:
            SoundCardField()
        case .organize:
            Text("Ouvre l'Organiser sur la page de FL qui est devant (Channel rack, Mixer ou Playlist). Les couleurs, dégradés et "
                 + "icônes de chaque famille se règlent dans sa fenêtre et y restent gardés. macOS demande une fois "
                 + "l'autorisation « Audio système » : seul le son de FL est écouté, rien n'est enregistré.")
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
        default:
            Text("Rien à régler.").foregroundStyle(.secondary)
        }
    }

    // MARK: Réglages (un contrôle par ParamSpec)

    @ViewBuilder private func control(_ p: ParamSpec) -> some View {
        switch (block.body, p.id) {
        case (.key(let k, _), "key"):
            LabeledContent(p.label) { keyField(k.combo) }
        case (.key(_, let n), "times"), (.menuKey(_, let n), "times"):
            LabeledContent(p.label) { countField(n, range: 1...20, key: "times") }
        case (.repeatCount(let n, _), "count"):
            LabeledContent(p.label) { countField(n, range: 1...MacroValidation.maxRepeat, key: "count") }
        case (.menuLetters(let l, _), "letters"):
            lettersField(p.label, l, max: 8, hint: "Lettres soulignées du menu ouvert (F de File…), dans l'ordre.")
        case (.trackMenu(let l, _, _, _), "letters"):
            trackMenuPicker(p.label, l)
        case (.menuLetters(_, let e), "finalEnter"):
            enterPicker(p.label, e, allowNever: true)
        case (.trackMenu(let l, _, _, let e), "finalEnter"):
            // Élément de la liste : Entrée déjà réglée pour lui. Seulement pour « Autre ».
            if MacroTemplates.trackMenuChoice(l) == nil { enterPicker(p.label, e, allowNever: false) }
        case (.menuKey(let k, _), "menuKey"):
            menuKeyPicker(p.label, k)
        case (.click(let t, _), "target"):
            clickTarget(t)
        case (.click(_, let b), "button"):
            buttonPicker(p.label, b)
        case (.drag(let from, let to), "from"):
            dragField(from, to)
        case (.delay(let ms), "ms"):
            LabeledContent(p.label) { msField(ms) }
        case (.delay, "wait"), (.waitWindow, "wait"), (.waitWindowClose, "wait"):
            waitPicker(block.body)
        case (.waitWindow(_, let ms), "timeoutMs"), (.waitWindowClose(_, let ms), "timeoutMs"):
            LabeledContent("Au plus") { secondsField(ms) }
        case (.chooseFile(let path), "path"), (.dropFile(let path), "path"):
            fileField(path)
        case (.flAction(let key, _), "action"):
            actionPicker(key)
        case (.flAction(let key, let fallback), "fallback"):
            fallbackField(key, fallback)
        case (.openPage(let page), "page"):
            pagePicker(page)
        case (.pageOption(let id, _), "option"):
            pageOptionPicker(id)
        case (.pageOption(let id?, let name), "name"):
            // Seulement pour l'option qui demande une valeur : la ligne arrive en poussant les réglages du dessous.
            if let field = PageOptions.field(of: id) {
                pageOptionValue(field, id: id, value: name)
                    .transition(Motion.transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity)))
            }
        case (.pageOption, "name"):
            EmptyView()
        case (.stop(let m), "message"):
            TextField(p.label, text: textBinding(m ?? "", max: MacroValidation.maxNoteLength) { text in
                setBody(key: "message") { $0 = .stop(message: text.isEmpty ? nil : text) }
            }, prompt: Text("Facultatif"))
        case (.comment(let t), "text"):
            TextField(p.label, text: textBinding(t, max: 200) { text in
                setBody(key: "text") { $0 = .comment(text) }
            }, axis: .vertical)
            .lineLimit(2...5)
        case (.nameColor(let name, _, let fade, _), "name"):
            // Coupé en points de code, comme le compte le script de FL (un « é » décomposé en vaut deux).
            TextField(p.label, text: Binding(get: { name ?? "" }, set: { text in
                let cut = String(String.UnicodeScalarView(text.unicodeScalars.prefix(NameColorPayload.maxNameScalars)))
                setBody(key: "name") { body in
                    if case .nameColor(_, let c, let f, let i) = body {
                        body = .nameColor(name: cut.isEmpty ? nil : cut, color: c, fade: f, icon: i)
                    }
                }
            }), prompt: Text(fade == nil ? "Kick, Lead, Voix… (facultatif)" : "Pas de nom pour un dégradé"))
            .disabled(fade != nil)
        case (.nameColor(_, let color, let fade, _), "color"):
            VStack(alignment: .leading, spacing: 10) {
                NameColorField(color: color) { newColor in
                    setBody(key: "color") { body in
                        if case .nameColor(let n, _, let f, let i) = body {
                            body = .nameColor(name: n, color: newColor, fade: newColor == nil ? nil : f, icon: i)
                        }
                    }
                }
                if let color {
                    // « Gradient color… » de FL : de First à Last sur les pistes ou canaux sélectionnés (2 au moins).
                    Toggle("Dégradé sur les pistes sélectionnées", isOn: Binding(get: { fade != nil }, set: { on in
                        setBody(key: "fade") { body in
                            guard case .nameColor(let n, let c?, _, let i) = body else { return }
                            // Dégradé : ni nom ni icône (plusieurs pistes).
                            body = on ? .nameColor(name: nil, color: c, fade: GradientField.defaultLast(for: c), icon: nil)
                                      : .nameColor(name: n, color: c, fade: nil, icon: i)
                        }
                    }))
                    .help("Comme « Gradient color… » de FL : de la première couleur (First) à la dernière (Last), sur les pistes ou les canaux sélectionnés (au moins 2). Le nom ne change pas.")
                    if let fade {
                        GradientField(first: color, last: fade) { first, last in
                            setBody(key: "fade") { body in
                                if case .nameColor(_, _, _, let i) = body {
                                    body = .nameColor(name: nil, color: first, fade: last, icon: i)
                                }
                            }
                        }
                    }
                }
            }
        case (.nameColor(_, _, let fade, let icon), "icon"):
            // Posée par la fenêtre de FL (F2) : un seul élément à la fois, donc pas avec un dégradé.
            VStack(alignment: .leading, spacing: 6) {
                FLIconField(icon: icon) { picked in
                    setBody(key: "icon") { body in
                        if case .nameColor(let n, let c, let f, _) = body {
                            body = .nameColor(name: n, color: c, fade: f, icon: picked)
                        }
                    }
                }
                .disabled(fade != nil)
                Text(fade != nil ? "Pas d'icône avec un dégradé (FL la pose sur un seul élément)."
                                 : "Posée par la fenêtre de FL (F2). La première fois, montre une fois le bouton de l'icône.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        default:
            Text("Réglage disponible dans une prochaine version.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    /// Modifie le corps du bloc (annulable ; `key` regroupe les frappes d'un même champ).
    private func setBody(key: String = "body", _ change: (inout BlockBody) -> Void) {
        model.updateBlock(block.id, key: key) { b in change(&b.body) }
    }

    private func menuKeyPicker(_ label: String, _ current: MenuKey) -> some View {
        let binding = Binding<MenuKey>(get: { current }, set: { key in
            setBody(key: "menuKey") { body in
                if case .menuKey(_, let n) = body { body = .menuKey(key, times: n) }
            }
        })
        return Picker(label, selection: binding) {
            ForEach(MenuKey.allCases, id: \.self) { key in
                Text(key.symbol).tag(key)
            }
        }
    }

    private func buttonPicker(_ label: String, _ current: MouseButton) -> some View {
        let binding = Binding<MouseButton>(get: { current }, set: { button in
            setBody(key: "button") { body in
                if case .click(let t, _) = body { body = .click(t, button: button) }
            }
        })
        return Picker(label, selection: binding) {
            Text("Gauche").tag(MouseButton.left)
            Text("Droit").tag(MouseButton.right)
        }
        .pickerStyle(.segmented)
    }

    /// Ce qu'attend le bloc « Attendre » : un seul bloc pour toutes les attentes, le choix change son genre (boîte
    /// ou menu qui s'ouvre ou se ferme, ou temps fixe), le délai est gardé quand il a un sens.
    private enum WaitChoice: Hashable { case dialogOpen, dialogClose, menuOpen, menuClose, fixed }

    private func waitPicker(_ body: BlockBody) -> some View {
        let current: WaitChoice
        switch body {
        case .waitWindow(.dialog, _): current = .dialogOpen
        case .waitWindowClose(.dialog, _): current = .dialogClose
        case .waitWindow(.menu, _): current = .menuOpen
        case .waitWindowClose(.menu, _): current = .menuClose
        default: current = .fixed
        }
        let binding = Binding<WaitChoice>(get: { current }, set: { choice in
            guard choice != current else { return }
            setBody(key: "wait") { b in
                var timeout = 4_000
                if case .waitWindow(_, let t) = b { timeout = t }
                if case .waitWindowClose(_, let t) = b { timeout = t }
                switch choice {
                case .dialogOpen: b = .waitWindow(.dialog, timeoutMs: timeout)
                case .dialogClose: b = .waitWindowClose(.dialog, timeoutMs: max(timeout, 8_000))
                case .menuOpen: b = .waitWindow(.menu, timeoutMs: timeout)
                case .menuClose: b = .waitWindowClose(.menu, timeoutMs: timeout)
                case .fixed: b = .delay(ms: 300)
                }
            }
        })
        return Picker("Attendre", selection: binding) {
            Text("qu'une boîte de FL s'ouvre").tag(WaitChoice.dialogOpen)
            Text("que la boîte se ferme").tag(WaitChoice.dialogClose)
            Text("qu'un menu de FL s'ouvre").tag(WaitChoice.menuOpen)
            Text("que le menu se ferme").tag(WaitChoice.menuClose)
            Divider()
            Text("un temps fixe (à éviter)").tag(WaitChoice.fixed)
        }
    }

    private func textBinding(_ value: String, max: Int, _ set: @escaping (String) -> Void) -> Binding<String> {
        Binding(get: { value }, set: { set(String($0.prefix(max))) })
    }

    // MARK: Touche

    /// Touche capturée (raccourci compris : ⌘A…), et ⌘ ⌥ ⌃ ⇧ à cocher : un raccourci que macOS garde pour lui se
    /// règle quand même (touche seule, puis modificateurs).
    private func keyField(_ combo: KeyCombo) -> some View {
        VStack(alignment: .trailing, spacing: 6) {
            CaptureField(id: "macro-block-\(block.id)", role: .target, combo: Binding(get: { combo }, set: { new in
                guard let new else { return }               // une touche est obligatoire : ⌫ ne l'efface pas
                setKey(new)
            }))
            HStack(spacing: 4) {
                modifierToggle("⌘", "Commande", \.command, combo)
                modifierToggle("⌥", "Option", \.option, combo)
                modifierToggle("⌃", "Contrôle", \.control, combo)
                modifierToggle("⇧", "Majuscule", \.shift, combo)
            }
        }
    }

    private func modifierToggle(_ symbol: String, _ name: String, _ path: WritableKeyPath<KeyCombo, Bool>,
                                _ combo: KeyCombo) -> some View {
        Toggle(symbol, isOn: Binding(get: { combo[keyPath: path] }, set: { on in
            var new = combo
            new[keyPath: path] = on
            if let why = Store.shared.forbiddenReason(new) {
                Dialogs.inform("Touche interdite", "\(new.display) ne peut pas être envoyée à FL : \(why).")
                return
            }
            setKey(new)
        }))
        .toggleStyle(.button)
        .font(.system(size: 13, weight: .medium))
        .help("\(name) avec la touche")
        .accessibilityLabel(name)
    }

    private func setKey(_ new: KeyCombo) {
        setBody(key: "key") { body in
            if case .key(var ref, let n) = body {
                ref.combo = new
                ref.char = nil
                body = .key(ref, times: n)
            }
        }
    }

    // MARK: Nombres bornés

    private func countField(_ n: Int, range: ClosedRange<Int>, key: String) -> some View {
        Stepper(value: Binding(get: { n }, set: { v in
            let value = min(max(v, range.lowerBound), range.upperBound)
            setBody(key: key) { body in
                switch body {
                case .key(let k, _): body = .key(k, times: value)
                case .menuKey(let k, _): body = .menuKey(k, times: value)
                case .repeatCount(_, let blocks): body = .repeatCount(value, blocks)
                default: break
                }
            }
        }), in: range) {
            Text(n == 1 ? "1 fois" : "\(n) fois").monospacedDigit()
        }
    }

    private func msField(_ ms: Int) -> some View {
        let range = 0...MacroValidation.maxDelayMs
        let binding = Binding<Int>(get: { ms }, set: { v in
            let value = min(max(v, range.lowerBound), range.upperBound)
            setBody(key: "ms") { if case .delay = $0 { $0 = .delay(ms: value) } }
        })
        return HStack(spacing: 6) {
            TextField("", value: binding, format: .number)
                .frame(width: 70)
                .multilineTextAlignment(.trailing)
            Text("ms").foregroundStyle(.secondary)
            Stepper("", value: binding, in: range, step: 50).labelsHidden()
        }
    }

    /// Délai d'attente en secondes (0,1 à 120 s), gardé en millisecondes.
    private func secondsField(_ ms: Int) -> some View {
        let binding = Binding<Double>(get: { Double(ms) / 1000 }, set: { v in
            let value = min(max(Int((v * 1000).rounded()), 100), MacroValidation.maxWaitMs)
            setBody(key: "timeout") { body in
                switch body {
                case .waitWindow(let k, _): body = .waitWindow(k, timeoutMs: value)
                case .waitWindowClose(let k, _): body = .waitWindowClose(k, timeoutMs: value)
                default: break
                }
            }
        })
        return HStack(spacing: 6) {
            TextField("", value: binding, format: .number.precision(.fractionLength(0...1)))
                .frame(width: 60)
                .multilineTextAlignment(.trailing)
            Text("s").foregroundStyle(.secondary)
            Stepper("", value: binding, in: 0.1...Double(MacroValidation.maxWaitMs / 1000), step: 0.5).labelsHidden()
        }
    }

    // MARK: Lettres et Entrée

    /// Élément du menu de la piste choisi dans une liste ; « Autre » vide les lettres et montre le champ dessous.
    private func trackMenuPicker(_ label: String, _ letters: [Character]) -> some View {
        let other = "other"
        let current = MacroTemplates.trackMenuChoice(letters)?.id ?? other
        return VStack(alignment: .leading, spacing: 6) {
            Picker(label, selection: Binding(get: { current }, set: { id in
                let choice = MacroTemplates.trackMenuChoices.first { $0.id == id }
                setBody(key: "letters") { body in
                    guard case .trackMenu(_, _, let target, let e) = body else { return }
                    if let choice {
                        body = .trackMenu(letters: choice.letters, labels: choice.labels, target: target, finalEnter: choice.enter)
                    } else {
                        body = .trackMenu(letters: [], labels: [], target: target, finalEnter: e == .never ? .ifNeeded : e)
                    }
                }
            })) {
                ForEach(MacroTemplates.trackMenuChoices) { Text($0.name).tag($0.id) }
                Divider()
                Text("Autre (lettres soulignées)…").tag(other)
            }
            if current == other {
                lettersField("Lettres", letters, max: 3,
                             hint: "Lettres soulignées dans le menu de la piste de FL : les sous-menus (F de File), puis l'élément (O de Open…).")
            }
        }
    }

    private func lettersField(_ label: String, _ letters: [Character], max: Int, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField(label, text: Binding(get: { String(letters).uppercased() }, set: { text in
                let clean = Array(text.lowercased().filter { ("a"..."z").contains($0) }.prefix(max))
                setBody(key: "letters") { body in
                    switch body {
                    case .menuLetters(_, let e): body = .menuLetters(clean, finalEnter: e)
                    // Nouvelles lettres : les libellés d'origine (File › Open…) ne correspondent plus.
                    case .trackMenu(_, _, let target, let e): body = .trackMenu(letters: clean, labels: [], target: target, finalEnter: e)
                    default: break
                    }
                }
            }), prompt: Text("F O"))
            Text(hint).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func enterTag(_ e: EnterPolicy) -> String {
        switch e {
        case .learned: return "learned"
        case .always: return "always"
        case .ifNeeded: return "ifNeeded"
        case .never: return "never"
        }
    }

    private func enterPicker(_ label: String, _ current: EnterPolicy, allowNever: Bool) -> some View {
        Picker(label, selection: Binding(get: { enterTag(current) }, set: { tag in
            let policy: EnterPolicy
            switch tag {
            case "always": policy = .always
            case "never": policy = .never
            case "learned": policy = current
            default: policy = .ifNeeded
            }
            setBody(key: "finalEnter") { body in
                switch body {
                case .menuLetters(let l, _): body = .menuLetters(l, finalEnter: policy)
                case .trackMenu(let l, let labels, let t, _): body = .trackMenu(letters: l, labels: labels, target: t, finalEnter: policy)
                default: break
                }
            }
        })) {
            if allowNever { Text("Jamais").tag("never") }
            Text("Si le menu reste ouvert").tag("ifNeeded")
            Text("Toujours").tag("always")
            if case .learned = current { Text("Apprise au premier passage").tag("learned") }
        }
    }

    // MARK: Clic

    private func targetKind(_ t: ClickTarget) -> String {
        switch t {
        case .flWindow, .openMenu, .button, .named, .cursorXWindowY, .toLearn: return "learned"
        case .track: return "track"
        case .lastClick: return "lastClick"
        case .startCursor: return "startCursor"
        }
    }

    @ViewBuilder private func clickTarget(_ t: ClickTarget) -> some View {
        Picker("Où", selection: Binding(get: { targetKind(t) }, set: { kind in
            guard kind != targetKind(t) else { return }
            let target: ClickTarget
            switch kind {
            case "track": target = .track(dx: 0, dy: 0)
            case "lastClick": target = .lastClick(dx: 0, dy: 0)
            case "startCursor": target = .startCursor(dx: 0, dy: 0)
            default: target = .toLearn
            }
            setBody(key: "target") { if case .click(_, let b) = $0 { $0 = .click(target, button: b) } }
        })) {
            Text("Endroit montré dans FL").tag("learned")
            Text("Sur la piste visée").tag("track")
            Text("Près du clic précédent").tag("lastClick")
            Text("Près du curseur au départ").tag("startCursor")
        }
        switch t {
        case .flWindow, .openMenu, .button, .named, .cursorXWindowY, .toLearn:
            learnedSpot(t)
        case .track(let dx, let dy), .lastClick(let dx, let dy), .startCursor(let dx, let dy):
            offsetFields(t, dx: dx, dy: dy)
        }
    }

    private func learnedSpot(_ t: ClickTarget) -> some View {
        let learning = teacher.activeBlock == block.id
        let text: String
        switch t {
        case .flWindow(_, _, _, _, let title?):
            text = "Retenu dans la fenêtre du plugin « \(title.displaySafe(max: 40)) » : le clic la retrouve où qu'elle soit "
                + "et attend qu'elle s'ouvre. Si elle change de taille, montre-le de nouveau."
        case .flWindow(_, _, _, let size?, _):
            text = "Retenu dans la fenêtre de FL de \(Int(size.width)) × \(Int(size.height)) (fenêtre principale, réglages, "
                + "boîte…) : le clic attend qu'elle s'ouvre. Si elle change de taille, montre-le de nouveau."
        case .flWindow:
            text = "Retenu par rapport à la fenêtre de FL."
        case .openMenu:
            text = "Retenu dans le menu de FL ouvert par le clic précédent : le clic attend que ce menu s'ouvre."
        case .button:
            text = "Bouton retrouvé à son image dans la fenêtre de FL, même s'il a bougé. L'écran n'est lu qu'à ce "
                + "moment-là, dans cette fenêtre."
        case .named(let spot):
            text = "Bouton retrouvé par son nom « \(spot.label.displaySafe(max: 30)) » dans la fenêtre de FL, même s'il a "
                + "bougé. L'écran n'est lu qu'à ce moment-là, dans cette fenêtre ; sans l'autorisation, à sa place."
        case .cursorXWindowY:
            text = "Ancienne position apprise (colonne du curseur)."
        default:
            text = "Pas encore montré : la macro ne tourne pas tant que l'endroit n'est pas montré."
        }
        return VStack(alignment: .leading, spacing: 6) {
            Text(text).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                if learning {
                    ProgressView().controlSize(.small)
                    Button("Annuler") { teacher.cancel("Annulé.") }.secondaryButton()
                } else {
                    Button {
                        // Bouton suivi à son image : son image est reprise en le montrant de nouveau.
                        if case .button = t { teach(visual: true) } else { teach() }
                    } label: {
                        Label("Montrer dans FL…", systemImage: "hand.point.up.left")
                    }
                    .secondaryButton()
                    .help("FL passe devant : clique une fois à l'endroit voulu (le clic agit aussi dans FL). Échap annule.")
                }
            }
            if ScreenLook.available, canFollow(t) {
                Toggle("Retrouver ce bouton s'il bouge", isOn: Binding(get: {
                    switch t {
                    case .button, .named: return true
                    default: return false
                    }
                }, set: { on in follow(on, t) }))
                .disabled(learning)
                .help("Pour un bouton qui change de place (une piste du Mixer, le « + » du Channel rack…) : il est "
                    + "cherché par son nom (« Insert 1 »), ou à son image s'il n'en a pas, dans la fenêtre au moment du "
                    + "clic. Demande l'autorisation « Enregistrement de l'écran ».")
            }
            if let message = teacher.message, teacher.lastBlock == block.id {
                Text(message).font(.system(size: 11)).foregroundStyle(learning ? Color.accentColor : Color.secondary)
            }
        }
    }

    /// Clic dans une fenêtre de FL (taille retenue) : son bouton peut être retrouvé à son image.
    private func canFollow(_ t: ClickTarget) -> Bool {
        switch t {
        case .flWindow(_, _, _, .some, _), .button, .named: return true
        default: return false
        }
    }

    /// Option « Retrouver ce bouton s'il bouge » : activée, l'autorisation de lire l'écran est demandée, puis on montre
    /// le bouton dans FL (son image est prise à ce moment-là) ; désactivée, le clic garde sa place, sans image.
    private func follow(_ on: Bool, _ t: ClickTarget) {
        if !on {
            let place: ClickTarget
            switch t {
            case .button(let spot): place = spot.place
            case .named(let spot): place = spot.place
            default: return
            }
            setBody(key: "target") { if case .click(_, let b) = $0 { $0 = .click(place, button: b) } }
            return
        }
        guard ScreenLook.allowed else {
            teacher.say("Autorise FL Shortcuts dans Réglages Système › Confidentialité et sécurité › Enregistrement de "
                        + "l'écran (rouvre l'app si macOS le demande), puis réactive l'option.", for: block.id)
            // Pas encore demandée : la fenêtre de macOS seule (les réglages ouverts en même temps la cachaient).
            if !ScreenLook.requestOnce() { ScreenLook.openSettings() }
            return
        }
        teach(visual: true)
    }

    private func teach(visual: Bool = false) {
        guard let pid = EventTap.shared.currentConfig.flPIDs.first else {
            teacher.say("Ouvre FL Studio, puis recommence.", for: block.id)
            return
        }
        let id = block.id
        let editor: MacroEditorModel = model
        teacher.start(block: id, pid: pid, returnTo: editor.window, visual: visual) { [weak editor] target in
            editor?.updateBlock(id, key: "target", actionName: "Montrer l'endroit du clic") { b in
                if case .click(_, let button) = b.body { b.body = .click(target, button: button) }
            }
        }
    }

    // MARK: Glisser-déposer

    private func dragField(_ from: ClickTarget, _ to: ClickTarget) -> some View {
        let learning = teacher.activeBlock == block.id
        let shown = from != .toLearn && to != .toLearn
        return VStack(alignment: .leading, spacing: 6) {
            if shown {
                LabeledContent("Attraper") { Text(MacroOutline.targetText(from)).foregroundStyle(.secondary) }
                LabeledContent("Lâcher") { Text(MacroOutline.targetText(to)).foregroundStyle(.secondary) }
            }
            Text(shown ? "Retenu par rapport aux fenêtres de FL : la macro attrape et lâche aux mêmes endroits de ces "
                         + "fenêtres. Si l'une change de taille ou de place dans FL, montre-le de nouveau."
                       : "Pas encore montré : fais le glisser-déposer une fois dans FL (reste cliqué, glisse, lâche). "
                         + "La macro ne tourne pas tant qu'il n'est pas montré.")
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                if learning {
                    ProgressView().controlSize(.small)
                    Button("Annuler") { teacher.cancel("Annulé.") }.secondaryButton()
                } else {
                    Button { teachDrag() } label: { Label("Montrer dans FL…", systemImage: "hand.draw") }
                        .secondaryButton()
                        .help("FL passe devant : fais le glisser-déposer une fois (il agit aussi dans FL). Échap annule.")
                }
            }
            if let message = teacher.message, teacher.lastBlock == block.id {
                Text(message).font(.system(size: 11)).foregroundStyle(learning ? Color.accentColor : Color.secondary)
            }
        }
    }

    private func teachDrag() {
        guard let pid = EventTap.shared.currentConfig.flPIDs.first else {
            teacher.say("Ouvre FL Studio, puis recommence.", for: block.id)
            return
        }
        let id = block.id
        let editor: MacroEditorModel = model
        teacher.startDrag(block: id, pid: pid, returnTo: editor.window) { [weak editor] from, to in
            editor?.updateBlock(id, key: "from", actionName: "Montrer le glisser-déposer") { b in
                if case .drag = b.body { b.body = .drag(from: from, to: to) }
            }
        }
    }

    private func offsetFields(_ t: ClickTarget, dx: Double, dy: Double) -> some View {
        func set(_ x: Double, _ y: Double) {
            let cx = min(max(x, -5000), 5000), cy = min(max(y, -5000), 5000)
            setBody(key: "offset") { body in
                guard case .click(let target, let b) = body else { return }
                switch target {
                case .track: body = .click(.track(dx: cx, dy: cy), button: b)
                case .lastClick: body = .click(.lastClick(dx: cx, dy: cy), button: b)
                case .startCursor: body = .click(.startCursor(dx: cx, dy: cy), button: b)
                default: break
                }
            }
        }
        return LabeledContent("Décalage (points)") {
            HStack(spacing: 6) {
                Text("x").foregroundStyle(.secondary)
                TextField("", value: Binding(get: { dx }, set: { set($0, dy) }), format: .number).frame(width: 56)
                Text("y").foregroundStyle(.secondary)
                TextField("", value: Binding(get: { dy }, set: { set(dx, $0) }), format: .number).frame(width: 56)
            }
        }
    }

    // MARK: Preset

    private func fileField(_ path: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "doc").foregroundStyle(.secondary)
                Text(path.isEmpty ? "Aucun preset choisi" : URL(fileURLWithPath: path).lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(path.isEmpty ? Color.secondary : Color.primary)
                Spacer(minLength: 4)
                Button("Choisir…") { choosePreset() }.secondaryButton()
            }
            Text("Un état de piste du Mixer (.fst) dans ton dossier personnel. La boîte « Open » de FL doit être ouverte juste avant (bloc « Attendre une fenêtre »).")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func choosePreset() {
        guard let path = PresetPanel.choose() else { return }
        setBody(key: "path") { body in
            if case .dropFile = body { body = .dropFile(path: path) } else { body = .chooseFile(path: path) }
        }
    }

    // MARK: Action de FL

    private func actionPicker(_ key: String) -> some View {
        let info = FLActions.id(forKey: key).flatMap(FLActions.info)
        let availability = info.map { AppStatus.shared.availability($0.id) }
        return VStack(alignment: .leading, spacing: 4) {
            Picker("Action", selection: Binding(get: { key }, set: { setAction($0) })) {
                ForEach(FLActionInfo.Category.allCases, id: \.self) { category in
                    Section(category.rawValue) {
                        ForEach(FLActions.all.filter { $0.category == category }) { a in
                            Text(a.label).tag(a.key)
                        }
                    }
                }
            }
            if let info {
                Text(info.detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if case .unavailable(let reason)? = availability, !MuteSolo.handlesWithoutLink(key) {
                Text(reason).font(.system(size: 11)).foregroundStyle(.orange)
            }
        }
    }

    /// Nouvelle action : son repli sans lien est choisi tout seul (touche équivalente de FL, menu de la piste pour
    /// l'armement, sinon rien).
    private func setAction(_ key: String) {
        let layout = SystemKeyboardLayout()
        let fallback: ActionFallback
        if key == "armon" {
            fallback = .trackMenuArm
        } else if let id = FLActions.id(forKey: key), let native = AppMode.nativeEquivalent(of: id == 40 ? 3 : id, layout: layout) {
            fallback = .key(KeyRef(native))
        } else {
            fallback = .none
        }
        setBody(key: "action") { $0 = .flAction(key: key, fallback: fallback) }
    }

    @ViewBuilder private func fallbackField(_ key: String, _ fallback: ActionFallback) -> some View {
        switch fallback {
        case .trackMenuArm:
            LabeledContent("Sans lien") {
                Text("Menu de la piste › Arm selected track(s)").font(.system(size: 12))
            }
        case .key(let ref):
            VStack(alignment: .leading, spacing: 4) {
                Text("Sans lien, cette touche de FL :").font(.system(size: 12))
                CaptureField(id: "macro-fallback-\(block.id)", role: .target, combo: Binding(get: { ref.combo }, set: { new in
                    var replacement = ActionFallback.none
                    if let new { replacement = .key(KeyRef(new)) }
                    setBody(key: "fallback") { body in
                        guard case .flAction(let k, _) = body else { return }
                        body = .flAction(key: k, fallback: replacement)
                    }
                }))
                Text("⌫ dans le champ : aucune touche (le bloc demande alors le lien avec FL).")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        case .none where MuteSolo.handlesWithoutLink(key):
            MuteSoloField(key: key, window: model.window) { model.refreshLearnedState() }
        case .none:
            VStack(alignment: .leading, spacing: 4) {
                Text("Sans lien avec FL, ce bloc échoue (aucun équivalent au clavier).")
                    .font(.system(size: 12))
                    .fixedSize(horizontal: false, vertical: true)
                Button("Ajouter une touche de secours") {
                    setBody(key: "fallback") { body in
                        guard case .flAction(let k, _) = body else { return }
                        body = .flAction(key: k, fallback: .key(KeyRef(KeyCombo(keyCode: 49))))
                    }
                }
                .secondaryButton()
            }
        }
    }

    // MARK: Pages de FL

    private func pagePicker(_ page: FLPage?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker("Page", selection: Binding<FLPage?>(get: { page }, set: { new in
                setBody(key: "page") { $0 = .openPage(new) }
            })) {
                if page == nil { Text("À choisir").tag(FLPage?.none) }
                ForEach(FLPage.allCases) { p in
                    Text(p.title).tag(FLPage?.some(p))
                }
            }
            if page == nil {
                Label("Choisis la page de FL à ouvrir : les options de « Cliquer sur… » en dessous viennent d'elle.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Ouverte seulement si elle n'est pas déjà devant (le lien avec FL le sait). Sans le lien : sa touche "
                 + "de FL (F5, F6, F7, F9…), qui la referme si elle est déjà devant.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Seulement les options de la page ouverte au-dessus (et l'option déjà choisie, même remplacée depuis).
    private func pageOptionPicker(_ id: String?) -> some View {
        let layout = SystemKeyboardLayout()
        let page = PageOptions.pageAbove(block.id, in: model.draft?.blocks ?? []) ?? nil
        var options = page.map { PageOptions.options(for: $0, layout: layout) } ?? []
        if let id, !options.contains(where: { $0.id == id }), let old = PageOptions.option(id, layout: layout),
           old.page == page {
            options.append(old)
        }
        let current = options.first { $0.id == id }
        let inPage = options.filter { if case .key = $0.kind { return false }; return true }
        let keys = options.filter { if case .key = $0.kind { return true }; return false }
        return VStack(alignment: .leading, spacing: 4) {
            if let page {
                Picker("Option", selection: Binding<String?>(get: { current?.id }, set: { new in
                    // Une autre sorte de valeur (plugin, numéro, nom) : la valeur repart de zéro.
                    let sameField = new.flatMap(PageOptions.field(of:)) == id.flatMap(PageOptions.field(of:))
                    withAnimation(Motion.quickMorph) {
                        setBody(key: "option") { body in
                            guard case .pageOption(_, let name) = body else { return }
                            body = .pageOption(id: new, name: sameField ? name : "")
                        }
                    }
                })) {
                    if current == nil { Text("À choisir").tag(String?.none) }
                    if !inPage.isEmpty {
                        Section(page.title) {
                            ForEach(inPage) { o in Text(o.label).tag(String?.some(o.id)) }
                        }
                    }
                    if !keys.isEmpty {
                        Section("Raccourcis de FL dans \(page.title)") {
                            ForEach(keys) { o in Text(o.label).tag(String?.some(o.id)) }
                        }
                    }
                }
                if let current, case .action(let key) = current.kind, MuteSolo.handlesWithoutLink(key) {
                    MuteSoloField(key: key, window: model.window) { model.refreshLearnedState() }
                } else if let current {
                    Text(optionDetail(current, layout: layout))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Label(id == nil ? "Choisis l'option à cliquer dans \(page.title)."
                                    : "Cette option n'est pas dans \(page.title) : choisis-en une de cette page.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Label("Choisis d'abord la page dans « Ouvrir une page de FL » juste au-dessus : seules ses options "
                      + "apparaissent ici.", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func optionDetail(_ option: PageOption, layout: KeyboardLayout) -> String {
        switch option.kind {
        case .action:
            return option.id == "mixer.armon"
                ? "Par le lien avec FL ; sans lien : menu de la piste › Arm selected track(s)."
                : "Par le lien avec FL ; sans lien : sa touche de FL, si elle existe."
        case .key(let combo):
            return "Touche de FL : \(combo.displayName(layout: layout))."
        case .addMenu(let item):
            return "Par le menu Add › \(item) de FL (barre des menus de macOS), sans clic : choisis le plugin ci-dessous."
        case .channelToggle(let solo):
            return "Le \(solo ? "solo" : "mute") du canal est basculé par le lien avec FL : ni souris, ni touche. Sans "
                + "le lien : la touche 1 à 0 de FL\(solo ? " avec ⌘" : ""), jusqu'au canal 10."
        case .rename:
            return "La piste sélectionnée dans le Mixer prend ce nom, par le lien avec FL. Sans le lien : la fenêtre "
                + "« Renommer » de FL (F2), le nom tapé, puis Entrée."
        }
    }

    /// Valeur de l'option : le plugin (liste lue dans FL), le numéro du canal ou le nouveau nom.
    @ViewBuilder private func pageOptionValue(_ field: PageOption.Field, id: String, value: String) -> some View {
        let set: (String) -> Void = { text in
            setBody(key: "name") { body in
                guard case .pageOption(let i, _) = body else { return }
                body = .pageOption(id: i, name: text)
            }
        }
        let problem = value.isEmpty ? nil : PageOptions.valueProblem(field, value)
        VStack(alignment: .leading, spacing: 4) {
            switch field {
            case .plugin:
                PluginField(item: id.hasSuffix(".addEffect") ? "Effect" : "Channel", value: value, set: set)
            case .channel:
                TextField("Canal", text: Binding(get: { value }, set: { text in
                    set(String(text.filter { $0.isASCII && $0.isNumber }.prefix(3)))
                }), prompt: Text("1 à \(PageOptions.maxChannel)"))
                Text("Numéro du canal dans le Channel rack (1 = le premier en haut).")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            case .name:
                TextField("Nouveau nom", text: Binding(get: { value }, set: { text in
                    set(String(String.UnicodeScalarView(text.unicodeScalars.prefix(NameColorPayload.maxNameScalars))))
                }), prompt: Text("Kick, Lead, Voix…"))
            }
            if let problem {
                Label(problem.prefix(1).uppercased() + problem.dropFirst(), systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// « Carte son branchée » : la carte à prendre (automatique, ou celle choisie, retenue sur ce Mac), la sortie du Mac en
/// ce moment, et un essai tout de suite, sans lancer la macro. CoreAudio n'est lu qu'à l'affichage et sur demande.
private struct SoundCardField: View {
    @State private var devices: [AudioDeviceInfo] = []
    @State private var current: AudioObjectID?
    @State private var chosen = UserDefaults.standard.string(forKey: SoundCard.chosenKey) ?? ""
    @State private var result: (ok: Bool, text: String)?
    @State private var trying = false

    private var auto: AudioDeviceInfo? {
        SoundCard.choose(devices, preferredUID: UserDefaults.standard.string(forKey: SoundCard.preferredKey))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Carte son", selection: Binding(get: { chosen }, set: { uid in
                chosen = uid
                if uid.isEmpty {
                    UserDefaults.standard.removeObject(forKey: SoundCard.chosenKey)
                } else {
                    UserDefaults.standard.set(uid, forKey: SoundCard.chosenKey)
                }
                result = nil
            })) {
                Text(auto.map { "Automatique (\($0.name.displaySafe(max: 30)))" } ?? "Automatique (aucune carte branchée)").tag("")
                ForEach(SoundCard.selectable(devices)) { d in
                    Text(d.name.displaySafe(max: 40) + (d.isExternal ? "" : " (du Mac)")).tag(d.uid)
                }
                if !chosen.isEmpty, !devices.contains(where: { $0.uid == chosen }) {
                    Text("Carte choisie, pas branchée").tag(chosen)
                }
            }
            Text("Sortie du Mac en ce moment : " + (devices.first { $0.id == current }?.name.displaySafe(max: 40) ?? "inconnue"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button("Essayer maintenant", action: tryNow)
                    .secondaryButton()
                    .disabled(trying)
                Button { reload() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .help("Relire les cartes branchées")
            }
            if let result {
                Label(result.text, systemImage: result.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(result.ok ? Color.green : Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("La carte devient la sortie et l'entrée du Mac. Une seule fois, dans FL › Options › Audio settings : "
                 + "Output sur « Default audio device » et Input sur « Default input device » ; FL suit alors la carte "
                 + "tout seul.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear(perform: reload)
    }

    private func reload() {
        devices = SoundCard.list()
        current = SoundCard.currentDefault()
    }

    /// Le bloc tout seul, tout de suite : la réponse dit ce que macOS a fait.
    private func tryNow() {
        trying = true
        DispatchQueue.global(qos: .userInitiated).async {
            let outcome = SoundCard.apply()
            DispatchQueue.main.async {
                trying = false
                switch outcome {
                case .done(let name, let input):
                    result = (true, (input ? "Sortie et entrée du Mac : " : "Sortie du Mac : ") + name.displaySafe(max: 40))
                case .noCard:
                    result = (false, "Aucune carte son branchée trouvée (USB, Thunderbolt…) : choisis-la dans la liste.")
                case .failed(let why):
                    result = (false, why.prefix(1).uppercased() + why.dropFirst())
                }
                reload()
            }
        }
    }
}

/// Plugin à ajouter : les favoris du menu Add › Channel ou Effect de FL, puis tous les plugins installés (Plugin
/// database de FL) ; sinon le nom à écrire. Un plugin hors des favoris y est ajouté (FLPluginDatabase).
private struct PluginField: View {
    let item: String
    let value: String
    let set: (String) -> Void
    @ObservedObject private var list: FLPluginList
    @State private var typing = false
    @State private var problem: String?

    private static let installedTag = "installed:"

    init(item: String, value: String, set: @escaping (String) -> Void) {
        self.item = item
        self.value = value
        self.set = set
        _list = ObservedObject(wrappedValue: FLPluginList.forItem(item))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if case .loaded(let names) = list.state, !typing {
                HStack(spacing: 6) {
                    Picker("Plugin", selection: Binding(get: { value }, set: { choose($0, names: names) })) {
                        if value.isEmpty { Text("À choisir").tag("") }
                        if !value.isEmpty, !names.contains(value) { Text(value).tag(value) }
                        ForEach(Array(FLPluginList.groups(names).enumerated()), id: \.offset) { _, group in
                            Section(group.title.map { "Favoris · \($0)" } ?? "Favoris du menu Add") {
                                ForEach(group.names, id: \.self) { name in
                                    Text(group.title == nil ? name
                                         : PageOptions.pluginPath(name).dropFirst().joined(separator: PageOptions.pathSeparator))
                                        .tag(name)
                                }
                            }
                        }
                        ForEach(FLPluginList.formats(list.installed), id: \.format) { format in
                            Section("Tous les plugins · \(format.format)") {
                                ForEach(format.items, id: \.index) { entry in
                                    Text(entry.name).tag(Self.installedTag + String(entry.index))
                                }
                            }
                        }
                    }
                    reloadButton
                }
                if let problem {
                    Text(problem).foregroundStyle(.orange).font(.system(size: 11))
                } else if value.hasPrefix(FLPluginDatabase.folderName + PageOptions.pathSeparator), !names.contains(value) {
                    Text("Ajouté à tes favoris de FL (Add › \(item) › \(FLPluginDatabase.folderName)) pour que la macro le "
                         + "choisisse sans souris. Si FL est ouvert, quitte-le et rouvre-le une fois pour qu'il le voie.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button("Écrire le nom moi-même") { withAnimation(Motion.quickMorph) { typing = true } }
                    .buttonStyle(.link)
                    .font(.system(size: 11))
            } else {
                HStack(spacing: 6) {
                    TextField("Plugin", text: Binding(get: { value }, set: { set(String($0.prefix(PageOptions.maxName))) }),
                              prompt: Text(item == "Effect" ? "Fruity Limiter, Pro-Q 3…" : "Serum, FLEX, Sytrus…"))
                    if list.state == .loading {
                        ProgressView().controlSize(.small)
                    } else {
                        reloadButton
                    }
                }
                Group {
                    if typing {
                        Button("Choisir dans la liste de FL") { withAnimation(Motion.quickMorph) { typing = false } }
                            .buttonStyle(.link)
                    } else if case .unavailable(let why) = list.state {
                        Text(why).foregroundStyle(.secondary)
                    } else {
                        Text("Écrit exactement comme dans le menu Add › \(item) de FL.").foregroundStyle(.secondary)
                    }
                }
                .font(.system(size: 11))
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { list.loadIfNeeded() }
    }

    /// Un favori du menu : tel quel. Un plugin installé : son favori s'il en a un, sinon ajouté aux favoris de FL.
    private func choose(_ choice: String, names: [String]) {
        problem = nil
        guard choice.hasPrefix(Self.installedTag), let i = Int(choice.dropFirst(Self.installedTag.count)),
              list.installed.indices.contains(i) else {
            set(choice)
            return
        }
        let plugin = list.installed[i]
        if let favorite = names.first(where: { PageOptions.pluginPath($0).last == plugin.name }) {
            set(favorite)
        } else if let path = FLPluginDatabase.addFavorite(plugin, kind: list.kind, root: FLPluginDatabase.root()) {
            set(path)
        } else {
            problem = "Impossible de l'ajouter aux favoris de FL (dossier Plugin database de FL protégé ?) : écris le nom "
                + "d'un plugin du menu Add."
        }
    }

    private var reloadButton: some View {
        Button { list.reload() } label: { Image(systemName: "arrow.clockwise") }
            .buttonStyle(.borderless)
            .help("Relire la liste dans FL (plugins ajoutés depuis)")
    }
}

/// Plugins du menu Add › Channel ou Effect de FL (barre des menus de macOS, Accessibilité, sans clic), et tous les
/// plugins installés (Plugin database de FL, sur le disque), pour « Cliquer sur… ». Lus à la première demande, relus
/// avec le bouton ; jamais journalisés.
final class FLPluginList: ObservableObject {
    enum State: Equatable {
        case loading
        /// Favoris du menu Add (peut être vide quand seuls les plugins installés sont connus).
        case loaded([String])
        case unavailable(String)
    }

    static let channel = FLPluginList(item: "Channel")
    static let effect = FLPluginList(item: "Effect")
    static func forItem(_ item: String) -> FLPluginList { item == "Effect" ? effect : channel }

    let item: String
    @Published private(set) var state: State?
    /// Tous les plugins installés de cette sorte (Plugin database de FL).
    @Published private(set) var installed: [FLPluginDatabase.Plugin] = []

    var kind: FLPluginDatabase.Kind { item == "Effect" ? .effects : .generators }

    private init(item: String) { self.item = item }

    func loadIfNeeded() {
        if state == nil || state == .unavailable(Self.flClosed) { reload() }
    }

    func reload() {
        guard state != .loading else { return }
        let trusted = AXIsProcessTrusted()
        let pid = trusted ? OrganizerEnvironment.flPID() : nil
        state = .loading
        let path = ["Add", item]
        let kind = self.kind
        DispatchQueue.global(qos: .userInitiated).async {
            let installed = FLPluginDatabase.installed(kind, root: FLPluginDatabase.root())
            let names = pid.map { pid in
                MenuBarAX.entries(pid: pid, under: path).map { $0.joined(separator: PageOptions.pathSeparator) }
            } ?? []
            DispatchQueue.main.async {
                self.installed = installed
                if !names.isEmpty || !installed.isEmpty {
                    self.state = .loaded(names)
                } else if !trusted {
                    self.state = .unavailable("Autorise l'Accessibilité à FL Shortcuts pour voir la liste de tes plugins, "
                                              + "ou écris le nom.")
                } else if pid == nil {
                    self.state = .unavailable(Self.flClosed)
                } else {
                    self.state = .unavailable("Liste introuvable dans FL : écris le nom.")
                }
            }
        }
    }

    struct Format: Equatable {
        struct Entry: Equatable {
            /// Place dans `installed`.
            let index: Int
            let name: String
        }

        let format: String
        var items: [Entry]
    }

    /// Pure (testée) : plugins installés rangés par format (VST, VST3, AU…), avec leur place dans la liste.
    static func formats(_ plugins: [FLPluginDatabase.Plugin]) -> [Format] {
        var out: [Format] = []
        for (i, plugin) in plugins.enumerated() {
            let entry = Format.Entry(index: i, name: plugin.name)
            if let last = out.indices.last, out[last].format == plugin.format {
                out[last].items.append(entry)
            } else {
                out.append(Format(format: plugin.format, items: [entry]))
            }
        }
        return out
    }

    private static let flClosed = "Ouvre FL Studio pour choisir dans la liste de tes plugins, ou écris le nom."

    struct Folder: Equatable {
        /// Sous-menu du menu Add ; nil pour les plugins de sa racine.
        let title: String?
        var names: [String]
    }

    /// Pure (testée) : plugins rangés par sous-menu, dans l'ordre du menu.
    static func groups(_ names: [String]) -> [Folder] {
        var out: [Folder] = []
        for name in names {
            let path = PageOptions.pluginPath(name)
            let title = path.count > 1 ? path[0] : nil
            if let last = out.indices.last, out[last].title == title {
                out[last].names.append(name)
            } else {
                out.append(Folder(title: title, names: [name]))
            }
        }
        return out
    }
}

/// Mute / solo sans le script : le bouton mute de la piste cliquée dans le Mixer, montré une seule fois sur ce Mac.
private struct MuteSoloField: View {
    let key: String
    let window: NSWindow?
    let learnedChanged: () -> Void
    @ObservedObject private var teacher = MuteSwitchTeacher.shared
    @State private var learned = MuteSwitch.isLearned

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(key == "mute"
                  ? "Avec le lien avec FL : le son de la piste choisie est coupé (ou remis) tout de suite, sans aucun clic."
                  : "Avec le lien avec FL : la piste choisie passe en solo (ou le perd) tout de suite, sans aucun clic.",
                  systemImage: "link")
                .font(.system(size: 11))
                .foregroundStyle(.blue)
                .fixedSize(horizontal: false, vertical: true)
            Text(key == "mute"
                 ? "Sans le lien seulement : clique ta piste dans le Mixer, puis lance la macro ; son bouton mute est "
                     + "cliqué (montré une fois ci-dessous)."
                 : "Sans le lien seulement : clique ta piste dans le Mixer, puis lance la macro ; clic droit sur son "
                     + "bouton mute, ou la touche S de FL tant qu'il n'est pas montré.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Label(learned ? "Bouton mute montré sur ce Mac" : "Bouton mute à montrer une fois",
                  systemImage: learned ? "checkmark.circle.fill" : "hand.point.up.left")
                .font(.system(size: 12))
                .foregroundStyle(learned ? Color.green : Color.purple)
            Button(learned ? "Montrer de nouveau…" : "Montrer le bouton mute dans FL…") {
                guard let pid = EventTap.shared.currentConfig.flPIDs.first else {
                    teacher.say("Ouvre FL Studio, puis recommence.")
                    return
                }
                teacher.start(pid: pid, returnTo: window)
            }
            .secondaryButton()
            .disabled(teacher.active)
            .help("Dans FL, clique le bouton mute (le petit rond en haut) d'une piste, puis reclique-le pour remettre le son.")
            if let message = teacher.message {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onChange(of: teacher.active) { active in
            guard !active else { return }
            learned = MuteSwitch.isLearned
            learnedChanged()
        }
    }
}

private extension ParamKind {
    /// Réglage montré dans l'inspecteur (les listes de blocs imbriqués se rangent dans la liste).
    var editable: Bool {
        if case .blocs = self { return false }
        return true
    }
}

extension MacroBadge {
    var symbol: String {
        switch self {
        case .pauseFixe: return "timer"
        case .aApprendre: return "hand.point.up.left"
        case .probleme: return "exclamationmark.triangle.fill"
        case .continueSiEchec: return "arrow.uturn.forward"
        }
    }

    var tint: Color {
        switch self {
        case .pauseFixe: return .orange
        case .aApprendre: return .purple
        case .probleme: return .red
        case .continueSiEchec: return .secondary
        }
    }
}

// MARK: - Montrer un clic dans FL

/// « Montrer dans FL… » : FL passe devant, le premier clic gauche de l'utilisateur dans FL est retenu par rapport à
/// la fenêtre ou au menu de FL où il tombe (fenêtres relevées toutes les 50 ms SEULEMENT pendant l'apprentissage,
/// 30 s au plus ; Échap annule). Reprend l'enregistreur de clics de l'apprentissage de l'entrée 1.
final class ClickTeacher: ObservableObject {
    static let shared = ClickTeacher()

    @Published private(set) var activeBlock: UUID?
    @Published private(set) var message: String?
    /// Bloc concerné par `message`.
    @Published private(set) var lastBlock: UUID?

    private var timer: Timer?
    private var history: [WinSnapshot] = []
    private var started = Date()
    private var pid: Int32 = 0
    private var completion: ((ClickTarget) -> Void)?
    /// Glisser-déposer montré : l'appui et le relâché du même geste.
    private var dragCompletion: ((ClickTarget, ClickTarget) -> Void)?
    private var dragging = false
    private weak var returnWindow: NSWindow?
    /// « Retrouver ce bouton s'il bouge » : l'image du bouton est prise juste après le clic montré.
    private var visual = false

    private init() {}

    func say(_ text: String, for block: UUID) {
        lastBlock = block
        message = text
    }

    /// Glisser-déposer : FL passe devant, le premier geste « appui, glissé, relâché » dans FL est retenu.
    func startDrag(block: UUID, pid: Int32, returnTo window: NSWindow?,
                   completion: @escaping (ClickTarget, ClickTarget) -> Void) {
        start(block: block, pid: pid, returnTo: window, drag: true) { _ in }
        guard activeBlock == block else { return }
        dragCompletion = completion
    }

    func start(block: UUID, pid: Int32, returnTo window: NSWindow?, visual: Bool = false, drag: Bool = false,
               completion: @escaping (ClickTarget) -> Void) {
        stop()
        self.visual = visual
        dragging = drag
        guard let fl = NSRunningApplication(processIdentifier: pid) else {
            say("Ouvre FL Studio, puis recommence.", for: block)
            return
        }
        self.pid = pid
        self.completion = completion
        returnWindow = window
        activeBlock = block
        say(drag ? "Dans FL : reste cliqué sur ce qu'il faut attraper, glisse et lâche à l'endroit voulu (Échap pour annuler)."
                 : "Dans FL : clique une fois à l'endroit voulu (Échap pour annuler).", for: block)
        history = []
        started = Date()
        CreatorPresence.stepAside()
        fl.activate(options: [])
        ClickRecorder.shared.start(releases: drag)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, self.activeBlock == block,
                  let main = FLWindows.list(pid: pid).filter({ $0.layer == 0 })
                    .max(by: { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }) else { return }
            HintPanel.shared.show(drag ? "Fais le glisser-déposer dans FL (une fois). Échap : annuler."
                                       : "Clique à l'endroit voulu dans FL (une fois). Échap : annuler.",
                                  near: CGPoint(x: main.bounds.midX, y: main.bounds.minY + 70))
        }
        let t = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// `text` : montré sous le bloc. nil (créateur fermé) : ni message ni retour à sa fenêtre.
    func cancel(_ text: String?) {
        let block = activeBlock
        if text == nil {
            returnWindow = nil
            if message != nil { message = nil }
        }
        finish(nil)
        if let block, let text { say(text, for: block) }
    }

    private func tick() {
        let snap = WinSnapshot.take(pid: pid)
        history.append(snap)
        if history.count > 40 { history.removeFirst(history.count - 40) }
        if CGEventSource.keyState(.combinedSessionState, key: 53) {
            cancel("Annulé.")
            return
        }
        if Date().timeIntervalSince(started) > 30 {
            cancel(dragging ? "Aucun glisser-déposer montré dans FL en 30 s." : "Aucun clic montré dans FL en 30 s.")
            return
        }
        if dragging {
            tickDrag(snap)
            return
        }
        guard let sample = ClickRecorder.shared.capturedSamples.first else { return }
        // Fenêtres telles qu'elles étaient juste avant le clic (un clic dans un menu le ferme aussitôt).
        let before = history.last(where: { $0.time <= sample.time }) ?? history.first ?? snap
        let block = activeBlock
        let windows: [(layer: Int, bounds: CGRect)] = before.fl.map { (layer: $0.layer, bounds: $0.bounds) }
        let title = FLWindowAX.pluginTitle(at: sample.point, before: before, fl: pid)     // fenêtre de plugin
        if let target = MacroOutline.learnedTarget(at: sample.point, windows: windows, title: title) {
            let done = completion
            // Clic dans une fenêtre de FL, écran lisible : le bouton est retenu par son nom s'il en porte un, sinon
            // (« Retrouver ce bouton s'il bouge ») par son image, sinon par sa place.
            if MacroEffectsMac.canRead || visual, let block, let window = before.hit(sample.point), window.number > 0,
               case .flWindow(let corner, let dx, let dy, let size?, let title) = target {
                finish(target)
                say("Lecture du bouton…", for: block)
                let point = sample.point, wantsImage = visual
                TextLook.lookup(at: point, window: window) { [weak self] found in
                    let spot = found.map { NamedSpot(label: $0.label, dx: $0.dx, dy: $0.dy, corner: corner, px: dx, py: dy,
                                                     size: size, title: title) }
                    if let spot, spot.isValid {
                        done?(.named(spot))
                        self?.say("Bouton retenu par son nom « \(spot.label.displaySafe(max: 30)) » : il sera retrouvé "
                                  + "même s'il bouge.", for: block)
                    } else if wantsImage {
                        self?.learnImage(at: point, window: window, place: target, done: done, block: block)
                    } else {
                        done?(target)
                        self?.say("Endroit retenu.", for: block)
                    }
                }
                return
            }
            finish(target)
            done?(target)
            if let block { say("Endroit retenu.", for: block) }
        } else {
            cancel("Ce clic n'était ni dans une fenêtre de FL ni dans un de ses menus : recommence.")
        }
    }

    /// Glisser : l'appui puis le relâché qui le suit, retenus par rapport aux fenêtres de FL telles qu'elles étaient
    /// juste avant l'appui.
    private func tickDrag(_ snap: WinSnapshot) {
        let samples = ClickRecorder.shared.capturedSamples
        guard let down = samples.first(where: { !$0.up }),
              let up = samples.first(where: { $0.up && $0.time >= down.time }) else { return }
        let before = history.last(where: { $0.time <= down.time }) ?? history.first ?? snap
        let windows: [(layer: Int, bounds: CGRect)] = before.fl.map { (layer: $0.layer, bounds: $0.bounds) }
        let titles = (FLWindowAX.pluginTitle(at: down.point, before: before, fl: pid),
                      FLWindowAX.pluginTitle(at: up.point, before: before, fl: pid))
        let block = activeBlock
        let done = dragCompletion
        switch MacroOutline.dragTargets(from: down.point, to: up.point, windows: windows, titles: titles) {
        case .shown(let from, let to):
            finish(nil)
            done?(from, to)
            if let block { say("Glisser-déposer retenu.", for: block) }
        case .tooShort:
            cancel("Ce n'était pas un glisser : reste cliqué et glisse jusqu'à l'endroit voulu, puis recommence.")
        case .outside:
            cancel("Le glisser doit commencer et finir dans une fenêtre de FL (pas dans un menu) : recommence.")
        }
    }

    /// Image du bouton sous `point` (bouton sans nom, « Retrouver ce bouton s'il bouge ») ; sinon sa place.
    private func learnImage(at point: CGPoint, window: WinInfo, place target: ClickTarget,
                            done: ((ClickTarget) -> Void)?, block: UUID) {
        guard case .flWindow(let corner, let dx, let dy, let size?, let title) = target else { return }
        ScreenLook.capture(windowNumber: window.number, size: window.bounds.size) { [weak self] image in
            let patch = image.flatMap { image -> GrayImage? in
                let cx = Int((point.x - window.bounds.minX) * CGFloat(image.width) / window.bounds.width)
                let cy = Int((point.y - window.bounds.minY) * CGFloat(image.height) / window.bounds.height)
                return image.crop(centerX: cx, centerY: cy, side: VisualSpot.defaultSide)
            }
            if let patch, patch.contrast >= VisualMatch.minContrast {
                done?(.button(VisualSpot(corner: corner, dx: dx, dy: dy, size: size, title: title,
                                         side: patch.width, pixels: patch.pixels)))
                self?.say("Bouton retenu : il sera cherché à son image.", for: block)
            } else {
                done?(target)
                self?.say(image == nil ? "Lecture de l'écran impossible : endroit retenu sans image."
                                       : "Rien de reconnaissable à cet endroit : endroit retenu sans image.", for: block)
            }
        }
    }

    private func finish(_ target: ClickTarget?) {
        stop()
        activeBlock = nil
        CreatorPresence.comeBack()
        // Retour dans le créateur.
        if let window = returnWindow {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
        returnWindow = nil
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        completion = nil
        dragCompletion = nil
        if activeBlock != nil {
            ClickRecorder.shared.stop()
            HintPanel.shared.hide()
        }
        history = []
    }
}

// MARK: Couleur du bloc « Nom et couleur »

/// « Changer la couleur », code « # » (6 chiffres hexadécimaux) avec aperçu, « Choisir… » (la fenêtre de couleur de
/// FL recopiée : FLColorSelector), et les 10 dernières couleurs choisies.
struct NameColorField: View {
    let color: RGBColor?
    let set: (RGBColor?) -> Void
    @State private var text = ""
    @State private var recent: [RGBColor] = []
    @State private var picking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Changer la couleur", isOn: Binding(get: { color != nil }, set: { on in
                let start = recent.first ?? NameColorPayload.defaultColor
                set(on ? start : nil)
                if on { text = start.hex }
            }))
            if let color {
                HStack(spacing: 6) {
                    Button { picking = true } label: { Self.swatch(color, size: 20) }
                        .buttonStyle(.plain)
                        .help("Choisir dans la roue des couleurs de FL")
                    Text("#").foregroundStyle(.secondary)
                    TextField("E0453A", text: $text)
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 96)
                        .help("Code de la couleur, comme dans la fenêtre de couleur de FL (Entrée pour la garder dans les récentes)")
                        .onSubmit {
                            if let c = RGBColor(hex: text) { remember(c) }
                        }
                    Button("Choisir…") { picking = true }
                        .controlSize(.small)
                        .popover(isPresented: $picking, arrowEdge: .leading) {
                            FLColorSelector(initial: color) { picked in
                                choose(picked)
                                picking = false
                            }
                        }
                }
                if !text.isEmpty, RGBColor(hex: text) == nil {
                    Text("6 chiffres ou lettres de A à F, comme E0453A.")
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                }
                if !recent.isEmpty {
                    Text("Récentes").font(.system(size: 11)).foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        ForEach(recent, id: \.self) { c in
                            Button { choose(c) } label: { Self.swatch(c, size: 18, selected: c == color) }
                                .buttonStyle(.plain)
                                .help("#\(c.hex)")
                        }
                    }
                }
            }
        }
        .onAppear {
            text = color?.hex ?? ""
            recent = RecentColors.list()
        }
        // Code tapé : appliqué dès qu'il est complet, gardé dans les récentes seulement à la validation (Entrée) ;
        // un code à moitié modifié ne remplit pas les récentes.
        .onChange(of: text) { newText in
            guard let c = RGBColor(hex: newText), c != color else { return }
            set(c)
        }
        // Couleur changée ailleurs (⌘Z, autre bloc sélectionné…) : le code affiché suit.
        .onChange(of: color) { newColor in
            if newColor != RGBColor(hex: text) { text = newColor?.hex ?? "" }
        }
    }

    /// Pastille des récentes : appliquée et remontée en tête.
    private func choose(_ c: RGBColor) {
        set(c)
        text = c.hex
        remember(c)
    }

    private func remember(_ c: RGBColor) {
        RecentColors.remember(c)
        recent = RecentColors.list()
    }

    static func swatch(_ c: RGBColor, size: CGFloat, selected: Bool = false) -> some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(Color(red: Double(c.r) / 255, green: Double(c.g) / 255, blue: Double(c.b) / 255))
            .frame(width: size, height: size)
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.15), lineWidth: selected ? 2 : 1))
    }
}
