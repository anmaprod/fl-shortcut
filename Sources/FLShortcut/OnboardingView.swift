// Accueil sobre : 1. autoriser le clavier (guide Accessibilité, détection automatique) ; 2. hors mode léger,
// relier FL Studio avec un vrai statut (« En attente de FL Studio… » → « FL Studio est relié ») et « Tester ».
// En mode léger (par défaut), l'accueil s'arrête après la première étape. Aucune animation continue.
// macOS 26 : lueurs aux couleurs de l'icône en haut de la fenêtre (dégradés statiques), que réfractent les touches
// en verre et le grand bouton en verre teinté ; verre coupé (préférence, Réduire la transparence) : fond uni.
// Audit : REL-23 (accueil marqué « vu » seulement après un choix ; permission demandée depuis l'accueil),
//         tests utilisateurs (rassurer sur la vie privée, montrer où cliquer dans MIDI Settings, confirmer que
//         ça marche).
import AppKit
import SwiftUI

/// Taille fixe de la fenêtre d'accueil (plus haute pour la grande icône et les touches en verre).
private let onboardingSize = CGSize(width: 560, height: 500)

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
        let root = OnboardingView { [weak self] in self?.close() }
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
        w.title = "Bienvenue dans FL Shortcut"
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

    func close() {
        UserDefaults.standard.set(true, forKey: "didOnboard")      // après un choix (REL-23)
        window?.close()
        window = nil
    }
}

struct OnboardingView: View {
    @EnvironmentObject var status: AppStatus
    @EnvironmentObject var link: MIDILink
    @EnvironmentObject var fl: FLMonitor
    let onFinish: () -> Void

    @State private var step = 0
    @State private var askedPermission = false
    @State private var installed = false
    @AppStorage(Appearance.glassKey) private var glassEnabled = true
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// Lueurs et touches en verre : macOS 26, préférence active, transparence non réduite.
    private var showGlass: Bool { Appearance.glassAvailable && glassEnabled && !reduceTransparency }

    var body: some View {
        Group {
            if step == 0 { permissionStep } else { linkStep }
        }
        .padding(.horizontal, 44)
        .padding(.top, 40)                  // la barre de titre est transparente
        .padding(.bottom, 28)
        .frame(width: onboardingSize.width, height: onboardingSize.height)
        .background { if showGlass { BrandGlow() } }
        .onAppear { installed = link.snapshot.hasKey }
    }

    // MARK: Étape 1 — clavier

    private var permissionStep: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            AppIcon().frame(width: 88, height: 88)
            Text("FL Shortcut")
                .font(.largeTitle.weight(.bold))
                .padding(.top, 10)
            Text("Tes propres raccourcis pour FL Studio.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            HStack(spacing: 10) {
                KeyCaps(combo: KeyCombo(keyCode: 21, control: true), large: true, glass: showGlass)
                Image(systemName: "arrow.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                Text("Ouvrir le Mixer, sans chercher F9").font(.system(size: 13, weight: .medium))
            }
            .padding(.top, 20)
            .accessibilityElement(children: .combine)

            Spacer(minLength: 20)

            VStack(spacing: 10) {
                if status.accessibilityOK {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text("Clavier autorisé")
                    }
                    .font(.system(size: 13))
                    Button {
                        // Mode léger : rien à installer dans FL, l'accueil est terminé.
                        if AppMode.light { onFinish() } else { step = 1 }
                    } label: {
                        Text(AppMode.light ? "Terminer" : "Continuer").frame(minWidth: 200)
                    }
                    .primaryButton()
                    .heroControlSize()
                    .keyboardShortcut(.defaultAction)
                } else {
                    Text("FL Shortcut a besoin de l'accès Accessibilité pour reconnaître tes raccourcis.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button {
                        askedPermission = true
                        AccessibilityGuide.start()
                    } label: {
                        Text("Autoriser le clavier…").frame(minWidth: 200)
                    }
                    .primaryButton()
                    .heroControlSize()
                    .keyboardShortcut(.defaultAction)
                    if askedPermission {
                        Text("Active FL Shortcut dans Réglages Système › Accessibilité. C'est détecté tout seul.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    Button("Plus tard") { onFinish() }
                        .buttonStyle(.link)
                        .font(.system(size: 12))
                }
            }
            .frame(maxWidth: 380)

            Spacer(minLength: 20)

            Label("Tes touches ne sont lues que quand FL Studio est au premier plan. Rien n'est enregistré ni envoyé, sauf ce que tu publies toi-même dans la Communauté.",
                  systemImage: "lock")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)
        }
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
                    StepRow(number: 2, done: linked, text: "Dans FL Studio : Options › MIDI Settings. Input « FL Shortcut » : Enable, Controller type « FL Shortcut ».")
                    StepRow(number: 3, done: linked, text: "Output « FL Shortcut » : même numéro de Port que l'entrée. C'est détecté tout seul.")
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
                        onFinish()
                    } else {
                        FLScriptInstaller.installWithAlert()
                        installed = link.snapshot.hasKey
                    }
                } label: {
                    Text(installed ? "Terminer" : "Installer le lien").frame(minWidth: 140)
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

/// Lueurs aux couleurs de l'icône en haut de l'accueil : dégradés radiaux statiques (aucun flou, aucune
/// animation). Couche de contenu, que le verre des touches et du bouton réfracte.
private struct BrandGlow: View {
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
                highlighted("FL Shortcut", badge: "①")
                Text("Output").font(.system(size: 10)).foregroundStyle(Color(white: 0.6)).padding(.top, 4)
                highlighted("FL Shortcut", badge: "②")
                Text("Controller type : FL Shortcut, même Port")
                    .font(.system(size: 10)).foregroundStyle(Color(white: 0.8)).padding(.top, 4)
            }
            .padding(10)
        }
        .background(Color(red: 0.17, green: 0.18, blue: 0.2))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
        .accessibilityLabel("Aperçu : dans MIDI Settings, choisir FL Shortcut en entrée et en sortie, avec le même port.")
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
