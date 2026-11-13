// Accueil sobre, enchaîné (maquette validée le 28/10) : 1. les autorisations (clavier, son de FL), chacune avec son
// état (« À autoriser », « En attente… », « Autorisé ») ; 2. hors mode léger, relier FL Studio en quatre étapes d'une
// ligne (`LinkGuide`) et la fenêtre MIDI Settings entourée, avec un vrai statut (« En attente de FL Studio… » →
// « FL Studio est relié ») ; 3. le guide, dans la même fenêtre ; à la fin, la fenêtre principale s'ouvre. Fond plein,
// cartes en verre devant ; fondus entre les écrans, aucune animation continue, aucune phrase d'explication.
// Audit : REL-23 (accueil marqué « vu » seulement après un choix ; permission demandée depuis l'accueil),
//         tests utilisateurs (montrer où cliquer dans MIDI Settings, confirmer que ça marche).
import AppKit
import SwiftUI

/// Taille fixe de la fenêtre d'accueil : celle du guide, qui s'y enchaîne sans que la fenêtre bouge.
private let onboardingSize = CGSize(width: 640, height: 540)

final class OnboardingWindow {
    static let shared = OnboardingWindow()
    private var window: NSWindow?
    private var closeObserver: NSObjectProtocol?

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let root = OnboardingView { [weak self] in self?.finish() }
            .environmentObject(AppStatus.shared)
            .environmentObject(MIDILink.shared)
            .environmentObject(FLMonitor.shared)
            .background(ArrowCursorKeeper())            // 13/11 : la flèche de l'app, même FL devant
        let host = NSHostingView(rootView: root)
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: onboardingSize.width, height: onboardingSize.height),
                         styleMask: [.titled, .closable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true
        w.backgroundColor = Swiss.NS.background             // style suisse : fond plein du thème, comme toute l'app
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.isReleasedWhenClosed = false
        w.title = String(localized: "Bienvenue dans FL Shortcuts")
        w.animationBehavior = .alertPanel          // ouverture « zoom » douce, comme les fenêtres d'accueil d'Apple
        w.contentView = host
        w.center()
        window = w
        // Fermée (y compris par le bouton rouge) : la vue et ses abonnements sont libérés, plus rien ne tourne.
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification,
                                                               object: w, queue: .main) { [weak self, weak w] _ in
            DispatchQueue.main.async {
                guard let self, let w else { return }
                AppResume.shared.onboardingStage = nil      // accueil fermé : rien à reprendre ici
                w.contentView = nil
                if self.window === w { self.window = nil }
                if let o = self.closeObserver { NotificationCenter.default.removeObserver(o) }
                self.closeObserver = nil
            }
        }
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    var isOpen: Bool { window != nil }

    /// Pendant la question du son de macOS : l'accueil se retire (il revient avec `bringToFront`).
    func stepAside() { window?.orderOut(nil) }

    /// Clavier autorisé dans Réglages Système : l'accueil revient devant, prêt pour la suite.
    func bringToFront() {
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Fin de l'accueil (guide fini ou passé) : la fenêtre principale s'ouvre pendant que l'accueil s'efface en fondu.
    func finish() {
        UserDefaults.standard.set(true, forKey: "didOnboard")      // après un choix (REL-23)
        UserDefaults.standard.set(true, forKey: "guideSeen")       // le guide vient d'être vu ici
        NotificationCenter.default.post(name: AccountLink.openEditor, object: nil)
        fadeOutAndClose()
    }

    private func fadeOutAndClose() {
        guard let w = window else { return }
        window = nil
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.45
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            w.animator().alphaValue = 0
        }, completionHandler: {
            w.close()
            w.alphaValue = 1
        })
    }

    /// Mode capture (mesure de la CI) : « clavier » (« clavier lent » : au ralenti) l'ouvre de nouveau sur l'écran du
    /// clavier, sans rien marquer ; « fin » la ferme. Les autres ordres vont à la vue (OnboardingView).
    func capture(_ command: String) {
        let words = command.split(separator: " ")
        guard let first = words.first else { return }
        switch first {
        case "clavier":
            window?.close()
            window = nil
            DebugSnapshot.slowMotion = words.contains("lent") ? 10 : 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.show() }
        case "fin":
            DebugSnapshot.slowMotion = 1
            window?.close()
            window = nil
        default:
            break
        }
    }
}

/// Accueil, en un seul enchaînement dans la même fenêtre : autoriser le clavier, relier FL (hors mode léger), puis le
/// guide ; à la fin, la fenêtre principale s'ouvre. Chaque écran se fond dans le suivant ; fond plein de la fenêtre.
struct OnboardingView: View {
    @EnvironmentObject var status: AppStatus
    @EnvironmentObject var link: MIDILink
    @EnvironmentObject var fl: FLMonitor
    let onFinish: () -> Void

    private enum Stage: String, Hashable { case keyboard, link, guide }

    @State private var stage = Stage.keyboard
    @State private var guidePage = 0
    @State private var askedPermission = false
    @State private var installed = false
    /// FL ouvert quand le lien a été posé : il ne le lira qu'après avoir été rouvert.
    @State private var flOpenAtInstall = false
    /// Mode capture : clavier montré comme autorisé.
    @State private var demoAccess = false

    /// Clavier autorisé : relu par `AppStatus` (toutes les 2 s) ou par l'accueil lui-même (chaque seconde).
    private var accessOK: Bool { demoAccess || status.accessibilityOK || permissions.granted }
    /// Relecture des autorisations, chaque seconde, tant qu'il en manque une sur cet écran (01/11 : « À autoriser »
    /// restait affiché une fois autorisé, quand la demande venait d'une copie d'avant la relance).
    private static let tick = Timer.publish(every: 1, tolerance: 0.3, on: .main, in: .common).autoconnect()
    /// Autorisations demandées ensemble (clavier, puis son de FL).
    @ObservedObject private var permissions = AccessibilityGuide.shared

    var body: some View {
        ZStack {
            switch stage {
            case .keyboard:
                permissionStep
                    .padding(.horizontal, 40)
                    .padding(.top, 40)                  // la barre de titre est transparente
                    .padding(.bottom, 34)
                    .transition(Motion.pageMorph)
            case .link:
                linkStep
                    .padding(.horizontal, 40)
                    .padding(.top, 52)
                    .padding(.bottom, 34)
                    .transition(Motion.pageMorph)
            case .guide:
                GuideView(page: $guidePage, close: onFinish)
                    .transition(Motion.pageMorph)
            }
        }
        .frame(width: onboardingSize.width, height: onboardingSize.height)
        .motion(Motion.morph, value: stage)
        .onAppear {
            installed = link.snapshot.hasKey
            if !installed, !DebugSnapshot.enabled { installLink(asking: false) }
            // Relancée par « Quitter et rouvrir » : l'accueil reprend à l'écran où il en était, sans transition.
            if let resume = AppResume.shared.takeOnboarding(), let saved = Stage(rawValue: resume.stage) {
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) {
                    stage = saved
                    guidePage = resume.guidePage
                }
            }
            AppResume.shared.onboardingStage = stage.rawValue
            AppResume.shared.guidePage = guidePage
        }
        .onChange(of: stage) { AppResume.shared.onboardingStage = $0.rawValue }
        .onChange(of: guidePage) { AppResume.shared.guidePage = $0 }
        .onChange(of: status.accessibilityOK) { ok in
            if ok, stage == .keyboard { OnboardingWindow.shared.bringToFront() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissions.refresh()                          // une autorisation donnée dans les Réglages pendant ce temps
        }
        .onReceive(Self.tick) { _ in
            guard stage == .keyboard, !DebugSnapshot.enabled, !(accessOK && permissions.audioGranted) else { return }
            permissions.refresh()
        }
        .onReceive(DebugSnapshot.publisher(DebugSnapshot.onboarding)) { note in
            // Mode capture : « autorise » (clavier montré comme autorisé), « guide lent » (passage au guide au ralenti).
            let words = (note.object as? String ?? "").split(separator: " ")
            if words.first == "autorise" { demoAccess = true }
            if words.first == "guide" {
                DebugSnapshot.slowMotion = words.contains("lent") ? 10 : 1
                stage = .guide
            }
            // « partie 2 lent » : une partie du guide, au ralenti.
            if words.first == "partie", words.count > 1, let n = Int(words[1]) {
                DebugSnapshot.slowMotion = words.contains("lent") ? 10 : 1
                guidePage = max(0, min(n, GuideContent.count - 1))
            }
        }
    }

    /// Écran suivant : relier FL (hors mode léger), puis le guide.
    private func advance() {
        switch stage {
        case .keyboard: stage = AppMode.light ? .guide : .link
        case .link: stage = .guide
        case .guide: onFinish()
        }
    }

    // MARK: Étape 1 — autorisations (clavier, son de FL), demandées ensemble

    /// Ce qui est demandé, d'un coup d'œil : le clavier, puis le son de FL (pour l'Organiser), chacun avec son état.
    private var permissionItems: [PermissionItem] {
        var items = [PermissionItem(id: "clavier", symbol: "keyboard", tint: .blue, title: String(localized: "Clavier"),
                                    detail: String(localized: "Pour tes raccourcis dans FL."),
                                    state: accessOK ? .allowed : askedPermission || permissions.asking ? .waiting : .toAllow)]
        if #available(macOS 14.2, *) {
            items.append(PermissionItem(id: "son", symbol: "waveform", tint: .pink, title: String(localized: "Son de FL"),
                                        // 02/11 : plus de « pour l'Organiser » (demande du propriétaire).
                                        detail: permissions.audioInSettings && !permissions.audioGranted
                                            ? String(localized: "À cocher dans les Réglages.") : String(localized: "Pour écouter tes sons."),
                                        state: permissions.audioGranted ? .allowed
                                            : permissions.asking && permissions.stage == .audio ? .waiting : .toAllow))
        }
        return items
    }

    /// Style suisse (maquette validée le 01/11) : « FL Shortcuts » en très grand souligné de blanc, puis une ligne par
    /// autorisation (numéro, nom en gras, détail gris, état en petites capitales : blanc si autorisé, rouge sinon), le
    /// bouton blanc en bas à droite.
    private var permissionStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            // Maquette du 05/11 : le rond (remis à sa demande) et « fl shortcuts » en très grand avec son point carré.
            HStack(alignment: .bottom, spacing: 18) {
                BrandRound().frame(width: 76, height: 76)
                SwissPageTitle(text: "FL Shortcuts", size: 64)
            }
            .padding(.top, 8)
            .morphIn(0)

            // Les autorisations dans une carte : le nom en gras, une phrase dessous, l'état à droite.
            VStack(spacing: 0) {
                ForEach(Array(permissionItems.enumerated()), id: \.element.id) { index, item in
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title).font(Swiss.font(18)).tracking(-0.3)
                            if let detail = item.detail {
                                Text(detail).font(.system(size: 13)).foregroundStyle(Swiss.gray)
                            }
                        }
                        Spacer(minLength: 8)
                        if item.state == .toAllow {
                            // À autoriser : un bouton qui se soulève sur son encoche rouge (02/11, « réactifs, comme
                            // dans Macro ») ; il demande cette autorisation-là.
                            Button(String(localized: "À autoriser")) { ask(item.id) }
                                .buttonStyle(StampButtonStyle())
                        } else {
                            PermissionPill(state: item.state)
                        }
                    }
                    .frame(minHeight: 64)
                    .overlay(alignment: .top) {
                        if index > 0 { Rectangle().fill(Swiss.faint).frame(height: 1) }
                    }
                    .accessibilityElement(children: .combine)
                }
                linkRow
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 4)
            .background(Rectangle().fill(Swiss.background))
            .overlay(Rectangle().strokeBorder(Swiss.line, lineWidth: 1))
            .swissCard()
            .morphIn(1)

            Spacer(minLength: 0)

            // 12/11 (« tout en bas, faut qu'il y ait un bouton à autoriser au lieu de continuer… même s'il y en a un des
            // deux qui est autorisé, il faut que le deuxième aussi soit autorisé pour qu'on puisse rentrer ») : on n'entre
            // qu'avec toutes les autorisations ; avant, le grand bouton demande celle qui manque (plus de « Plus tard »).
            VStack(alignment: .trailing, spacing: 10) {
                if allAllowed {
                    Button { advance() } label: {
                        Text("Continuer").frame(minWidth: 220)
                    }
                    .primaryButton()
                    .heroControlSize()
                    .keyboardShortcut(.defaultAction)
                    .transition(Motion.pageMorph)
                } else {
                    Button { askNext() } label: {
                        Text("Autoriser").frame(minWidth: 220)
                    }
                    .primaryButton()
                    .heroControlSize()
                    .keyboardShortcut(.defaultAction)
                    .transition(Motion.pageMorph)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .morphIn(2)
        }
        // Clavier autorisé : les états et les boutons changent en fondu.
        .motion(Motion.morph, value: accessOK)
        .motion(Motion.morph, value: allAllowed)
        .motion(Motion.morph, value: askedPermission)
    }

    /// 13/11 (« installer le lien midi dès l'installation du logiciel ») : le lien avec FL, posé tout seul à l'arrivée
    /// sur l'accueil dès que le dossier de FL existe (`installIfMissing`) ; sinon « À installer » le pose (dossier de
    /// FL demandé s'il n'est pas à sa place). Il n'empêche jamais d'entrer : FL peut ne pas être encore installé.
    private var linkRow: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Lien avec FL").font(Swiss.font(18)).tracking(-0.3)
                Text(installed && flOpenAtInstall ? String(localized: "Quitte et rouvre FL pour qu'il le voie.")
                                                  : String(localized: "Pour les actions de FL et l'Organiser."))
                    .font(.system(size: 13)).foregroundStyle(Swiss.gray)
            }
            Spacer(minLength: 8)
            if installed {
                Text("Installé").swissLabel(Swiss.text)
            } else {
                Button(String(localized: "À installer")) { installLink(asking: true) }
                    .buttonStyle(StampButtonStyle())
            }
        }
        .frame(minHeight: 64)
        .overlay(alignment: .top) { Rectangle().fill(Swiss.faint).frame(height: 1) }
        .accessibilityElement(children: .combine)
    }

    /// Le lien posé : tout seul (`asking` faux : seulement si le dossier de FL est à sa place), ou par « À installer ».
    private func installLink(asking: Bool) {
        guard !link.snapshot.hasKey else {
            installed = true
            return
        }
        let flOpen = NSWorkspace.shared.runningApplications.contains { FLMatcher.isFL(bundleID: $0.bundleIdentifier) }
        let done = asking ? FLScriptInstaller.installWithAlert(quiet: true) : FLScriptInstaller.installIfMissing() != nil
        if done {
            if !asking { MIDILink.shared.reloadKey() }
            MacroLog.shared.write("LINK", asking ? "installed from the welcome screen" : "installed on the welcome screen")
            flOpenAtInstall = flOpen
            if flOpen { status.scriptInstalledWhileFLOpen() }
        }
        installed = done || link.snapshot.hasKey
    }

    /// Toutes les autorisations de la carte sont données : on peut entrer (12/11).
    private var allAllowed: Bool { permissionItems.allSatisfy { $0.state == .allowed } }

    /// « Autoriser » du bas : la première autorisation qui manque, dans l'ordre de la carte (le clavier, puis le son).
    private func askNext() {
        guard let missing = permissionItems.first(where: { $0.state != .allowed }) else { return }
        ask(missing.id)
    }

    /// « À autoriser » d'une ligne : le clavier (avec la suite, comme « Tout autoriser… »), ou le son de FL seul.
    private func ask(_ id: String) {
        if id == "son" {
            AccessibilityGuide.shared.startAudio()
        } else {
            askedPermission = true
            AccessibilityGuide.start(panel: false)
        }
    }

    // MARK: Étape 2 — relier FL Studio (hors mode léger)

    private var linked: Bool { link.status == .linked }

    /// Les étapes de `LinkGuide` : la première cochée une fois le lien installé, les autres une fois FL relié.
    private var linkSteps: [LinkStep] {
        LinkGuide.steps.enumerated().map { index, text in
            LinkStep(id: index + 1, text: text, done: index == 0 ? installed : linked)
        }
    }

    private var linkStep: some View {
        VStack(spacing: 0) {
            Text("Relier FL Studio")
                .font(Swiss.title(35)).tracking(Swiss.titleTracking(35))
                .morphIn(0)

            HStack(alignment: .top, spacing: 18) {
                PlateRows(data: linkSteps) { step in
                    StepRow(number: step.id, done: step.done, text: step.text)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .frame(minHeight: 48)
                }
                .frame(maxWidth: .infinity)
                MIDISettingsCrops()
            }
            .padding(.top, 24)
            .morphIn(1)

            HStack(spacing: 8) {
                if linked {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("FL Studio est relié")
                } else {
                    WaitingRing()
                    Text("En attente de FL Studio…").foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 13))
            .padding(.top, 22)
            .accessibilityElement(children: .combine)
            .morphIn(2)

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                if !installed {
                    Button("Plus tard") { advance() }
                        .secondaryButton()
                }
                Button {
                    if installed {
                        advance()
                    } else {
                        FLScriptInstaller.installWithAlert()
                        installed = link.snapshot.hasKey
                    }
                } label: {
                    Text(installed ? String(localized: "Continuer") : String(localized: "Installer le lien"))
                        .frame(minWidth: 160)
                }
                .primaryButton()
                .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
            .morphIn(3)
        }
        .motion(Motion.morph, value: linked)
    }
}

/// Une autorisation de l'accueil : icône, nom, à quoi elle sert (si besoin), et son état.
private struct PermissionItem: Identifiable {
    let id: String
    let symbol: String
    let tint: Color
    let title: String
    let detail: String?
    let state: PermissionState
}

private enum PermissionState {
    case toAllow, waiting, allowed
}

/// État d'une autorisation en pastille : grise à autoriser, bleue en attente, verte une fois autorisée.
private struct PermissionPill: View {
    let state: PermissionState

    private var label: String {
        switch state {
        case .toAllow: return String(localized: "À autoriser")
        case .waiting: return String(localized: "En attente…")
        case .allowed: return String(localized: "Autorisé")
        }
    }

    /// Style suisse : autorisé en blanc, à autoriser en rouge (ce qui reste à faire), en attente en gris.
    private var color: Color {
        switch state {
        case .toAllow: return Swiss.red
        case .waiting: return Swiss.gray
        case .allowed: return Swiss.text
        }
    }

    var body: some View {
        Text(label).swissLabel(color)
    }
}

/// Une étape pour relier FL Studio.
private struct LinkStep: Identifiable {
    let id: Int
    let text: String
    let done: Bool
}

/// Étape numérotée sur une ligne ; coche verte une fois faite.
private struct StepRow: View {
    let number: Int
    let done: Bool
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(Swiss.background)
                        .frame(width: 20, height: 20)
                        .background(Rectangle().fill(Swiss.text))
                } else {
                    Text("\(number)")
                        .font(Swiss.font(12).monospacedDigit())
                        .foregroundStyle(Swiss.background)
                        .frame(width: 20, height: 20)
                        .background(Rectangle().fill(Swiss.red))
                }
            }
            .frame(width: 22)
            .accessibilityHidden(true)
            Text(text).font(.system(size: 13.5)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Étape \(number) : \(text)")
        .accessibilityValue(done ? String(localized: "fait") : String(localized: "à faire"))
    }
}

/// Le rond de l'accueil (05/11 : « je veux que tu remettes le rond ») : le grand cercle décalé à l'encre, un jour, le
/// rond rouge (le rond de la barre des menus, en couleurs) ; sous Orange, un trait noir autour du rond et son ombre
/// noire décalée, comme les boutons. Dessiné sur une toile de 1024 ramenée à la taille donnée.
struct BrandRound: View {
    var body: some View {
        let ink = Swiss.text
        let background = Swiss.background
        let orange = AppTheme.current == .orange
        Canvas { ctx, size in
            let k = min(size.width, size.height) / 1024
            func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> Path {
                Path(ellipseIn: CGRect(x: (cx - r) * k, y: (cy - r) * k, width: 2 * r * k, height: 2 * r * k))
            }
            ctx.stroke(circle(590, 440, 365), with: .color(ink), lineWidth: 70 * k)
            ctx.fill(circle(470, 580, 345), with: .color(background))
            if orange { ctx.fill(circle(510, 620, 290), with: .color(.black)) }
            ctx.fill(circle(470, 580, 290), with: .color(Swiss.brandRed))
            if orange { ctx.stroke(circle(470, 580, 290), with: .color(.black), lineWidth: 40 * k) }
        }
        .accessibilityHidden(true)
    }
}

/// Icône de l'appli (accueil, panneau de la barre des menus, guide d'autorisation).
struct AppIcon: View {
    /// Icône de l'app (Resources/AppIcon.icns) ; dessin de secours si l'app tourne hors de son bundle.
    private static let bundleIcon: NSImage? = {
        guard Bundle.main.url(forResource: "AppIcon", withExtension: "icns") != nil else { return nil }
        return NSApp.applicationIconImage
    }()

    var body: some View {
        if let icon = Self.bundleIcon {
            Image(nsImage: icon).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                .accessibilityHidden(true)
        } else {
            drawn
        }
    }

    /// Dessin de secours, à plat, d'après l'icône (« fl. » du 05/11, marque/icone-app-fl.svg) : tuile noire aux coins
    /// arrondis, « fl » en blanc, le point carré en rouge, en bas à gauche. Marge de 10 % comme la grille des icônes.
    private var drawn: some View {
        GeometryReader { geo in
            drawing(side: geo.size.width)
        }
        .accessibilityHidden(true)
    }

    private func drawing(side: CGFloat) -> some View {
        let k = side / 1024
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 185 * k, style: .continuous)
                .fill(Color.black)
                .frame(width: 824 * k, height: 824 * k)
                .offset(x: 100 * k, y: 100 * k)
            Text(verbatim: "fl")
                .font(Swiss.font(470 * k))
                .tracking(-470 * k * 0.065)
                .foregroundStyle(Color.white)
                .fixedSize()
                .frame(width: 330 * k, height: 470 * k, alignment: .bottomLeading)
                .offset(x: 210 * k, y: 324 * k)
            Rectangle()
                .fill(Swiss.brandRed)
                .frame(width: 97 * k, height: 94 * k)
                .offset(x: 557 * k, y: 700 * k)
        }
        .frame(width: side, height: side, alignment: .topLeading)
    }
}
