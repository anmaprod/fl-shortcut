// Accueil en 2 étapes (simulation validée) : 1. autoriser le clavier, 2. relier FL Studio avec un vrai statut
// (« En attente de FL Studio… » → « FL Studio est relié ») et un bouton « Tester ».
// Audit : REL-23 (accueil marqué « vu » seulement après un choix ; permission demandée depuis l'accueil),
//         tests utilisateurs (rassurer sur la vie privée, montrer où cliquer dans MIDI Settings, confirmer que
//         ça marche).
import AppKit
import SwiftUI

final class OnboardingWindow {
    static let shared = OnboardingWindow()
    private var window: NSWindow?

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
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 600),
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
    @State private var appeared = false
    @State private var breathe = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                if step == 0 { permissionStep } else { linkStep }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 48)
            .padding(.bottom, 40)
            .transition(Motion.transition(.asymmetric(
                insertion: .offset(x: 60).combined(with: .opacity).combined(with: .scale(scale: 0.98)),
                removal: .offset(x: -60).combined(with: .opacity).combined(with: .scale(scale: 0.98)))))

            HStack(spacing: 8) {
                ForEach(0..<2) { i in
                    Capsule()
                        .fill(i == step ? Color.accentColor : Color.secondary.opacity(0.35))
                        .frame(width: i == step ? 22 : 7, height: 7)
                }
            }
            .padding(.bottom, 20)
            .accessibilityHidden(true)
        }
        .frame(width: 640, height: 600)
        .motion(Motion.smooth, value: step)
        .windowGlassBackground()
        .onAppear {
            installed = link.snapshot.hasKey
            Motion.run(Motion.bouncy.delay(0.12)) { appeared = true }
        }
        // Le statut passe au vert tout seul dès que FL répond : on l'anime au lieu de le faire sauter.
        .motion(Motion.smooth, value: link.status)
        .motion(Motion.smooth, value: status.accessibilityOK)
    }

    // MARK: Étape 1 — clavier

    private var permissionStep: some View {
        VStack(spacing: 14) {
            AppIcon().frame(width: 92, height: 92).padding(.bottom, 6)
                .scaleEffect(appeared || Motion.reduce ? 1 : 0.82)
                .opacity(appeared ? 1 : 0)
            Group {
                Text("FL Shortcut").font(.system(size: 30, weight: .bold))
                Text("Crée tes propres raccourcis pour FL Studio.")
                    .font(.system(size: 15)).foregroundStyle(.secondary)
            }
            .offset(y: appeared || Motion.reduce ? 0 : 8)
            .opacity(appeared ? 1 : 0)

            HStack(spacing: 10) {
                KeyCaps(combo: KeyCombo(keyCode: 21, control: true))
                Image(systemName: "arrow.right").font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary)
                Text("Ouvrir le Mixer, sans chercher F9").font(.system(size: 14, weight: .medium))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassCard(cornerRadius: 16)
            .padding(.top, 6)

            Label {
                Text("FL Shortcut ne regarde tes touches que quand FL Studio est au premier plan. Rien n'est enregistré ni envoyé.")
            } icon: {
                Image(systemName: "lock.fill")
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .frame(maxWidth: 420)
            .padding(.top, 8)

            Group {
                if status.accessibilityOK {
                    Button {
                        step = 1
                    } label: {
                        Label("Autorisé — continuer", systemImage: "checkmark").frame(minWidth: 200)
                    }
                    .transition(Motion.pop)
                } else {
                    Button {
                        if askedPermission {
                            status.openAccessibilitySettings()
                        } else {
                            askedPermission = true
                            status.requestAccessibility()
                        }
                    } label: {
                        Text(askedPermission ? "Ouvrir les Réglages" : "Autoriser le clavier").frame(minWidth: 200)
                    }
                    .transition(Motion.pop)
                }
            }
            .primaryGlassButton()
            .controlSize(.large)
            .padding(.top, 14)

            Text(status.accessibilityOK ? " " :
                    askedPermission ? "Active FL Shortcut dans Réglages Système › Confidentialité et sécurité › Accessibilité."
                                    : "macOS va te demander l'accès « Accessibilité ».")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .contentTransition(.interpolate)

            Button("Plus tard") { onFinish() }
                .buttonStyle(.link)
                .font(.system(size: 12))
        }
    }

    // MARK: Étape 2 — relier FL Studio

    private var linked: Bool { link.status == .linked }

    private var linkStep: some View {
        VStack(spacing: 12) {
            Text("Relier FL Studio").font(.system(size: 26, weight: .bold))
            Text("À faire une seule fois.").font(.system(size: 14)).foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    StepRow(number: 1, done: installed, text: "Installer le lien dans FL Studio (un clic, ci-dessous), puis redémarrer FL.")
                    StepRow(number: 2, done: linked, text: "Dans FL Studio : Options › MIDI Settings. Input « FL Shortcut » : Enable, Controller type « FL Shortcut ».")
                    StepRow(number: 3, done: linked, text: "Output « FL Shortcut » : même numéro de Port que l'entrée. FL Shortcut le détecte tout seul.")
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard(cornerRadius: 18)

                MIDISettingsPreview()
                    .frame(width: 230)
            }
            .padding(.top, 10)

            HStack(spacing: 10) {
                if linked {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .bounceSymbol(on: linked)
                        .transition(Motion.transition(.scale(scale: 0.3).combined(with: .opacity)))
                } else {
                    Circle().fill(installed ? Color.orange : Color.gray).frame(width: 8, height: 8)
                        .opacity(installed && breathe ? 0.45 : 1)
                        .transition(.opacity)
                }
                Text(linked ? "FL Studio est relié" : installed ? "En attente de FL Studio… fais les étapes 2 et 3" : "FL Studio pas encore relié")
                    .font(.system(size: 13, weight: .medium))
                    .contentTransition(.interpolate)
            }
            .onAppear {
                // Point qui « respire » doucement pendant l'attente (désactivé si le mouvement est réduit).
                guard !Motion.reduce else { return }
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { breathe = true }
            }
            .padding(.horizontal, 16)
            .frame(height: 36)
            .glassCapsule()
            .padding(.top, 6)
            .accessibilityElement(children: .combine)

            HStack(spacing: 10) {
                if linked {
                    Button("Tester") { link.test(action: 33) }
                        .secondaryGlassButton()
                        .controlSize(.large)
                        .help("Ouvre le Mixer dans FL Studio")
                        .transition(Motion.pop)
                }
                Button {
                    if installed {
                        onFinish()
                    } else {
                        FLScriptInstaller.installWithAlert()
                        installed = link.snapshot.hasKey
                    }
                } label: {
                    Text(installed ? "Terminer" : "Installer le lien").frame(minWidth: 180)
                }
                .primaryGlassButton()
                .controlSize(.large)
            }
            .padding(.top, 8)

            if installed && !linked {
                Text("Tu peux terminer maintenant : le statut s'affichera aussi dans la fenêtre Raccourcis.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
        .motion(Motion.smooth, value: installed)
    }
}

private struct StepRow: View {
    let number: Int
    let done: Bool
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle().fill(done ? Color.green : Color.primary.opacity(0.08))
                if done {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white)
                        .transition(Motion.transition(.scale(scale: 0.3).combined(with: .opacity)))
                } else {
                    Text("\(number)").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
                        .transition(.opacity)
                }
            }
            .frame(width: 22, height: 22)
            .scaleEffect(done && !Motion.reduce ? 1.0 : 0.96)
            .motion(Motion.bouncy, value: done)
            Text(text).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(done ? "fait" : "à faire")
    }
}

/// Aperçu de la fenêtre MIDI Settings de FL, avec les deux endroits où cliquer.
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
                Text("Controller type : FL Shortcut · même Port")
                    .font(.system(size: 10)).foregroundStyle(Color(white: 0.8)).padding(.top, 4)
            }
            .padding(10)
        }
        .background(Color(red: 0.17, green: 0.18, blue: 0.2))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
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
    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width / 96
            ZStack {
                RoundedRectangle(cornerRadius: 22 * s, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.35, green: 0.78, blue: 0.98), Color(red: 0.04, green: 0.38, blue: 1)],
                                         startPoint: .top, endPoint: .bottom))
                RoundedRectangle(cornerRadius: 22 * s, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.5), lineWidth: 1)
                HStack(spacing: 8 * s) {
                    RoundedRectangle(cornerRadius: 7 * s, style: .continuous).fill(Color.white.opacity(0.92)).frame(width: 27 * s, height: 27 * s)
                    RoundedRectangle(cornerRadius: 7 * s, style: .continuous).fill(Color.white.opacity(0.92)).frame(width: 27 * s, height: 27 * s)
                }
                .offset(y: 10 * s)
                Image(systemName: "arrow.turn.up.right")
                    .font(.system(size: 26 * s, weight: .heavy))
                    .foregroundStyle(.white)
                    .offset(y: -18 * s)
            }
            .shadow(color: Color(red: 0.04, green: 0.38, blue: 1).opacity(0.35), radius: 14 * s, y: 10 * s)
        }
        .accessibilityHidden(true)
    }
}
