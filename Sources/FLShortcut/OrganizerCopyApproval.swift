// Validation de la copie rangée (demande du propriétaire, 24/10). L'Organiser range toujours dans une copie
// « <nom>_2.flp » à côté du projet. Une fois l'Organiser fermé, la prochaine fois qu'on rouvre FL Shortcuts (l'icône
// de la barre des menus, l'app relancée ou rouverte), il demande si l'on valide cette version :
// - « Valider » : l'original part à la Corbeille et la version organisée prend son nom (FL enregistre d'abord la
//   version organisée s'il l'a ouverte, puis rouvre le fichier renommé : il n'écrira jamais sous l'ancien nom) ;
// - « Retourner en arrière » : la version organisée part à la Corbeille et FL rouvre le projet d'avant (lancé
//   dessus s'il était fermé) ;
// - « Plus tard » : plus demandé tout seul avant le prochain lancement ; une ligne du menu de l'icône y mène.
// Rien n'est jamais supprimé pour de bon (Corbeille) ; un renommage raté remet l'original à sa place. Les chemins
// restent dans les réglages de l'app sur le Mac, jamais dans le journal.
import AppKit
import SwiftUI

/// Une copie rangée en attente : le projet d'origine, la version organisée, et les versions organisées d'avant du
/// même projet (rangé de nouveau sans avoir répondu), qui partent à la Corbeille quelle que soit la réponse.
struct PendingCopy: Codable, Equatable, Identifiable {
    var original: URL
    var copy: URL
    var older: [URL] = []
    var date: Date

    var id: String { copy.path }
}

/// Les fichiers, côté Mac (des faux dans les tests). `trash` rend la place du fichier dans la Corbeille.
struct CopyFiles {
    var exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    var trash: (URL) throws -> URL? = { url in
        var place: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &place)
        return place as URL?
    }
    var move: (URL, URL) throws -> Void = { try FileManager.default.moveItem(at: $0, to: $1) }
}

enum CopyApprovalError: Error, Equatable {
    /// La version organisée n'est plus là (déplacée, supprimée) : rien n'a été touché.
    case copyMissing
    /// L'original n'a pas pu aller à la Corbeille : rien n'a été touché.
    case cannotTrash
    /// La version organisée n'a pas pu prendre le nom de l'original : l'original est revenu.
    case cannotRename
    /// FL n'a pas pu enregistrer (pas au premier plan) : rien n'a été touché.
    case flNotSaved
    /// FL n'a pas ouvert le fichier attendu à temps : rien n'a été touché.
    case flBusy
    /// Le projet d'avant n'est plus là (déplacé, supprimé) : la version organisée reste.
    case originalMissing

    var message: String {
        switch self {
        case .copyMissing:
            return String(localized: "La version organisée n'est plus à côté de ton projet : rien n'a été touché.")
        case .cannotTrash:
            return String(localized: "Ton projet d'origine n'a pas pu aller à la Corbeille : rien n'a été touché.")
        case .cannotRename:
            return String(localized: "La version organisée n'a pas pu prendre le nom de ton projet : ton projet d'origine est revenu à sa place.")
        case .flNotSaved:
            return String(localized: "FL Studio doit être au premier plan pour enregistrer la version organisée : clique dans sa fenêtre, puis réessaie. Rien n'a été touché.")
        case .flBusy:
            return String(localized: "FL Studio n'a pas changé de projet à temps (une question attend peut-être dans FL) : rien n'a été touché.")
        case .originalMissing:
            return String(localized: "Ton projet d'avant n'est plus à sa place : la version organisée est gardée.")
        }
    }
}

/// Pur (testé) : la liste des copies en attente et ce qui arrive aux fichiers.
enum CopyApprovalRules {
    static func same(_ a: URL, _ b: URL) -> Bool { a.standardizedFileURL.path == b.standardizedFileURL.path }

    /// Le nom d'un projet sans « .flp » ni son « _N » de version (« Nuit_3.flp » → « Nuit »).
    static func stem(_ url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
        guard let range = name.range(of: "_[0-9]+$", options: .regularExpression), range.lowerBound > name.startIndex
        else { return name }
        return String(name[..<range.lowerBound])
    }

    /// Une copie en attente qu'on peut toucher : rien que des projets .flp, dans le dossier de l'original, et des
    /// versions « _N » du même projet. La liste est gardée dans les réglages de l'app, qu'un autre programme du Mac
    /// peut écrire : sans cette vérification, il lui faisait mettre à la Corbeille, renommer ou ouvrir n'importe quel
    /// fichier (audit du 25/10).
    static func isSafe(_ p: PendingCopy) -> Bool {
        let folder = p.original.deletingLastPathComponent().standardizedFileURL.path
        func ok(_ url: URL, version: Bool) -> Bool {
            url.isFileURL && url.pathExtension.lowercased() == "flp"
                && url.deletingLastPathComponent().standardizedFileURL.path == folder
                && stem(url) == stem(p.original)
                && (!version || url.deletingPathExtension().lastPathComponent != stem(url))
        }
        return ok(p.original, version: false) && ok(p.copy, version: true) && !same(p.original, p.copy)
            && p.older.allSatisfy { ok($0, version: true) && !same($0, p.original) }
    }

    /// La liste après une nouvelle copie rangée de `original`. Rangé de nouveau depuis une version organisée en
    /// attente (ou depuis son original), elle la remplace et garde l'original d'origine ; l'ancienne version
    /// organisée partira à la Corbeille avec la réponse.
    static func recording(_ list: [PendingCopy], original: URL, copy: URL, date: Date) -> [PendingCopy] {
        var out = list
        var root = original
        var older: [URL] = []
        if let i = out.firstIndex(where: { same($0.copy, original) || same($0.original, original) }) {
            let previous = out.remove(at: i)
            root = previous.original
            older = previous.older + [previous.copy]
        }
        older.removeAll { same($0, copy) || same($0, root) }
        out.removeAll { same($0.copy, copy) }
        out.append(PendingCopy(original: root, copy: copy, older: older, date: date))
        return out
    }

    /// « Valider » : l'original à la Corbeille, la version organisée prend son nom, les versions d'avant à la
    /// Corbeille. Le fichier final (le nom de l'original). Rien n'est touché si la version organisée manque ou si
    /// l'original ne peut pas aller à la Corbeille ; un renommage raté remet l'original à sa place.
    @discardableResult
    static func validate(_ p: PendingCopy, files: CopyFiles) throws -> URL {
        guard isSafe(p), files.exists(p.copy) else { throw CopyApprovalError.copyMissing }
        var trashed: URL?
        if files.exists(p.original) {
            do {
                trashed = try files.trash(p.original)
            } catch {
                throw CopyApprovalError.cannotTrash
            }
        }
        do {
            try files.move(p.copy, p.original)
        } catch {
            if let trashed { try? files.move(trashed, p.original) }
            throw CopyApprovalError.cannotRename
        }
        for url in p.older where files.exists(url) { _ = try? files.trash(url) }
        return p.original
    }

    /// « Retourner en arrière » : la version organisée et celles d'avant à la Corbeille ; l'original ne bouge pas.
    static func goBack(_ p: PendingCopy, files: CopyFiles) {
        guard isSafe(p) else { return }
        for url in [p.copy] + p.older where files.exists(url) { _ = try? files.trash(url) }
    }
}

/// Les copies en attente (réglages de l'app) et la question, posée à la réouverture de FL Shortcuts.
final class CopyApproval: ObservableObject {
    static let shared = CopyApproval()
    static let key = "organizerPendingCopies"

    @Published private(set) var pending: [PendingCopy] = []
    /// « Plus tard » : plus demandé tout seul avant le prochain lancement (la ligne du menu reste).
    private(set) var snoozed = false
    private let defaults: UserDefaults
    var files = CopyFiles()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let list = try? JSONDecoder().decode([PendingCopy].self, from: data) {
            pending = Array(list.filter(CopyApprovalRules.isSafe).prefix(20))
        }
    }

    private func save() {
        if pending.isEmpty {
            defaults.removeObject(forKey: Self.key)
        } else if let data = try? JSONEncoder().encode(pending) {
            defaults.set(data, forKey: Self.key)
        }
    }

    /// Une copie rangée vient d'être faite (et ouverte dans FL).
    func record(original: URL, copy: URL) {
        pending = CopyApprovalRules.recording(pending, original: original, copy: copy, date: Date())
            .filter(CopyApprovalRules.isSafe)
        save()
    }

    /// « Revenir comme avant » : l'utilisateur a déjà choisi l'original, plus rien à demander pour cette copie.
    func forget(copy: URL) {
        pending.removeAll { CopyApprovalRules.same($0.copy, copy) }
        save()
    }

    /// « Revenir comme avant » dans l'Organiser (demande du propriétaire, 28/10) : la version organisée, et celles
    /// d'avant du même projet, partent à la Corbeille dès que FL ne la montre plus (il vient de rouvrir l'original ; il
    /// demande peut-être s'il faut l'enregistrer : l'utilisateur choisit). Toujours montrée au bout d'une minute : elle
    /// reste, la question reviendra à la réouverture de FL Shortcuts. Jamais un autre fichier (CopyApprovalRules.isSafe).
    func discard(copy: URL) {
        guard let p = pending.first(where: { CopyApprovalRules.same($0.copy, copy) }) else { return }
        let files = self.files
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let left = CopyApprovalLive.wait(seconds: 60) { !CopyApprovalLive.flShows(p.copy) }
            if left { CopyApprovalRules.goBack(p, files: files) }
            MacroLog.shared.write("ORGANIZE", left ? "organized copy trashed after undo (\(p.older.count) older)"
                                                   : "organized copy still open in FL after undo: kept, asked later")
            DispatchQueue.main.async { if left { self?.done(p) } }
        }
    }

    /// Les versions organisées qui ne sont plus là (déplacées, supprimées à la main) sont oubliées.
    func prune() {
        let before = pending.count
        pending.removeAll { !files.exists($0.copy) || !CopyApprovalRules.isSafe($0) }
        if pending.count != before { save() }
    }

    /// Réponse donnée (ou rien à faire) : la copie sort de la liste.
    func done(_ p: PendingCopy) {
        pending.removeAll { $0.id == p.id }
        save()
    }

    func snooze() { snoozed = true }

    /// À la réouverture de FL Shortcuts (icône, lancement, app rouverte) : la question, si une version organisée
    /// attend, que l'Organiser est fermé et que « Plus tard » n'a pas été choisi depuis le lancement. Fil principal.
    func askIfNeeded() {
        guard !snoozed, !DebugSnapshot.enabled, OrganizerWindow.controller == nil else { return }
        prune()
        guard !pending.isEmpty else { return }
        MainActor.assumeIsolated { CopyApprovalWindow.shared.show() }
    }
}

// MARK: - Avec FL

/// Ce que FL doit faire autour des fichiers (côté Mac) : jamais un nom dans le journal.
enum CopyApprovalLive {
    /// FL montre ce fichier (le titre de sa fenêtre, ou le document que macOS lui connaît).
    static func flShows(_ url: URL) -> Bool { ProjectFileLive.isOpen(url) }

    /// FL montre ce fichier, à `seconds` près (vrai) ; faux s'il le montre encore (ou pas encore) au bout du temps.
    static func wait(seconds: TimeInterval, until condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return condition()
    }

    /// « Valider », avec FL. Si FL montre l'original, il ouvre d'abord la version organisée ; s'il la montre, il
    /// l'enregistre (⌘S : ce qui a été fait dedans depuis l'Organiser est gardé) ; les fichiers changent ; FL rouvre
    /// le fichier sous son nom d'origine. FL fermé ou sur un autre projet : les fichiers seulement. Hors du fil
    /// principal.
    static func validate(_ p: PendingCopy, files: CopyFiles) -> Result<URL, CopyApprovalError> {
        guard files.exists(p.copy) else { return .failure(.copyMissing) }
        var flHad = false
        if OrganizerEnvironment.flPID() != nil {
            let showsCopy = flShows(p.copy)
            if !showsCopy, flShows(p.original) {
                guard ProjectFileLive.open(p.copy), wait(seconds: 60, until: { flShows(p.copy) }) else {
                    return .failure(.flBusy)
                }
            }
            if showsCopy || flShows(p.copy) {
                flHad = true
                guard ProjectFileLive.saveShown(p.copy) else { return .failure(.flNotSaved) }
            }
        }
        do {
            let final = try CopyApprovalRules.validate(p, files: files)
            if flHad { _ = ProjectFileLive.open(final) }
            MacroLog.shared.write("ORGANIZE", "organized copy approved (fl \(flHad ? "reopened" : "untouched"), \(p.older.count) older)")
            return .success(final)
        } catch {
            let reason = error as? CopyApprovalError ?? .cannotRename
            MacroLog.shared.write("ORGANIZE", "organized copy not approved (\(reason))")
            return .failure(reason)
        }
    }

    /// « Retourner en arrière », avec FL : il rouvre le projet d'avant (sauf s'il le montre déjà ; il demande
    /// peut-être s'il faut enregistrer celui qu'il quitte : l'utilisateur choisit), puis la version organisée part à
    /// la Corbeille une fois quittée. FL fermé : il est lancé sur le projet d'avant. Le projet d'avant disparu : rien
    /// n'est touché.
    static func goBack(_ p: PendingCopy, files: CopyFiles) -> CopyApprovalError? {
        guard CopyApprovalRules.isSafe(p) else { return .copyMissing }
        guard files.exists(p.original) else { return .originalMissing }
        if OrganizerEnvironment.flPID() != nil {
            let showsCopy = flShows(p.copy)
            if showsCopy || !flShows(p.original) {
                guard ProjectFileLive.open(p.original) else { return .flBusy }
                if showsCopy, !wait(seconds: 60, until: { !flShows(p.copy) }) { return .flBusy }
            }
        } else {
            // FL Studio lui-même, sur le projet d'avant (jamais une autre app qui aurait pris les .flp).
            guard let fl = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.image-line.flstudio") else {
                return .flBusy
            }
            DispatchQueue.main.async {
                NSWorkspace.shared.open([p.original], withApplicationAt: fl, configuration: NSWorkspace.OpenConfiguration(),
                                        completionHandler: nil)
            }
        }
        CopyApprovalRules.goBack(p, files: files)
        MacroLog.shared.write("ORGANIZE", "organized copy discarded, previous project reopened (\(p.older.count) older)")
        return nil
    }
}

// MARK: - Fenêtre

final class CopyApprovalFlow: ObservableObject {
    enum Step: Equatable {
        case question
        case working(String)
        /// `retry` : la même question peut être reposée ; sinon « OK » ferme.
        case failed(String, retry: Bool)
    }

    @Published var step: Step = .question
    @Published private(set) var current: PendingCopy?
    let approval: CopyApproval
    /// Mode capture (mesure de la CI) : écrans seulement, aucun fichier touché.
    let demo: Bool
    var close: () -> Void = {}

    init(approval: CopyApproval, demo: PendingCopy? = nil) {
        self.approval = approval
        self.demo = demo != nil
        current = demo ?? approval.pending.first
    }

    var remaining: Int { demo ? 0 : max(0, approval.pending.count - 1) }

    func validate() { answer(keep: true) }
    func goBack() { answer(keep: false) }

    func later() {
        approval.snooze()
        close()
    }

    private func answer(keep: Bool) {
        guard let p = current, !demo else { return }
        step = .working(keep ? String(localized: "FL enregistre la version organisée…")
                             : String(localized: "FL rouvre ton projet d'avant…"))
        let files = approval.files
        DispatchQueue.global(qos: .userInitiated).async {
            let error: CopyApprovalError?
            if keep {
                if case .failure(let e) = CopyApprovalLive.validate(p, files: files) { error = e } else { error = nil }
            } else {
                error = CopyApprovalLive.goBack(p, files: files)
            }
            DispatchQueue.main.async { [weak self] in self?.finish(p, error: error) }
        }
    }

    private func finish(_ p: PendingCopy, error: CopyApprovalError?) {
        if let error, error != .copyMissing {
            step = .failed(error.message, retry: true)
            return
        }
        // Répondu, ou la version organisée a disparu (plus rien à demander pour elle) : la suivante, s'il y en a.
        approval.done(p)
        approval.prune()
        if let next = approval.pending.first {
            current = next
            if let error {
                step = .failed(error.message, retry: true)
            } else {
                step = .question
            }
        } else if let error {
            step = .failed(error.message, retry: false)
        } else {
            close()
        }
    }

    /// Mode capture : un écran donné.
    func showDemo(_ screen: String) {
        switch screen {
        case "travail": step = .working(String(localized: "FL enregistre la version organisée…"))
        case "erreur": step = .failed(CopyApprovalError.flNotSaved.message, retry: true)
        default: step = .question
        }
    }
}

/// La fenêtre de la question (une seule à la fois), au-dessus de FL : FL passe devant pendant qu'il enregistre.
@MainActor
final class CopyApprovalWindow: NSObject, NSWindowDelegate {
    static let shared = CopyApprovalWindow()
    private var window: NSWindow?
    private var flow: CopyApprovalFlow?

    var isShowing: Bool { window != nil }

    func show(demo: PendingCopy? = nil) {
        if let window {
            window.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let flow = CopyApprovalFlow(approval: .shared, demo: demo)
        guard flow.current != nil else { return }
        flow.close = { [weak self] in self?.window?.close() }
        self.flow = flow
        let host = NSHostingController(rootView: CopyApprovalView(flow: flow))
        let w = NSWindow(contentViewController: host)
        w.styleMask = [.titled, .closable, .fullSizeContentView]
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.title = String(localized: "Version organisée")
        w.level = .floating
        w.hidesOnDeactivate = false
        w.delegate = self
        w.isReleasedWhenClosed = false
        w.center()
        window = w
        w.orderFrontRegardless()
        w.makeKey()
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Mode capture : un écran d'exemple ; « fermer » ferme la fenêtre.
    func showDemo(_ screen: String) {
        guard screen != "fermer" else {
            window?.close()
            return
        }
        if window == nil {
            let folder = URL(fileURLWithPath: "/Users/exemple/Documents/Image-Line/FL Studio/Projects")
            show(demo: PendingCopy(original: folder.appendingPathComponent("Nuit blanche.flp"),
                                   copy: folder.appendingPathComponent("Nuit blanche_2.flp"), date: Date()))
        }
        flow?.showDemo(screen)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if case .working = flow?.step { return false }
        return true
    }

    func windowWillClose(_ notification: Notification) {
        // Fermée sans répondre : comme « Plus tard ».
        if let flow, !flow.demo, flow.current.map({ p in flow.approval.pending.contains { $0.id == p.id } }) == true {
            flow.approval.snooze()
        }
        window = nil
        flow = nil
    }
}

/// Mise en page des alertes de macOS, comme la désinstallation : icône, titre en gras, une phrase, boutons en bas.
struct CopyApprovalView: View {
    @ObservedObject var flow: CopyApprovalFlow

    var body: some View {
        Group {
            switch flow.step {
            case .question: question
            case .working(let text): working(text)
            case .failed(let text, let retry): failed(text, retry: retry)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 30)
        .padding(.bottom, 18)
        .frame(width: 380)
        .background { BrandGlow() }
    }

    private func name(_ url: URL?) -> String { url?.lastPathComponent ?? "" }

    private var question: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 40))
                .foregroundStyle(OrganizerView.tint)
                .accessibilityHidden(true)
            Text("Tu valides la version organisée ?")
                .font(.system(size: 13, weight: .bold))
            Text("« \(name(flow.current?.copy)) » est ton projet « \(name(flow.current?.original)) » rangé par l'Organiser.")
                .font(.system(size: 11))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 4) {
                Text("Valider : ton projet d'origine part à la Corbeille et la version organisée prend son nom.")
                Text("Retourner en arrière : la version organisée part à la Corbeille et FL rouvre ton projet d'avant.")
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            if flow.remaining > 0 {
                Text("Encore \(flow.remaining) autre(s) projet(s) ensuite.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Button { flow.goBack() } label: { Text("Retourner en arrière").frame(maxWidth: .infinity) }
                Button { flow.validate() } label: { Text("Oui, valider").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
            .padding(.top, 8)
            Button("Plus tard") { flow.later() }
                .buttonStyle(.link)
                .font(.system(size: 11))
                .keyboardShortcut(.cancelAction)
        }
    }

    private func working(_ text: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
            Text(text).font(.system(size: 13, weight: .bold)).multilineTextAlignment(.center)
            ProgressView().controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private func failed(_ text: String, retry: Bool) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.yellow)
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: 11))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                if retry {
                    Button { flow.later() } label: { Text("Plus tard").frame(maxWidth: .infinity) }
                        .keyboardShortcut(.cancelAction)
                    Button { flow.step = .question } label: { Text("Réessayer").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button { flow.close() } label: { Text("OK").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .controlSize(.large)
            .padding(.top, 8)
        }
    }
}
