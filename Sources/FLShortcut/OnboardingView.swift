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
        let host = NSHostingView(rootView: root)
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: onboardingSize.width, height: onboardingSize.height),
                         styleMask: [.titled, .closable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true
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
    /// Mode capture : clavier montré comme autorisé.
    @State private var demoAccess = false

    private var accessOK: Bool { demoAccess || status.accessibilityOK }
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
                                    detail: nil,
                                    state: accessOK ? .allowed : askedPermission ? .waiting : .toAllow)]
        if #available(macOS 14.2, *) {
            items.append(PermissionItem(id: "son", symbol: "waveform", tint: .pink, title: String(localized: "Son de FL"),
                                        detail: String(localized: "pour l'Organiser"),
                                        state: permissions.audioGranted ? .allowed
                                            : askedPermission && permissions.stage == .audio ? .waiting : .toAllow))
        }
        return items
    }

    private var permissionStep: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            Text("FL Shortcuts")
                .font(.system(size: 34, weight: .bold))
                .morphIn(0)

            PlateRows(data: permissionItems) { item in
                HStack(spacing: 12) {
                    SectionIcon(symbol: item.symbol, tint: item.tint, size: 28)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(item.title).font(.system(size: 14, weight: .semibold))
                        if let detail = item.detail {
                            Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 8)
                    PermissionPill(state: item.state)
                }
                .padding(.horizontal, 12)
                .frame(height: 52)
                .accessibilityElement(children: .combine)
            }
            .frame(width: 400)
            .padding(.top, 28)
            .morphIn(1)

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                if accessOK {
                    Button { advance() } label: {
                        Text("Continuer").frame(minWidth: 220)
                    }
                    .primaryButton()
                    .heroControlSize()
                    .keyboardShortcut(.defaultAction)
                    .transition(Motion.pageMorph)
                } else {
                    Button {
                        askedPermission = true
                        AccessibilityGuide.start(panel: false)      // seule la page de réglages s'ouvre
                    } label: {
                        Text("Tout autoriser…").frame(minWidth: 220)
                    }
                    .primaryButton()
                    .heroControlSize()
                    .keyboardShortcut(.defaultAction)
                    .transition(Motion.pageMorph)
                    Button("Plus tard") { advance() }
                        .buttonStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            .morphIn(2)
        }
        // Clavier autorisé : les états et les boutons changent en fondu.
        .motion(Motion.morph, value: accessOK)
        .motion(Motion.morph, value: askedPermission)
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
                .font(.system(size: 28, weight: .bold))
                .morphIn(0)

            HStack(alignment: .top, spacing: 18) {
                PlateRows(data: linkSteps) { step in
                    StepRow(number: step.id, done: step.done, text: step.text)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .frame(minHeight: 48)
                }
                .frame(maxWidth: .infinity)
                MIDISettingsImage(width: 220)
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

    private var color: Color {
        switch state {
        case .toAllow: return .secondary
        case .waiting: return .accentColor
        case .allowed: return .green
        }
    }

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.14)))
            .overlay(Capsule().strokeBorder(color.opacity(0.28), lineWidth: 1))
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
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.green)
                } else {
                    Text("\(number)")
                        .font(.system(size: 12, weight: .bold).monospacedDigit())
                        .foregroundStyle(Color.white)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.accentColor))
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

    /// Dessin de secours, à plat, d'après l'icône : dégradé de la marque, touche ⌃ translucide derrière, touche
    /// blanche avec une forme d'onde devant. Marge de 10 % comme la grille des icônes macOS.
    private var drawn: some View {
        GeometryReader { geo in
            drawing(scale: geo.size.width / 96)
        }
        .accessibilityHidden(true)
    }

    private func drawing(scale s: CGFloat) -> some View {
        let brand = LinearGradient(colors: Appearance.brand, startPoint: .topLeading, endPoint: .bottomTrailing)
        return ZStack {
            RoundedRectangle(cornerRadius: 18 * s, style: .continuous)
                .fill(brand)
                .padding(9.5 * s)
            RoundedRectangle(cornerRadius: 9 * s, style: .continuous)
                .fill(Color.white.opacity(0.35))
                .frame(width: 30 * s, height: 30 * s)
                .overlay(Image(systemName: "chevron.up")
                    .font(.system(size: 12 * s, weight: .bold))
                    .foregroundStyle(Color.white))
                .offset(x: 12 * s, y: -12 * s)
            RoundedRectangle(cornerRadius: 11 * s, style: .continuous)
                .fill(Color.white.opacity(0.94))
                .frame(width: 36 * s, height: 36 * s)
                .overlay(Image(systemName: "waveform")
                    .font(.system(size: 17 * s, weight: .bold))
                    .foregroundStyle(brand))
                .offset(x: -7 * s, y: 9 * s)
        }
    }
}
