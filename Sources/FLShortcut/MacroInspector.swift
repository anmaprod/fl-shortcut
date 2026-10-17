// Créateur de macros : inspecteur du bloc choisi, à droite, construit à partir de ses réglages (ParamSpec du
// registre) : capture de touche (le champ d'enregistrement des raccourcis), nombres bornés, choix du preset,
// action de FL du catalogue, endroit d'un clic montré dans FL, « Si le bloc échoue », note.
// Construit seulement pour le bloc choisi ; chaque réglage passe par le brouillon (annulable, enregistré 0,5 s après).
import AppKit
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
            Text("\(titles.map { $0.displaySafe(max: 40) }.joined(separator: " › ")) : choisi par son nom dans la barre "
                 + "des menus de macOS (rien n'est cliqué à l'écran). Pour un autre élément, enregistre de nouveau tes clics.")
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
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
            Text("La carte son branchée (USB, Thunderbolt…) devient la sortie et l'entrée du Mac. Une seule fois, dans "
                 + "FL › Options › Audio settings : Output sur « Default audio device » et Input sur « Default input "
                 + "device » ; FL suit alors la carte tout seul. Plusieurs cartes branchées : celle choisie la dernière fois.")
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
        case .organize:
            Text("Ouvre l'Organiser sur la page de FL qui est devant (Channel rack ou Mixer). Les couleurs, dégradés et "
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
        case .flWindow, .openMenu, .cursorXWindowY, .toLearn: return "learned"
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
        case .flWindow, .openMenu, .cursorXWindowY, .toLearn:
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
            text = "Retenu dans la fenêtre du plugin « \(title.displaySafe(max: 40)) » : le clic la retrouve où qu'elle soit, "
                + "même agrandie, et attend qu'elle s'ouvre."
        case .flWindow(_, _, _, let size?, _):
            text = "Retenu dans la fenêtre de FL de \(Int(size.width)) × \(Int(size.height)) (fenêtre principale, réglages, "
                + "boîte…) : le clic attend qu'elle s'ouvre. Si elle change de taille, montre-le de nouveau."
        case .flWindow:
            text = "Retenu par rapport à la fenêtre de FL."
        case .openMenu:
            text = "Retenu dans le menu de FL ouvert par le clic précédent : le clic attend que ce menu s'ouvre."
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
                        teach()
                    } label: {
                        Label("Montrer dans FL…", systemImage: "hand.point.up.left")
                    }
                    .secondaryButton()
                    .help("FL passe devant : clique une fois à l'endroit voulu (le clic agit aussi dans FL). Échap annule.")
                }
            }
            if let message = teacher.message, teacher.lastBlock == block.id {
                Text(message).font(.system(size: 11)).foregroundStyle(learning ? Color.accentColor : Color.secondary)
            }
        }
    }

    private func teach() {
        guard let pid = EventTap.shared.currentConfig.flPIDs.first else {
            teacher.say("Ouvre FL Studio, puis recommence.", for: block.id)
            return
        }
        let id = block.id
        let editor: MacroEditorModel = model
        teacher.start(block: id, pid: pid, returnTo: editor.window) { [weak editor] target in
            editor?.updateBlock(id, key: "target", actionName: "Montrer l'endroit du clic") { b in
                if case .click(_, let button) = b.body { b.body = .click(target, button: button) }
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
            if case .unavailable(let reason)? = availability {
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
        case .lienFL: return "link"
        case .aApprendre: return "hand.point.up.left"
        case .probleme: return "exclamationmark.triangle.fill"
        case .continueSiEchec: return "arrow.uturn.forward"
        }
    }

    var tint: Color {
        switch self {
        case .pauseFixe: return .orange
        case .lienFL: return .blue
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
    private weak var returnWindow: NSWindow?

    private init() {}

    func say(_ text: String, for block: UUID) {
        lastBlock = block
        message = text
    }

    func start(block: UUID, pid: Int32, returnTo window: NSWindow?, completion: @escaping (ClickTarget) -> Void) {
        stop()
        guard let fl = NSRunningApplication(processIdentifier: pid) else {
            say("Ouvre FL Studio, puis recommence.", for: block)
            return
        }
        self.pid = pid
        self.completion = completion
        returnWindow = window
        activeBlock = block
        say("Dans FL : clique une fois à l'endroit voulu (Échap pour annuler).", for: block)
        history = []
        started = Date()
        CreatorPresence.stepAside()
        fl.activate(options: [])
        ClickRecorder.shared.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, self.activeBlock == block,
                  let main = FLWindows.list(pid: pid).filter({ $0.layer == 0 })
                    .max(by: { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }) else { return }
            HintPanel.shared.show("Clique à l'endroit voulu dans FL (une fois). Échap : annuler.",
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
            cancel("Aucun clic montré dans FL en 30 s.")
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
            finish(target)
            done?(target)
            if let block { say("Endroit retenu.", for: block) }
        } else {
            cancel("Ce clic n'était ni dans une fenêtre de FL ni dans un de ses menus : recommence.")
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
