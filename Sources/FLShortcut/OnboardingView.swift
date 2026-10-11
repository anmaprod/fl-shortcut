// Accueil sobre : 1. autoriser le clavier (guide Accessibilité, détection automatique) ; 2. hors mode léger,
// relier FL Studio avec un vrai statut (« En attente de FL Studio… » → « FL Studio est relié ») et « Tester ».
// En mode léger (par défaut), l'accueil s'arrête après la première étape. Aucune animation continue.
// Audit : REL-23 (accueil marqué « vu » seulement après un choix ; permission demandée depuis l'accueil),
//         tests utilisateurs (rassurer sur la vie privée, montrer où cliquer dans MIDI Settings, confirmer que
//         ça marche).
import AppKit
import SwiftUI

/// Taille fixe de la fenêtre d'accueil.
private let onboardingSize = CGSize(width: 560, height: 460)

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

    var body: some View {
        Group {
            if step == 0 { permissionStep } else { linkStep }
        }
        .padding(.horizontal, 44)
        .padding(.top, 40)                  // la barre de titre est transparente
        .padding(.bottom, 28)
        .frame(width: onboardingSize.width, height: onboardingSize.height)
        .onAppear { installed = link.snapshot.hasKey }
    }

    // MARK: Étape 1 — clavier

    private var permissionStep: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            AppIcon().frame(width: 72, height: 72)
            Text("FL Shortcut")
                .font(.title.weight(.semibold))
                .padding(.top, 14)
            Text("Tes propres raccourcis pour FL Studio.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            HStack(spacing: 8) {
                KeyCaps(combo: KeyCombo(keyCode: 21, control: true))
                Image(systemName: "arrow.right").font(.system(size: 11)).foregroundStyle(.secondary)
                Text("Ouvrir le Mixer, sans chercher F9").font(.system(size: 13))
            }
            .padding(.top, 22)
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
                        Text(AppMode.light ? "Terminer" : "Continuer").frame(minWidth: 160)
                    }
                    .primaryButton()
                    .controlSize(.large)
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
                        Text("Autoriser le clavier…").frame(minWidth: 160)
                    }
                    .primaryButton()
                    .controlSize(.large)
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

            Label("Tes touches ne sont lues que quand FL Studio est au premier plan. Rien n'est enregistré ni envoyé.",
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
            Group {
                if done {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Text("\(number).").foregroundStyle(.secondary)
                }
            }
            .frame(width: 18, alignment: .leading)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 13).monospacedDigit())
        .accessibilityElement(children: .combine)
        .accessibilityValue(done ? "fait" : "à faire")
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

/// Icône de l'appli dessinée (deux touches et une flèche), en attendant l'icône finale.
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

    /// Dessin de secours, à plat (deux touches et une flèche).
    private var drawn: some View {
        GeometryReader { geo in
            let s = geo.size.width / 96
            ZStack {
                RoundedRectangle(cornerRadius: 22 * s, style: .continuous)
                    .fill(Color.accentColor)
                HStack(spacing: 8 * s) {
                    RoundedRectangle(cornerRadius: 7 * s, style: .continuous).fill(Color.white.opacity(0.92)).frame(width: 27 * s, height: 27 * s)
                    RoundedRectangle(cornerRadius: 7 * s, style: .continuous).fill(Color.white.opacity(0.92)).frame(width: 27 * s, height: 27 * s)
                }
                .offset(y: 10 * s)
                Image(systemName: "arrow.turn.up.right")
                    .font(.system(size: 26 * s, weight: .bold))
                    .foregroundStyle(.white)
                    .offset(y: -18 * s)
            }
        }
        .accessibilityHidden(true)
    }
}
