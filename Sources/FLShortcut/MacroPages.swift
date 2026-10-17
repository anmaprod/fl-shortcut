// Blocs « Ouvrir une page de FL » et « Cliquer sur… » : on choisit d'abord la page (Playlist, Channel Rack, Mixer…),
// puis une option de cette page dans une liste (armer la piste, ajouter un instrument, un raccourci de FL…). La
// liste ne montre que les options de la page ouverte au-dessus ; ajouter « Cliquer sur… » sans page juste au-dessus
// ajoute d'abord « Ouvrir une page de FL », à choisir.
// - La page n'est ouverte que si elle n'est pas déjà devant : avec le lien, la page devant est connue (rien n'est
//   envoyé si c'est elle), et l'ouverture du script de FL ne ferme jamais une page (ui.showWindow). Sans le lien :
//   sa touche de FL (F5, F6, F7, F9, ⌥F8), qui peut la refermer si elle est déjà devant (dit dans l'inspecteur).
// - Chaque option est jouée par le moyen le plus sûr : le lien avec FL (actions), le menu Add de FL par son nom
//   (instrument, effet), ou la touche de FL (raccourcis d'origine de la page).
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
    func openBody(layout: KeyboardLayout) -> BlockBody {
        let native = FLActions.id(forKey: actionKey).flatMap { AppMode.nativeEquivalent(of: $0, layout: layout) }
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
    }

    /// « mixer.arm », « channelRack.addInstrument », « channelRack.fl.channelRack.c »…
    let id: String
    let page: FLPage
    let label: String
    let kind: Kind

    /// Demande un nom (plugin à ajouter).
    var needsName: Bool {
        if case .addMenu = kind { return true }
        return false
    }
}

enum PageOptions {
    /// Longueur maximale du nom d'un plugin.
    static let maxName = 80

    /// Options de la page : les plus utiles d'abord (ajouter un plugin, armer…), puis les raccourcis de FL de la page.
    static func options(for page: FLPage, layout: KeyboardLayout) -> [PageOption] {
        var out: [PageOption] = []
        func add(_ id: String, _ label: String, _ kind: PageOption.Kind) {
            out.append(PageOption(id: "\(page.rawValue).\(id)", page: page, label: label, kind: kind))
        }
        switch page {
        case .channelRack:
            add("addInstrument", "Ajouter un instrument (VST, plugin…)", .addMenu("Channel"))
            add("chnext", "Instrument suivant", .action("chnext"))
            add("chprev", "Instrument précédent", .action("chprev"))
            add("presetnext", "Preset suivant", .action("presetnext"))
            add("presetprev", "Preset précédent", .action("presetprev"))
        case .mixer:
            add("addEffect", "Ajouter un effet sur la piste (plugin)", .addMenu("Effect"))
            add("armon", "Armer la piste", .action("armon"))
            add("arm", "Armer ou désarmer la piste", .action("arm"))
            add("mute", "Couper le son de la piste (mute)", .action("mute"))
            add("solo", "Solo sur la piste", .action("solo"))
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
            add(entry.id, entry.title, .key(combo))
        }
        return out
    }

    /// Identifiants de toutes les options, et celles qui passent par le lien : ne dépendent pas de la disposition du
    /// clavier, calculés une fois (la validation et les besoins d'une macro les lisent souvent).
    private static let known: (all: Set<String>, link: Set<String>) = {
        let all = FLPage.allCases.flatMap { options(for: $0, layout: SystemKeyboardLayout()) }
        return (Set(all.map(\.id)), Set(all.filter { if case .action = $0.kind { return true }; return false }.map(\.id)))
    }()

    static func isKnown(_ id: String) -> Bool { known.all.contains(id) }
    static func usesLink(_ id: String) -> Bool { known.link.contains(id) }
    static func needsName(_ id: String) -> Bool { id.hasSuffix(".addInstrument") || id.hasSuffix(".addEffect") }

    /// Page d'une option, d'après son identifiant.
    static func page(of id: String) -> FLPage? {
        id.split(separator: ".", maxSplits: 1).first.flatMap { FLPage(rawValue: String($0)) }
    }

    static func option(_ id: String, layout: KeyboardLayout) -> PageOption? {
        guard let page = page(of: id) else { return nil }
        return options(for: page, layout: layout).first { $0.id == id }
    }

    /// Ce que joue l'option : une action du lien, la touche de FL, ou le menu Add de FL avec le nom choisi.
    static func body(_ option: PageOption, name: String, layout: KeyboardLayout) -> BlockBody {
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
            return .menuBar(titles: ["Add", item, name.trimmingCharacters(in: .whitespaces)])
        }
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
