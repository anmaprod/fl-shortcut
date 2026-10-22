// Menu de l'icône de la barre des menus (MenuBarExtra en fenêtre), réglé là où SwiftUI ne le fait pas :
// - il se ferme dès qu'on choisit une ligne, ou qu'on clique une fenêtre de l'app (il restait ouvert par-dessus) ;
// - refermé d'un clic sur l'icône, il laisse devant la fenêtre de l'app qui y était (SwiftUI rendait le premier plan
//   à FL, dont la fenêtre recouvrait tout : on aurait dit que tout se fermait) ;
// - à chaque ouverture, son contenu sort de l'icône : il passe du flou au net en grandissant depuis le haut, puis les
//   options arrivent l'une après l'autre (flou → net, de haut en bas, ressort) et leur icône éclot ; une option
//   choisie le fait rentrer dans l'icône à l'envers (les options du bas d'abord, puis le panneau) avant qu'il se
//   ferme. « Réduire les animations » : fondu seul.
// Fermer passe par le bouton de l'icône (comme un clic dessus) : SwiftUI reste d'accord sur l'état du menu, et le
// clic suivant sur l'icône l'ouvre du premier coup.
import AppKit
import SwiftUI

final class MenuPanel: ObservableObject {
    static let shared = MenuPanel()

    /// Contenu déployé : faux pendant que le menu est fermé, vrai (animé) à chaque ouverture.
    @Published private(set) var revealed = false
    /// Notre bulle (MenuBubble) dans une fenêtre rendue transparente ; faux : menu de macOS d'avant (repli).
    @Published private(set) var bubble = false
    /// Pastille de départ de la bulle, sous l'icône (contenu de la fenêtre, origine en haut à gauche).
    @Published private(set) var pillFrame: CGRect = .zero
    /// Cadre de l'icône à l'écran (origine en bas), lu à chaque ouverture.
    private(set) var statusIconFrame: CGRect?

    private weak var panel: NSWindow?
    /// Fenêtre du menu (rapport de la CI : sa structure).
    var window: NSWindow? { panel }
    private var observers: [NSObjectProtocol] = []
    /// Dernière fois que l'app est passée au premier plan.
    private var activeSince = Date.distantPast
    /// Fenêtre de l'app qui était devant à l'ouverture (l'app au premier plan) : elle y revient à la fermeture.
    private weak var frontWindow: NSWindow?
    /// Fermeture demandée (ligne choisie) : ne pas recliquer l'icône une seconde fois.
    private var closing = false
    /// Menu ouvert (entre l'ouverture et la fermeture de sa fenêtre), même pendant qu'il rentre dans l'icône.
    private var isOpen = false

    private init() {
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.activeSince = Date()
        })
    }

    /// Fenêtre du menu, donnée par son contenu dès qu'il y est posé ; suivie une seule fois.
    func attach(_ window: NSWindow) {
        guard panel !== window else { return }
        panel = window
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window,
                                            queue: .main) { [weak self] _ in self?.opened() })
        observers.append(center.addObserver(forName: NSWindow.didResignKeyNotification, object: window,
                                            queue: .main) { [weak self] _ in self?.resigned() })
        observers.append(center.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: window,
                                            queue: .main) { [weak self] _ in self?.visibilityChanged() })
        // La fenêtre grandit de la marge de la bulle, ou macOS la décale près d'un bord : la pastille reste sous
        // l'icône.
        for name in [NSWindow.didResizeNotification, NSWindow.didMoveNotification] {
            observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                self?.placePill()
            })
        }
        prepareBubble()                                    // bulle prête avant le premier affichage
        if window.isKeyWindow || window.occlusionState.contains(.visible) { opened() }
    }

    /// Fenêtre transparente pour notre bulle (ou repli sur le menu d'avant), pastille sous l'icône. À chaque
    /// ouverture : macOS peut remettre son fond.
    private func prepareBubble() {
        guard let panel else { return }
        // La préférence de repli compte au lancement : une fenêtre déjà rendue transparente garde sa bulle (le menu
        // d'avant n'y aurait plus de fond).
        let legacy = !bubble && UserDefaults.standard.bool(forKey: MenuBubbleSupport.legacyKey)
        let ours = MenuBubbleSupport.prepare(panel, legacy: legacy) || bubble
        if ours != bubble {
            var quiet = Transaction()
            quiet.disablesAnimations = true
            withTransaction(quiet) { bubble = ours }
        }
        placePill()
    }

    private func placePill() {
        guard let panel else { return }
        statusIconFrame = statusButton?.window?.frame
        guard let icon = statusIconFrame else { return }
        let pill = MenuBubbleGeometry.pill(icon: icon, window: panel.frame)
        if pill != pillFrame { pillFrame = pill }
    }

    /// Commande de la CI : un clic sur l'icône (ouvre ou ferme le menu, comme la souris).
    func clickIcon() {
        statusButton?.performClick(nil)
    }

    /// Contenu affiché : si la fenêtre n'a rien signalé (cas imprévu), le contenu se montre quand même.
    func appeared() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, !self.revealed, !self.closing, self.panel?.isVisible ?? true else { return }
            self.reveal()
        }
    }

    /// Ligne choisie : le menu rentre dans l'icône (l'ouverture à l'envers), puis se ferme, comme un vrai menu.
    func close() {
        guard let panel, panel.isVisible, !closing else { return }
        closing = true
        let reduce = Motion.reduce
        let duration: TimeInterval
        if bubble {
            // Les lignes partent d'abord (MenuReveal), notre bulle rentre dans l'icône ; la fenêtre, transparente,
            // n'a rien d'autre à effacer.
            duration = reduce ? Motion.reducedDuration : Motion.settleTime(.doux)
            withAnimation(reduce ? Motion.reduced : Motion.spring(.doux)) { revealed = false }
        } else {
            // Les options repartent d'abord (MenuReveal), puis le panneau rentre dans l'icône.
            duration = reduce ? Motion.reducedDuration : 2 * Motion.exitDuration
            withAnimation(reduce ? Motion.reduced : Motion.exit.delay(Motion.exitDuration)) { revealed = false }
            // La bulle de macOS s'efface avec les options : elle restait seule au-dessus de la fenêtre qu'une option
            // venait d'ouvrir.
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().alphaValue = 0
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self, let panel = self.panel, panel.isVisible else { return }
            self.statusButton?.performClick(nil)
            // Filet : toujours là (une fenêtre de l'app vient de prendre la main et le clic n'a rien fermé), il est
            // retiré directement.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                guard let self, let panel = self.panel, panel.isVisible, !self.revealed else { return }
                panel.orderOut(nil)
                self.closed()
            }
        }
    }

    // MARK: Ouverture, fermeture

    private func opened() {
        guard !isOpen else { return }
        isOpen = true
        closing = false
        // L'app était déjà au premier plan avant le clic sur l'icône (pas activée par l'ouverture du menu).
        let alreadyFront = NSApp.isActive && Date().timeIntervalSince(activeSince) > 0.4
        frontWindow = alreadyFront ? appWindows.first : nil
        prepareBubble()
        reveal()
    }

    private func reveal() {
        panel?.alphaValue = 1                              // effacée à la dernière fermeture
        withAnimation(Motion.reduce ? Motion.reduced : Motion.spring(.doux)) {
            revealed = true
        }
    }

    /// Une autre fenêtre a pris la main (ligne choisie, clic sur une fenêtre de l'app ou sur une autre app) : le menu
    /// se ferme s'il est encore là.
    private func resigned() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let panel = self.panel else { return }
            // Clic sur une fenêtre de l'app : elle reste devant une fois le menu fermé. Clic dans une autre app :
            // SwiftUI ferme le menu lui-même (le refermer ici pourrait le rouvrir pendant qu'il s'efface).
            if panel.isVisible, !panel.isKeyWindow, NSApp.isActive {
                if let key = NSApp.keyWindow, key !== panel, key.isVisible { self.frontWindow = key }
                self.close()
            }
            if !panel.isVisible { self.closed() }
        }
    }

    private func visibilityChanged() {
        guard let panel else { return }
        if panel.occlusionState.contains(.visible) {
            if panel.isVisible { opened() }
        } else if !panel.isVisible {
            closed()
        }
    }

    private func closed() {
        guard isOpen else { return }
        isOpen = false
        var quiet = Transaction()
        quiet.disablesAnimations = true
        withTransaction(quiet) { revealed = false }       // sans animation : prêt pour la prochaine ouverture
        // Fermé par une ligne choisie ou d'un clic sur l'icône (pas d'un clic dans une autre app) alors qu'une
        // fenêtre de l'app était devant : elle y reste.
        let byItemOrIcon = closing || (statusButton?.window?.frame.contains(NSEvent.mouseLocation) ?? false)
        closing = false
        guard let window = frontWindow, byItemOrIcon else { frontWindow = nil; return }
        frontWindow = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard window.isVisible, !window.isMiniaturized else { return }
            // Une fenêtre de l'app a déjà la main (celle qu'une ligne vient d'ouvrir, l'Organiser…) : elle la garde.
            if let key = NSApp.keyWindow, key !== self?.panel, key.isVisible { return }
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: Outils

    /// Fenêtres de l'app qu'on peut avoir devant soi (principale, guide…), de la plus en avant à la plus en arrière.
    private var appWindows: [NSWindow] {
        NSApp.orderedWindows.filter { $0 !== panel && $0.isVisible && !$0.isMiniaturized && $0.canBecomeMain }
    }

    /// Bouton de l'icône dans la barre des menus (créé par SwiftUI pour MenuBarExtra).
    private var statusButton: NSStatusBarButton? {
        for window in NSApp.windows where window.className.contains("NSStatusBarWindow") {
            if let button = Self.find(NSStatusBarButton.self, in: window.contentView) { return button }
        }
        return nil
    }

    private static func find<T: NSView>(_ type: T.Type, in view: NSView?) -> T? {
        guard let view else { return nil }
        if let match = view as? T { return match }
        for sub in view.subviews {
            if let match = find(type, in: sub) { return match }
        }
        return nil
    }
}

extension View {
    /// Contenu du menu : sort de l'icône (fondu, léger agrandissement depuis le haut).
    func menuReveal(_ revealed: Bool) -> some View {
        modifier(MenuReveal(revealed: revealed, index: nil))
    }

    /// Ligne du menu : arrive juste après la précédente (`index` : sa place dans le menu).
    /// En bulle (`bubble`), les lignes attendent que la bulle soit presque posée.
    func menuRevealRow(_ revealed: Bool, index: Int, bubble: Bool = false) -> some View {
        modifier(MenuReveal(revealed: revealed, index: index, bubble: bubble))
    }
}

private struct MenuReveal: ViewModifier {
    let revealed: Bool
    let index: Int?
    var bubble = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotionSetting

    private var reduceMotion: Bool { reduceMotionSetting && DebugSnapshot.slowMotion == 1 }

    func body(content: Content) -> some View {
        if reduceMotion {
            content.opacity(revealed ? 1 : 0)
        } else if let index {
            // Une option : du flou au net en descendant à sa place, juste après la précédente ; à la fermeture,
            // celles du bas repartent d'abord.
            content
                .opacity(revealed ? 1 : 0)
                .blur(radius: revealed ? 0 : 6)
                .scaleEffect(revealed ? 1 : 0.94, anchor: .top)
                .offset(y: revealed ? 0 : -12)
                .animation(revealed
                           ? Motion.spring(.doux).delay(arrival(index))
                           : Motion.exit.delay(Motion.stagger(10 - index, start: 0, step: 0.012)), value: revealed)
        } else {
            // Le panneau : sort de l'icône, du flou au net, en grandissant depuis le haut.
            content
                .opacity(revealed ? 1 : 0)
                .blur(radius: revealed ? 0 : 10)
                .scaleEffect(revealed ? 1 : 0.86, anchor: .top)
                .offset(y: revealed ? 0 : -8)
        }
    }

    /// Délai d'arrivée d'une ligne : juste après la précédente ; en bulle, à partir de 60 % de son ouverture.
    private func arrival(_ index: Int) -> TimeInterval {
        guard bubble else { return Motion.stagger(index) }
        return 0.6 * Motion.settleTime(.doux) + Motion.stagger(index, start: 0, step: 0.035)
    }
}
