// Blocs « Ouvrir une page de FL » et « Cliquer sur… » : on choisit d'abord la page (Playlist, Channel Rack, Mixer…),
// puis une option de cette page dans une liste (armer la piste, ajouter un instrument, un raccourci de FL…). La
// liste ne montre que les options de la page ouverte au-dessus ; ajouter « Cliquer sur… » sans page juste au-dessus
// ajoute d'abord « Ouvrir une page de FL », à choisir.
// - La page n'est ouverte que si elle n'est pas déjà devant : avec le lien, la page devant est connue (rien n'est
//   envoyé si c'est elle), et l'ouverture du script de FL ne ferme jamais une page (ui.showWindow). Sans le lien :
//   sa touche de FL (F5, F6, F7, F9, ⌥F8), qui peut la refermer si elle est déjà devant (dit dans l'inspecteur).
// - Chaque option est jouée par le moyen le plus sûr : le lien avec FL (actions, mute ou solo d'un canal par son
//   numéro, nom de la piste), le menu Add de FL par son nom (instrument, effet, choisi dans la liste lue dans FL), ou
//   la touche de FL (raccourcis d'origine de la page). Aucune ne clique avec la souris.
// - Une option qui demande une valeur (plugin, numéro du canal, nouveau nom) la garde dans le texte « name » du bloc.
import Foundation

/// Page de FL qu'on peut mettre devant.
enum FLPage: String, CaseIterable, Identifiable {
    case playlist, channelRack, pianoRoll, mixer, browser

    var id: String { rawValue }

    var title: String {
        switch self {
        case .playlist: return "Playlist"
        case .channelRack: return "Channel Rack"
        case .pianoRoll: return "Piano Roll"
        case .mixer: return "Mixer"
        case .browser: return "Browser"
        }
    }

    /// Action du script de FL qui la met devant (PROTOCOL.md §6).
    var actionKey: String {
        switch self {
        case .playlist: return "pl"
        case .channelRack: return "cr"
        case .pianoRoll: return "pr"
        case .mixer: return "mx"
        case .browser: return "br"
        }
    }

    /// Page devant selon le lien avec FL.
    var window: FLWindow {
        switch self {
        case .playlist: return .playlist
        case .channelRack: return .channelRack
        case .pianoRoll: return .pianoRoll
        case .mixer: return .mixer
        case .browser: return .browser
        }
    }

    /// Rubrique du catalogue des raccourcis de cette page.
    var section: FLSection {
        switch self {
        case .playlist: return .playlist
        case .channelRack: return .channelRack
        case .pianoRoll: return .pianoRoll
        case .mixer: return .mixer
        case .browser: return .browser
        }
    }

    /// Bloc qui la met devant : le lien avec FL, sinon sa touche de FL.
    /// Touche de FL qui affiche la page (F5, F6, F7, F9, ⌥F8).
    func nativeKey(layout: KeyboardLayout) -> KeyCombo? {
        FLActions.id(forKey: actionKey).flatMap { AppMode.nativeEquivalent(of: $0, layout: layout) }
    }

    func openBody(layout: KeyboardLayout) -> BlockBody {
        let native = nativeKey(layout: layout)
        let fallback: ActionFallback = native.map { ActionFallback.key(KeyRef($0)) } ?? ActionFallback.none
        return .flAction(key: actionKey, fallback: fallback)
    }
}

/// Une option d'une page de FL (« Cliquer sur… »).
struct PageOption: Identifiable, Equatable {
    enum Kind: Equatable {
        /// Action du script de FL (le lien), avec sa touche de FL en repli.
        case action(String)
        /// Raccourci d'origine de FL dans cette page.
        case key(KeyCombo)
        /// Élément du menu Add de FL (barre des menus de macOS), suivi du nom choisi (plugin).
        case addMenu(String)
        /// Mute ou solo d'un canal du Channel rack, par son numéro : le lien avec FL (aucun clic, aucune touche),
        /// sinon la touche 1 à 0 de FL jusqu'au canal 10.
        case channelToggle(solo: Bool)
        /// Nouveau nom de la piste sélectionnée : le lien avec FL, sinon la fenêtre F2 de FL.
        case rename
    }

    /// Ce que l'option demande en plus, écrit dans le bloc (son texte « name »).
    enum Field: Equatable {
        /// Plugin du menu Add de FL (« Serum », ou « Sous-menu › Plugin »).
        case plugin
        /// Numéro du canal (1 à `PageOptions.maxChannel`).
        case channel
        /// Nouveau nom de la piste.
        case name
    }

    /// « mixer.arm », « channelRack.addInstrument », « channelRack.fl.channelRack.c »…
    let id: String
    let page: FLPage
    let label: String
    let kind: Kind

    var field: Field? {
        switch kind {
        case .addMenu: return .plugin
        case .channelToggle: return .channel
        case .rename: return .name
        case .action, .key: return nil
        }
    }
}

enum PageOptions {
    /// Longueur maximale du nom d'un plugin.
    static let maxName = 80
    /// Numéro de canal le plus grand accepté (« Mute d'un canal »).
    static let maxChannel = 999
    /// Sous-menus du menu Add dans le nom d'un plugin : « Fruity › Fruity Limiter ».
    static let pathSeparator = " › "

    /// Raccourcis remplacés par une option qui demande sa valeur : les touches 1 à 0 (⌘ pour le solo) par « Mute
    /// d'un canal », F2 par « Renommer la piste ». Plus proposés, toujours compris (macros déjà faites).
    static let replaced: Set<String> = {
        let digits = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
        let rack = digits.flatMap { ["channelRack.fl.channelRack.\($0)", "channelRack.fl.channelRack.cmd-\($0)"] }
        return Set(rack + ["mixer.fl.mixer.f2"])
    }()

    /// Options de la page : les plus utiles d'abord (ajouter un plugin, armer…), puis les raccourcis de FL de la page.
    /// `all` : avec les raccourcis remplacés (validation, macros déjà faites).
    static func options(for page: FLPage, layout: KeyboardLayout, all: Bool = false) -> [PageOption] {
        var out: [PageOption] = []
        func add(_ id: String, _ label: String, _ kind: PageOption.Kind) {
            out.append(PageOption(id: "\(page.rawValue).\(id)", page: page, label: label, kind: kind))
        }
        switch page {
        case .channelRack:
            add("addInstrument", "Ajouter un instrument (VST, plugin…)", .addMenu("Channel"))
            add("chMute", "Mute d'un canal (son numéro)", .channelToggle(solo: false))
            add("chSolo", "Solo d'un canal (son numéro)", .channelToggle(solo: true))
            add("chnext", "Instrument suivant", .action("chnext"))
            add("chprev", "Instrument précédent", .action("chprev"))
            add("presetnext", "Preset suivant", .action("presetnext"))
            add("presetprev", "Preset précédent", .action("presetprev"))
        case .mixer:
            add("addEffect", "Ajouter un effet sur la piste (plugin)", .addMenu("Effect"))
            add("rename", "Renommer la piste", .rename)
            add("armon", "Armer la piste", .action("armon"))
            add("arm", "Armer ou désarmer la piste", .action("arm"))
            add("mute", "Mute de la piste (coupe ou remet le son)", .action("mute"))
            add("solo", "Solo de la piste (met ou retire le solo)", .action("solo"))
            add("unsolo", "Retirer tous les solos", .action("unsolo"))
            add("bypass", "Couper les effets de la piste (bypass)", .action("bypass"))
            add("trnext", "Piste suivante", .action("trnext"))
            add("trprev", "Piste précédente", .action("trprev"))
            add("volup", "Monter le volume de la piste", .action("volup"))
            add("voldn", "Baisser le volume de la piste", .action("voldn"))
            add("mono", "Master en mono", .action("mono"))
        case .playlist:
            add("marker", "Poser un marqueur", .action("marker"))
            add("snap", "Grille suivante", .action("snap"))
        case .pianoRoll:
            add("quant", "Quantize rapide", .action("quant"))
            add("snap", "Grille suivante", .action("snap"))
        case .browser:
            break
        }
        // Raccourcis d'origine de FL dans cette page (touche de FL, toujours la même).
        for entry in Catalog.entries(layout: layout) where entry.section == page.section {
            guard case .native(let combo) = entry.kind else { continue }
            let id = "\(page.rawValue).\(entry.id)"
            if !all, replaced.contains(id) { continue }
            add(entry.id, entry.title, .key(combo))
        }
        return out
    }

    /// Identifiants de toutes les options, celles qui passent par le lien, et ce que chacune demande : ne dépendent
    /// pas de la disposition du clavier, calculés une fois (la validation et les besoins d'une macro les lisent souvent).
    private static let known: (all: Set<String>, link: Set<String>, fields: [String: PageOption.Field]) = {
        let all = FLPage.allCases.flatMap { options(for: $0, layout: SystemKeyboardLayout(), all: true) }
        let link = all.filter {
            switch $0.kind {
            case .action, .channelToggle, .rename: return true
            case .key, .addMenu: return false
            }
        }
        return (Set(all.map(\.id)), Set(link.map(\.id)),
                Dictionary(uniqueKeysWithValues: all.compactMap { o in o.field.map { (o.id, $0) } }))
    }()

    static func isKnown(_ id: String) -> Bool { known.all.contains(id) }
    static func usesLink(_ id: String) -> Bool { known.link.contains(id) }
    static func field(of id: String) -> PageOption.Field? { known.fields[id] }

    /// Page d'une option, d'après son identifiant.
    static func page(of id: String) -> FLPage? {
        id.split(separator: ".", maxSplits: 1).first.flatMap { FLPage(rawValue: String($0)) }
    }

    static func option(_ id: String, layout: KeyboardLayout) -> PageOption? {
        guard let page = page(of: id) else { return nil }
        return options(for: page, layout: layout, all: true).first { $0.id == id }
    }

    /// Numéro de canal écrit dans le bloc (1 à `maxChannel`), sinon nil.
    static func channel(_ text: String) -> Int? {
        guard let n = Int(text.trimmingCharacters(in: .whitespaces)), (1...maxChannel).contains(n) else { return nil }
        return n
    }

    /// Touche 1 à 0 de FL (⌘ pour le solo) du canal `number`, jusqu'au canal 10.
    static func channelKey(_ number: Int, solo: Bool, layout: KeyboardLayout) -> KeyCombo? {
        guard (1...10).contains(number) else { return nil }
        let digit = number == 10 ? "0" : String(number)
        guard let o = option("channelRack.fl.channelRack.\(solo ? "cmd-" : "")\(digit)", layout: layout),
              case .key(let combo) = o.kind else { return nil }
        return combo
    }

    /// Chemin dans le menu Add › Channel ou Effect : « Fruity › Fruity Limiter » → [Fruity, Fruity Limiter].
    static func pluginPath(_ name: String) -> [String] {
        name.split(separator: "›", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// Ce que joue l'option : une action du lien, la touche de FL, ou le menu Add de FL avec le nom choisi. nil : jouée
    /// par l'effet lui-même (canal par son numéro, nom de la piste).
    static func body(_ option: PageOption, name: String, layout: KeyboardLayout) -> BlockBody? {
        switch option.kind {
        case .action(let key):
            // Armer sans le lien : le menu de la piste (n'éteint jamais) ; sinon la touche de FL, si elle existe.
            let native = FLActions.id(forKey: key).flatMap { AppMode.nativeEquivalent(of: $0, layout: layout) }
            let fallback: ActionFallback = key == "armon" ? .trackMenuArm
                : native.map { ActionFallback.key(KeyRef($0)) } ?? ActionFallback.none
            return .flAction(key: key, fallback: fallback)
        case .key(let combo):
            return .key(KeyRef(combo), times: 1)
        case .addMenu(let item):
            return .menuBar(titles: ["Add", item] + pluginPath(name))
        case .channelToggle, .rename:
            return nil
        }
    }

    /// Valeur du bloc pour son option : nil si elle convient, sinon ce qu'il faut écrire.
    static func valueProblem(_ field: PageOption.Field, _ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        switch field {
        case .plugin:
            let path = pluginPath(trimmed)
            if trimmed.isEmpty || trimmed.count > maxName || path.contains(where: \.isEmpty)
                || path.count > MenuBarAX.maxDepth - 2 {
                return "choisis le plugin à ajouter (comme dans le menu Add de FL)."
            }
        case .channel:
            if channel(trimmed) == nil { return "écris le numéro du canal (1 à \(maxChannel))." }
        case .name:
            if trimmed.isEmpty { return "écris le nouveau nom de la piste." }
            if let problem = NameColorPayload.nameProblem(trimmed) { return problem }
        }
        return nil
    }

    /// Pure (testée) : page ouverte au-dessus du bloc `id`, la dernière « Ouvrir une page de FL » avant lui, à son
    /// niveau ou plus haut (avant la boucle qui le contient). `.none` : bloc absent ; `.some(nil)` : aucune page
    /// choisie au-dessus.
    static func pageAbove(_ id: UUID, in blocks: [Block], inherited: FLPage? = nil) -> FLPage?? {
        var page = inherited
        for block in blocks {
            if block.id == id { return .some(page) }
            for child in block.body.children {
                if let found = pageAbove(id, in: child, inherited: page) { return found }
            }
            if case .openPage(let p) = block.body { page = p }
        }
        return nil
    }

    /// Pure (testée) : première option dont la page n'est pas celle ouverte au-dessus (chemin du bloc « 3.2 », numéroté
    /// comme la validation : « sinon » poursuit après « alors »), avec la page ouverte au-dessus.
    static func misplaced(in blocks: [Block], prefix: String = "", offset: Int = 0,
                          inherited: FLPage? = nil) -> (path: String, page: FLPage?)? {
        var page = inherited
        for (i, block) in blocks.enumerated() {
            let path = MacroValidation.path(prefix, offset + i + 1)
            if case .pageOption(let id?, _) = block.body, let own = PageOptions.page(of: id), own != page {
                return (path, page)
            }
            for (start, child) in MacroValidation.childLists(block.body) {
                if let found = misplaced(in: child, prefix: path, offset: start, inherited: page) { return found }
            }
            if case .openPage(let p) = block.body { page = p }
        }
        return nil
    }

    /// Message de la validation pour une option hors de sa page.
    static func misplacedMessage(_ wrong: (path: String, page: FLPage?)) -> String {
        guard let page = wrong.page else {
            return "Étape \(wrong.path) : ajoute « Ouvrir une page de FL » juste au-dessus et choisis la page de cette option."
        }
        return "Étape \(wrong.path) : cette option n'est pas dans \(page.title), la page ouverte au-dessus : choisis-en une de cette page."
    }
}

extension MacroOutline {
    /// Pure (testée) : « Cliquer sur… » posé à `point` sans page juste au-dessus (ni « Ouvrir une page de FL », ni
    /// une autre option de page) : un bloc entre les deux peut avoir changé la page devant.
    static func needsPage(_ new: Block, at point: InsertionPoint, in blocks: [Block]) -> Bool {
        guard case .pageOption = new.body else { return false }
        var copy = blocks
        return withList(&copy, container: point.container, slot: point.slot) { (list: inout [Block]) -> Bool in
            let i = min(max(point.index, 0), list.count)
            let above = i > 0 ? list[i - 1].body.type : nil
            return above != .openPage && above != .pageOption
        } ?? false
    }

    /// Insère un bloc ; « Cliquer sur… » sans page juste au-dessus arrive avec `page` (« Ouvrir une page de FL », à
    /// choisir) juste au-dessus.
    static func insertWithPage(_ new: Block, page: Block = Block(.openPage(nil)), into blocks: inout [Block],
                               at point: InsertionPoint) -> Bool {
        guard needsPage(new, at: point, in: blocks) else { return insert(new, into: &blocks, at: point) }
        let done: Void? = withList(&blocks, container: point.container, slot: point.slot) { (list: inout [Block]) -> Void in
            let i = min(max(point.index, 0), list.count)
            list.insert(page, at: i)
            list.insert(new, at: i + 1)
        }
        return done != nil
    }
}
