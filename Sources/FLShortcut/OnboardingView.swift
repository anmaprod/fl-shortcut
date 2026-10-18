// Accueil sobre, enchaîné : 1. autoriser le clavier (guide Accessibilité, détection automatique) ; 2. hors mode
// léger, relier FL Studio avec un vrai statut (« En attente de FL Studio… » → « FL Studio est relié ») et « Tester » ;
// 3. le guide, dans la même fenêtre ; à la fin, la fenêtre principale s'ouvre. Fondus entre les écrans, aucune
// animation continue.
// macOS 26 : lueurs aux couleurs de l'icône en haut de la fenêtre (dégradés statiques), que réfractent les touches
// en verre et le grand bouton en verre teinté ; verre coupé (préférence, Réduire la transparence) : fond uni.
// Audit : REL-23 (accueil marqué « vu » seulement après un choix ; permission demandée depuis l'accueil),
//         tests utilisateurs (rassurer sur la vie privée, montrer où cliquer dans MIDI Settings, confirmer que
//         ça marche).
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
        w.title = "Bienvenue dans FL Shortcuts"
        w.animationBehavior = .alertPanel          // ouverture « zoom » douce, comme les fenêtres d'accueil d'Apple
        w.contentView = host
        w.center()
        window = w
        // Fermée (y compris par le bouton rouge) : la vue et ses abonnements sont libérés, plus rien ne tourne.
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification,
                                                               object: w, queue: .main) { [weak self, weak w] _ in
            DispatchQueue.main.async {
                guard let self, let w else { return }
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
/// guide ; à la fin, la fenêtre principale s'ouvre. Chaque écran se fond dans le suivant (l'icône de l'app glisse de
/// l'écran du clavier jusqu'en haut du guide) ; le fond suit la couleur de la page.
struct OnboardingView: View {
    @EnvironmentObject var status: AppStatus
    @EnvironmentObject var link: MIDILink
    @EnvironmentObject var fl: FLMonitor
    let onFinish: () -> Void

    private enum Stage: Hashable { case keyboard, link, guide }

    @State private var stage = Stage.keyboard
    @State private var guidePage = 0
    @State private var askedPermission = false
    @State private var installed = false
    /// Mode capture : clavier montré comme autorisé.
    @State private var demoAccess = false
    /// L'icône de l'app, de l'écran du clavier jusqu'en haut du guide.
    @Namespace private var morph

    private var accessOK: Bool { demoAccess || status.accessibilityOK }
    /// Autorisations demandées ensemble (clavier, puis fenêtre de FL).
    @ObservedObject private var permissions = AccessibilityGuide.shared

    var body: some View {
        ZStack {
            switch stage {
            case .keyboard:
                permissionStep
                    .padding(.horizontal, 56)
                    .padding(.top, 44)                  // la barre de titre est transparente
                    .padding(.bottom, 28)
                    .transition(Motion.pageMorph)
            case .link:
                linkStep
                    .padding(.horizontal, 44)
                    .padding(.top, 44)
                    .padding(.bottom, 28)
                    .transition(Motion.pageMorph)
            case .guide:
                GuideView(page: $guidePage, close: onFinish, drawsBackdrop: false, appIconMorph: morph)
                    .transition(Motion.pageMorph)
            }
        }
        .frame(width: onboardingSize.width, height: onboardingSize.height)
        .background { GuideBackdrop(page: stage == .guide ? guidePage : 0) }
        .motion(Motion.morph, value: stage)
        .onAppear { installed = link.snapshot.hasKey }
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

    // MARK: Étape 1 — autorisations (clavier, fenêtre de FL), demandées ensemble

    private var permissionStep: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            AppIcon()
                .matchedGeometryEffect(id: "appIcon", in: morph)
                .frame(width: 84, height: 84)                // place pour la liste des autorisations
                .shadow(color: Appearance.brand[1].opacity(0.4), radius: 22, y: 10)
                .morphIn(0)
            Text("FL Shortcuts")
                .font(.system(size: 34, weight: .bold))
                .padding(.top, 12)
                .morphIn(1)
            Text(accessOK ? "Le clavier est autorisé : tout est prêt."
                          : "Une seule fois, tout ce dont FL Shortcuts a besoin, demandé ensemble.")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 420)
                .padding(.top, 8)
                .id(accessOK)                           // le texte change en fondu
                .transition(.opacity)
                .morphIn(2)

            permissionList
                .padding(.top, 14)
                .morphIn(3)

            Spacer(minLength: 14)

            VStack(spacing: 10) {
                if accessOK {
                    Label("Clavier autorisé", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.green)
                        .transition(Motion.pageMorph)
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
                        AccessibilityGuide.start()
                    } label: {
                        Text("Tout autoriser…").frame(minWidth: 220)
                    }
                    .primaryButton()
                    .heroControlSize()
                    .keyboardShortcut(.defaultAction)
                    .transition(Motion.pageMorph)
                    if askedPermission {
                        Text("Suis le petit panneau en bas à droite : clavier, puis fenêtre de FL. C'est détecté tout seul.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .transition(.opacity)
                    }
                    Button("Plus tard") { advance() }
                        .buttonStyle(.link)
                        .font(.system(size: 12))
                }
            }
            .frame(maxWidth: 380)
            .morphIn(4)

            Spacer(minLength: 14)

            Label("Tes touches ne sont lues que quand FL Studio est au premier plan. Rien n'est enregistré ni envoyé, sauf ce que tu publies toi-même dans la Communauté.",
                  systemImage: "lock")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(maxWidth: 440)
                .morphIn(5)
        }
        // Clavier autorisé : le texte et les boutons changent en fondu.
        .motion(Motion.morph, value: accessOK)
        .motion(Motion.morph, value: askedPermission)
    }

    /// Ce qui est demandé, d'un coup d'œil : le clavier (indispensable), la fenêtre de FL (conseillée), et le son de
    /// FL que macOS demande lui-même à la première écoute de l'Organiser.
    private var permissionList: some View {
        VStack(alignment: .leading, spacing: 8) {
            permissionRow("keyboard", .blue, "Clavier", "Tes raccourcis dans FL Studio (indispensable)", done: accessOK)
            if ScreenLook.available {
                permissionRow("macwindow", .purple, "Fenêtre de FL", "Retrouver ses boutons par leur nom, au moment du clic",
                              done: permissions.screenGranted)
            }
            permissionRow("waveform", .pink, "Son de FL", "Organiser : macOS le demande une fois, à la première écoute",
                          done: nil)
        }
        .frame(maxWidth: 400)
    }

    private func permissionRow(_ symbol: String, _ tint: Color, _ title: String, _ detail: String,
                               done: Bool?) -> some View {
        HStack(spacing: 10) {
            SectionIcon(symbol: symbol, tint: tint, size: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let done {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(done ? Color.green : Color.secondary)
                    .contentTransition(.opacity)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Étape 2 — relier FL Studio (hors mode léger)

    private var linked: Bool { link.status == .linked }

    private var linkStatusText: String {
        if linked { return "FL Studio est relié" }
        return installed ? "En attente de FL Studio… fais les étapes 2 et 3" : "FL Studio pas encore relié"
    }

    private var linkStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Relier FL Studio").font(.title2.weight(.semibold))
                Text("À faire une seule fois.").font(.system(size: 13)).foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    StepRow(number: 1, done: installed, text: "Installer le lien dans FL Studio (bouton ci-dessous), puis redémarrer FL.")
                    StepRow(number: 2, done: linked, text: "FL trouve « FL Shortcuts Link » en démarrant et le relie tout seul. C'est détecté ici dès que c'est fait.")
                    StepRow(number: 3, done: linked, text: "Seulement si rien ne se passe : Options › MIDI Settings, entrée « FL Shortcuts Link », Controller type « FL Shortcuts », même numéro de Port en entrée et en sortie.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                MIDISettingsPreview()
                    .frame(width: 200)
            }

            HStack(spacing: 6) {
                if linked {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Circle().fill(installed ? Color.orange : Color.gray).frame(width: 7, height: 7)
                }
                Text(linkStatusText)
            }
            .font(.system(size: 12))
            .accessibilityElement(children: .combine)

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                if installed && !linked {
                    Text("Le statut reste visible dans la fenêtre Raccourcis.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if linked {
                    Button("Tester") { link.test(action: 33) }
                        .secondaryButton()
                        .controlSize(.large)
                        .help("Ouvre le Mixer dans FL Studio")
                }
                Button {
                    if installed {
                        advance()
                    } else {
                        FLScriptInstaller.installWithAlert()
                        installed = link.snapshot.hasKey
                    }
                } label: {
                    Text(installed ? "Continuer" : "Installer le lien").frame(minWidth: 140)
                }
                .primaryButton()
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}

private struct StepRow: View {
    let number: Int
    let done: Bool
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            StepBadge(number: number, done: done)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 13))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Étape \(number) : \(text)")
        .accessibilityValue(done ? "fait" : "à faire")
    }
}

/// Lueurs aux couleurs de l'icône en haut de l'accueil et du guide : dégradés radiaux statiques (aucun flou,
/// aucune animation). Couche de contenu, que le verre des touches et du bouton réfracte.
struct BrandGlow: View {
    @Environment(\.colorScheme) private var scheme

    private var k: Double { scheme == .dark ? 0.42 : 0.30 }

    var body: some View {
        ZStack {
            RadialGradient(colors: [Appearance.brand[0].opacity(k), .clear], center: .topLeading,
                           startRadius: 0, endRadius: 380)
            RadialGradient(colors: [Appearance.brand[1].opacity(k * 0.8), .clear], center: .top,
                           startRadius: 0, endRadius: 320)
            RadialGradient(colors: [Appearance.brand[2].opacity(k), .clear], center: .topTrailing,
                           startRadius: 0, endRadius: 380)
        }
        .ignoresSafeArea()                    // sous la barre de titre transparente
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Aperçu de la fenêtre MIDI Settings de FL, avec les deux endroits où cliquer (couleurs de FL).
private struct MIDISettingsPreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Options › MIDI Settings")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(white: 0.92))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(red: 0.23, green: 0.25, blue: 0.27))
            VStack(alignment: .leading, spacing: 5) {
                Text("Input").font(.system(size: 10)).foregroundStyle(Color(white: 0.6))
                highlighted("FL Shortcuts Link", badge: "①")
                Text("Output").font(.system(size: 10)).foregroundStyle(Color(white: 0.6)).padding(.top, 4)
                highlighted("FL Shortcuts Link", badge: "②")
                Text("Controller type : FL Shortcuts, même Port")
                    .font(.system(size: 10)).foregroundStyle(Color(white: 0.8)).padding(.top, 4)
            }
            .padding(10)
        }
        .background(Color(red: 0.17, green: 0.18, blue: 0.2))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
        .accessibilityLabel("Aperçu : dans MIDI Settings, FL Shortcuts Link en entrée et en sortie, avec le même port.")
    }

    private func highlighted(_ text: String, badge: String) -> some View {
        HStack {
            Text(text)
            Spacer()
            Text(badge).bold()
        }
        .font(.system(size: 11))
        .foregroundStyle(Color(red: 1, green: 0.81, blue: 0.54))
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 4).fill(Color.orange.opacity(0.18)))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.orange, lineWidth: 2))
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
