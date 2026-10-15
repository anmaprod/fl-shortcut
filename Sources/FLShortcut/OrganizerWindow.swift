// Organiser : la fenêtre (panneau flottant qui laisse FL au premier plan) et son contrôleur. Ouverte par le bloc
// « Organiser la page ouverte » ou par le menu de la barre des menus. Écoute, aperçu par famille (une couleur ou un
// dégradé chacune, famille de chaque son modifiable), application, puis « Revenir comme avant ». Tout est libéré à la
// fermeture (session, capture, IA, panneau) : rien ne tourne au repos. Aucune lecture de l'écran.
import AppKit
import SwiftUI

/// Ce dont l'Organiser a besoin du monde réel (des faux dans les tests).
struct OrganizerEnvironment {
    var link: () -> OrganizerLink
    /// Capture du son de FL, ou la raison de l'impossibilité (macOS trop ancien, FL fermé).
    var audio: () -> Result<AudioSource, OrganizerError>
    var classify: () -> OrganizerSession.Classify
    /// ⌥↑ envoyé à FL : `moveUp(link)(n)` renvoie le nombre de pas faits.
    var moveUp: (OrganizerLink) -> (Int) -> Int
    var timing = OrganizerSession.Timing()
    var sleep: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
    var escapePressed: () -> Bool = { false }
    var loadStyles: () -> [SoundFamily: FamilyStyle] = { FamilyStyles.load() }
    var saveStyles: ([SoundFamily: FamilyStyle]) -> Void = { FamilyStyles.save($0) }

    static func live() -> OrganizerEnvironment {
        OrganizerEnvironment(
            link: { RequestOrganizerLink.live() },
            audio: {
                guard #available(macOS 14.2, *) else {
                    return .failure(.failed("L'Organiser écoute FL avec macOS 14.2 ou plus récent : mets macOS à jour."))
                }
                guard let pid = OrganizerEnvironment.flPID() else { return .failure(.failed("FL Studio n'est pas ouvert.")) }
                return .success(FLAudioTap(pid: pid))
            },
            classify: { OrganizerSession.liveClassifier() },
            moveUp: { link in { count in OrganizerEnvironment.liveMoveUp(count, link: link) } },
            escapePressed: { CGEventSource.keyState(.combinedSessionState, key: 53) })
    }

    /// FL au premier plan d'abord, sinon le premier FL ouvert.
    static func flPID() -> Int32? {
        let cfg = EventTap.shared.currentConfig
        if cfg.flPIDs.contains(cfg.frontmostPID) { return cfg.frontmostPID }
        return cfg.flPIDs.min()
    }

    /// ⌥↑ envoyé à FL seul, 15 ms entre deux ; s'arrête dès que FL n'est plus au premier plan ou que le Channel rack
    /// n'est plus devant dans FL.
    static func liveMoveUp(_ count: Int, link: OrganizerLink) -> Int {
        guard count > 0, let pid = flPID() else { return 0 }
        if EventTap.shared.currentConfig.frontmostPID != pid {
            _ = NSRunningApplication(processIdentifier: pid)?.activate(options: [])
            Thread.sleep(forTimeInterval: 0.3)
        }
        let effects = MacroEffectsMac(pid: pid)
        let up = KeyCombo(keyCode: 126, option: true)
        var done = 0
        while done < count {
            guard EventTap.shared.currentConfig.frontmostPID == pid, link.window == .channelRack else { break }
            effects.postKey(up, pid: pid)
            done += 1
            Thread.sleep(forTimeInterval: 0.015)
        }
        return done
    }
}

final class OrganizerController: ObservableObject {
    enum Phase: Equatable {
        case starting
        case listening(done: Int, total: Int)
        case preview
        case applying
        case applied(OrganizerError?)
        case undoing
        case undone(OrganizerError?)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .starting
    /// Famille de chaque élément (canal ou piste du Mixer), modifiable dans l'aperçu.
    @Published var families: [Int: SoundFamily] = [:]
    @Published var styles: [SoundFamily: FamilyStyle]
    @Published private(set) var result: OrganizerResult?

    /// Appelé une fois, à la fermeture (la fenêtre se ferme et lâche le contrôleur).
    var onClose: (() -> Void)?

    private let env: OrganizerEnvironment
    private let queue = DispatchQueue(label: "app.flshortcut.organizer", qos: .userInitiated)
    private var link: OrganizerLink?
    private var session: OrganizerSession?
    private var snapshot: OrganizerSnapshot?
    private var closed = false

    init(env: OrganizerEnvironment) {
        self.env = env
        styles = env.loadStyles()
    }

    var title: String {
        switch result?.page {
        case .mixer?: return "Organiser le Mixer"
        case .channelRack?: return "Organiser le Channel rack"
        case nil: return "Organiser"
        }
    }

    /// Écoute de chaque son, hors du fil principal.
    func start() {
        guard phase == .starting, !closed else { return }
        let audio: AudioSource
        switch env.audio() {
        case .success(let source):
            audio = source
        case .failure(let error):
            phase = .failed(error.message)
            return
        }
        let link = env.link()
        let session = OrganizerSession(
            link: link, audio: audio, classify: env.classify(), timing: env.timing, sleep: env.sleep,
            escape: env.escapePressed,
            progress: { [weak self] done, total in
                DispatchQueue.main.async { self?.listening(done, total) }
            })
        self.link = link
        self.session = session
        phase = .listening(done: 0, total: 0)
        queue.async { [weak self] in
            let outcome = session.run()
            DispatchQueue.main.async { self?.finishListening(outcome) }
        }
    }

    private func listening(_ done: Int, _ total: Int) {
        guard case .listening = phase else { return }
        phase = .listening(done: done, total: total)
    }

    private func finishListening(_ outcome: Result<OrganizerResult, OrganizerError>) {
        session = nil
        guard !closed else { return }
        switch outcome {
        case .success(let result):
            self.result = result
            families = OrganizerApplier.families(of: result)
            if !families.isEmpty {
                phase = .preview
            } else if result.page == .mixer {
                phase = .failed("Aucune piste du Mixer n'est reliée à un son du Channel rack.")
            } else {
                phase = .failed("Aucun son à écouter dans le Channel rack.")
            }
        case .failure(let error):
            phase = .failed(error.message)
        }
    }

    /// Familles présentes, dans l'ordre Drums, Basse, Mélodies, Voix, FX, À vérifier.
    var presentFamilies: [SoundFamily] {
        let used = Set(families.values)
        return SoundFamily.order.filter { used.contains($0) }
    }

    struct Member: Identifiable, Equatable {
        let id: Int
        let name: String
        let testNotes: Bool
    }

    /// Éléments d'une famille, dans l'ordre de FL.
    func members(of family: SoundFamily) -> [Member] {
        guard let result else { return [] }
        var out: [Member] = []
        switch result.page {
        case .channelRack:
            for item in result.items where families[item.index] == family {
                out.append(Member(id: item.index, name: item.name, testNotes: item.testNotes))
            }
        case .mixer:
            for track in result.mixer where families[track.index] == family {
                out.append(Member(id: track.index, name: track.name.isEmpty ? "Piste \(track.index)" : track.name,
                                  testNotes: false))
            }
        }
        return out
    }

    /// Couleur prévue de chaque élément (dégradés répartis dans l'ordre final).
    var plannedColors: [Int: RGBColor] {
        guard let result else { return [:] }
        let order: [Int]
        switch result.page {
        case .channelRack:
            let channels = result.channels.sorted { $0.index < $1.index }
            order = RegroupPlan.make(order: channels.map { families[$0.index] }).final
        case .mixer:
            order = result.mixer.map(\.index)
        }
        return OrganizerApplier.plannedColors(families: families, styles: styles, order: order)
    }

    func style(of family: SoundFamily) -> FamilyStyle {
        styles[family] ?? FamilyStyles.initial[family] ?? FamilyStyle(color: NameColorPayload.defaultColor)
    }

    func updateStyle(_ family: SoundFamily, _ change: (inout FamilyStyle) -> Void) {
        var updated = self.style(of: family)
        change(&updated)
        styles[family] = updated
    }

    var doneText: String {
        result?.page == .mixer ? "C'est fait : les pistes du Mixer sont colorées."
                               : "C'est fait : les sons sont colorés et regroupés par famille."
    }

    func apply() {
        guard phase == .preview, let result, let link else { return }
        env.saveStyles(styles)
        phase = .applying
        let applier = OrganizerApplier(link: link, moveUp: env.moveUp(link))
        let families = self.families, styles = self.styles
        queue.async { [weak self] in
            let outcome = applier.apply(result: result, families: families, styles: styles)
            DispatchQueue.main.async {
                self?.snapshot = outcome.snapshot
                self?.phase = .applied(outcome.error)
            }
        }
    }

    /// « Revenir comme avant » : après l'application, ou pour finir un retour interrompu.
    var canUndo: Bool {
        guard snapshot != nil else { return false }
        switch phase {
        case .applied: return true
        case .undone(let error): return error != nil
        default: return false
        }
    }

    func undo() {
        guard canUndo, let snapshot, let link else { return }
        phase = .undoing
        let applier = OrganizerApplier(link: link, moveUp: env.moveUp(link))
        queue.async { [weak self] in
            let outcome = applier.undo(snapshot)
            DispatchQueue.main.async {
                self?.snapshot = outcome.snapshot
                self?.phase = .undone(outcome.error)
            }
        }
    }

    /// Arrête l'écoute (la session remet FL comme avant) et ferme la fenêtre.
    func close() {
        guard !closed else { return }
        closed = true
        session?.cancel()
        session = nil
        let done = onClose
        onClose = nil
        done?()
    }
}

/// Le panneau de l'Organiser : un seul à la fois, détruit à la fermeture.
enum OrganizerWindow {
    private static var panel: NSPanel?
    /// Le contrôleur affiché (nil quand la fenêtre est fermée).
    private(set) static var controller: OrganizerController?
    private static let delegate = Delegate()

    private final class Delegate: NSObject, NSWindowDelegate {
        func windowWillClose(_ notification: Notification) { OrganizerWindow.close() }
    }

    /// Ouvre l'Organiser (ou le ramène devant). Fil principal.
    static func open(env: OrganizerEnvironment = .live()) {
        if let panel {
            panel.orderFrontRegardless()
            panel.makeKey()
            return
        }
        let controller = OrganizerController(env: env)
        controller.onClose = { OrganizerWindow.close() }
        let host = NSHostingView(rootView: OrganizerView(controller: controller))
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: OrganizerView.width, height: OrganizerView.height),
                        styleMask: [.titled, .closable, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.title = "Organiser"
        p.isFloatingPanel = true
        p.level = .floating
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.fullScreenAuxiliary]
        p.contentView = host
        p.delegate = delegate
        p.center()
        panel = p
        self.controller = controller
        p.orderFrontRegardless()
        p.makeKey()
        controller.start()
    }

    /// Ferme et lâche tout ; l'écoute en cours s'arrête et FL est remis comme avant.
    static func close() {
        guard let p = panel else { return }
        let c = controller
        panel = nil
        controller = nil
        c?.close()
        p.delegate = nil
        p.orderOut(nil)
        p.contentView = nil
        CreatorPresence.releaseMemory()
    }
}

struct OrganizerView: View {
    static let width: CGFloat = 460
    static let height: CGFloat = 560

    @ObservedObject var controller: OrganizerController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text(controller.title).font(.system(size: 15, weight: .semibold))
                Spacer()
            }
            content
        }
        .padding(18)
        .frame(width: Self.width, height: Self.height, alignment: .top)
    }

    private static func listeningText(_ done: Int, _ total: Int) -> String {
        total == 0 ? "Préparation de l'écoute…" : "Écoute \(min(done + 1, total)) / \(total)"
    }

    @ViewBuilder private var content: some View {
        switch controller.phase {
        case .starting:
            working("Préparation…")
        case .listening(let done, let total):
            VStack(alignment: .leading, spacing: 10) {
                Text(Self.listeningText(done, total)).font(.system(size: 13, weight: .medium))
                ProgressView(value: Double(done), total: Double(max(total, 1)))
                Text("Chaque son joue seul, sans que tu l'entendes. Ne touche pas à FL pendant l'écoute ; Échap l'arrête.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button("Arrêter") { controller.close() }.keyboardShortcut(.cancelAction)
                }
            }
        case .preview:
            preview
        case .applying:
            working("Application dans FL… Ne touche pas à FL.")
        case .undoing:
            working("Retour comme avant…")
        case .applied(let error):
            ending(error?.message ?? controller.doneText, ok: error == nil)
        case .undone(let error):
            ending(error?.message ?? "FL est revenu comme avant.", ok: error == nil)
        case .failed(let message):
            ending(message, ok: false)
        }
    }

    private func working(_ text: String) -> some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(text).font(.system(size: 13))
        }
    }

    private func ending(_ text: String, ok: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(ok ? Color.green : Color.orange)
                Text(text).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if controller.canUndo {
                    Button("Revenir comme avant") { controller.undo() }
                }
                Spacer()
                Button("Fermer") { controller.close() }.keyboardShortcut(.defaultAction)
            }
        }
    }

    private var hint: String {
        controller.result?.page == .mixer
            ? "Chaque piste prend la famille des sons qui y sont reliés. Clique sur une famille pour la changer."
            : "Vérifie chaque son et clique sur sa famille pour la changer. Appliquer colore et regroupe les sons par famille."
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(hint)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    let colors = controller.plannedColors
                    ForEach(controller.presentFamilies, id: \.self) { family in
                        FamilySection(controller: controller, family: family, colors: colors)
                    }
                }
            }
            HStack {
                Button("Annuler") { controller.close() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Appliquer") { controller.apply() }.keyboardShortcut(.defaultAction)
            }
        }
    }
}

/// Une famille de l'aperçu : son réglage (une couleur ou un dégradé) et ses sons.
private struct FamilySection: View {
    @ObservedObject var controller: OrganizerController
    let family: SoundFamily
    let colors: [Int: RGBColor]
    @State private var pickingFirst = false
    @State private var pickingLast = false

    private var fadeOn: Binding<Bool> {
        Binding(get: { controller.style(of: family).fade != nil }, set: { on in
            controller.updateStyle(family) { style in
                style.fade = on ? GradientField.defaultLast(for: style.color) : nil
            }
        })
    }

    var body: some View {
        let style = controller.style(of: family)
        let members = controller.members(of: family)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: family.symbol).frame(width: 18)
                Text(family.label).font(.system(size: 13, weight: .semibold))
                Text("\(members.count)").foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: fadeOn) {
                    Text("Une couleur").tag(false)
                    Text("Dégradé").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .controlSize(.small)
                swatch(style.color, picking: $pickingFirst) { picked in
                    controller.updateStyle(family) { $0.color = picked }
                }
                if let fade = style.fade {
                    swatch(fade, picking: $pickingLast) { picked in
                        controller.updateStyle(family) { $0.fade = picked }
                    }
                }
            }
            ForEach(members) { member in
                row(member, color: colors[member.id] ?? style.color)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
    }

    private func row(_ member: OrganizerController.Member, color: RGBColor) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(swiftColor(color))
                .frame(width: 12, height: 12)
            Text(member.name.isEmpty ? "(sans nom)" : member.name).lineLimit(1)
            if member.testNotes {
                Image(systemName: "music.note")
                    .foregroundStyle(.secondary)
                    .help("Muet dans le pattern : classé avec deux notes d'essai. Vérifie sa famille.")
            }
            Spacer()
            Menu {
                ForEach(SoundFamily.order, id: \.self) { choice in
                    Button(choice.label) { controller.families[member.id] = choice }
                }
            } label: {
                Text(family.label).font(.system(size: 11))
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .fixedSize()
            .help("Changer la famille de ce son")
        }
        .font(.system(size: 12))
    }

    private func swatch(_ color: RGBColor, picking: Binding<Bool>, set: @escaping (RGBColor) -> Void) -> some View {
        Button { picking.wrappedValue = true } label: {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(swiftColor(color))
                .frame(width: 22, height: 16)
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.primary.opacity(0.2)))
        }
        .buttonStyle(.plain)
        .help("#" + color.hex + " : choisir dans la roue des couleurs de FL")
        .popover(isPresented: picking, arrowEdge: .bottom) {
            FLColorSelector(initial: color) { picked in
                set(picked)
                picking.wrappedValue = false
            }
        }
    }
}
