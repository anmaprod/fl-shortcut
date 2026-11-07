// Mute et solo d'une piste du Mixer sans le script MIDI (mode léger). FL n'a ni touche ni menu pour couper le son
// d'une piste : seulement son bouton mute (le petit rond en haut de la piste), dont le clic droit fait le solo ; le
// solo a aussi sa touche, S.
// - Le bouton mute est montré une seule fois sur ce Mac (« Montrer le bouton mute dans FL… », deux clics : couper
//   puis remettre le son) : sa hauteur dans la fenêtre de FL, et son image dans les deux états.
// - Pendant la macro : la piste est celle cliquée juste avant (TrackMemory). Son bouton est cherché à son image dans
//   la colonne de cette piste seulement (lecture de la fenêtre de FL au moment du clic, autorisation « Enregistrement
//   de l'écran ») ; sans lecture, ou s'il n'est pas reconnu, à la hauteur apprise, sous la piste cliquée.
// - Mute : clic gauche sur ce bouton. Solo : clic droit dessus ; bouton pas encore montré : la touche S de FL (piste
//   sélectionnée, Mixer devant). Les deux inversent l'état, comme le lien avec FL quand le script est là.
import AppKit
import SwiftUI

/// Bouton mute d'une piste du Mixer, montré une fois sur ce Mac.
struct MuteSwitch: Codable, Equatable {
    /// Du haut de la fenêtre de FL au centre du bouton (points).
    var dy: Double
    /// Côté des images, carrées et centrées sur le bouton (points, 1 pixel par point).
    var side: Int
    /// Le bouton dans ses deux états (niveaux de gris), 0 à 2 images : sans lecture de l'écran, la hauteur seule.
    var patches: [Data]

    static let key = "macroSpots.v2.muteSwitch"
    static let defaultSide = 16
    /// Demi-largeur de la colonne cherchée autour de la piste cliquée (une piste du Mixer fait environ 55 points).
    static let column: CGFloat = 70

    var isValid: Bool {
        dy.isFinite && dy >= 0 && dy <= 5000 && (8...64).contains(side) && patches.count <= 2
            && patches.allSatisfy { $0.count == side * side }
    }

    var images: [GrayImage] { patches.map { GrayImage(width: side, height: side, pixels: [UInt8]($0)) } }

    static func load(_ defaults: UserDefaults = .standard) -> MuteSwitch? {
        guard let data = defaults.data(forKey: key),
              let spot = try? JSONDecoder().decode(MuteSwitch.self, from: data), spot.isValid else { return nil }
        return spot
    }

    func save(_ defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key) }
    }

    static func forget(_ defaults: UserDefaults = .standard) { defaults.removeObject(forKey: key) }

    static var isLearned: Bool { load() != nil }

    static let toLearn = String(localized: "Sans le lien avec FL : bouton mute à montrer une fois.")

    /// Pure (testée) : centre du bouton de la piste dont la colonne contient `expected` (repère de l'image : la
    /// fenêtre de FL, 1 pixel par point), ou nil s'il n'est pas reconnu. Jamais hors de cette colonne ; à image égale,
    /// le plus proche de la piste cliquée.
    func locate(in image: GrayImage, expected: CGPoint) -> CGPoint? {
        let x0 = max(0, Int(expected.x - Self.column)), x1 = min(image.width, Int(expected.x + Self.column))
        guard x1 - x0 >= side, let band = image.crop(x: x0, y: 0, width: x1 - x0, height: image.height) else { return nil }
        let hint = (x: Int(expected.x) - x0, y: Int(expected.y))
        func distance(_ h: VisualMatch.Hit) -> Int {
            4 * (h.x - hint.x) * (h.x - hint.x) + (h.y - hint.y) * (h.y - hint.y)
        }
        let hits = images.compactMap { VisualMatch.find($0, in: band, hint: hint) }
        guard let best = hits.min(by: { distance($0) < distance($1) }) else { return nil }
        return CGPoint(x: x0 + best.x, y: best.y)
    }

    /// Pure (testée) : image du bouton autour de `point` (repère de l'image), ou nil (bord, zone unie).
    static func patch(of image: GrayImage, at point: CGPoint, side: Int = defaultSide) -> Data? {
        guard let p = image.crop(centerX: Int(point.x), centerY: Int(point.y), side: side),
              p.contrast >= VisualMatch.minContrast else { return nil }
        return Data(p.pixels)
    }
}

/// « Action de FL » mute ou solo sans le lien : ce que l'app sait faire sans le script.
enum MuteSolo {
    static func handlesWithoutLink(_ key: String) -> Bool { key == "mute" || key == "solo" }
}

extension MacroEffectsMac {
    /// Bouton mute de la piste cliquée juste avant la macro (point global), ou la raison de l'échec.
    private func muteSwitchPoint(ctx: Context) -> Result<CGPoint, MenuStop> {
        guard let spot = MuteSwitch.load() else {
            return .failure(.fail(String(localized: "bouton mute pas encore montré : choisis le bloc, puis « Montrer le bouton mute dans FL… »")))
        }
        guard targetTrackIsInFL(),
              let window = WinSnapshot.take(pid: ctx.pid).fl.first(where: { $0.layer == 0 && $0.bounds.contains(ctx.track) })
        else {
            return .failure(.fail(String(localized: "clique d'abord sur ta piste dans le Mixer, puis lance la macro")))
        }
        let expected = CGPoint(x: ctx.track.x - window.bounds.minX, y: spot.dy)
        guard expected.y < window.bounds.height else {
            return .failure(.fail(String(localized: "bouton mute hors de la fenêtre de FL : montre-le de nouveau")))
        }
        var found: CGPoint?
        if !spot.patches.isEmpty, MacroEffectsMac.canRead,
           let image = ScreenLook.capture(windowNumber: window.number, size: window.bounds.size) {
            found = spot.locate(in: image, expected: expected)
        }
        MacroLog.shared.write("MUTE", found == nil ? "switch at learned height" : "switch found by its image")
        let p = found ?? expected
        return .success(CGPoint(x: window.bounds.minX + p.x, y: window.bounds.minY + p.y))
    }

    /// Sans le lien : clic gauche sur le bouton mute de la piste cliquée (inverse le mute).
    func muteWithoutLink(ctx: Context) -> StepResult {
        switch muteSwitchPoint(ctx: ctx) {
        case .success(let p): return click(at: p, right: false, ctx: ctx)
        case .failure(let stop): return result(stop)
        }
    }

    /// Sans le lien : clic droit sur le bouton mute de la piste cliquée ; pas encore montré, la touche S de FL
    /// (piste sélectionnée, Mixer devant). Inverse le solo.
    func soloWithoutLink(ctx: Context) -> StepResult {
        guard MuteSwitch.isLearned else {
            if let stop = shouldStop(ctx.pid) { return .cancel(stop) }
            postKey(KeyCombo(keyCode: KeyNames.keyCode(for: "s") ?? 1), pid: ctx.pid)
            MacroLog.shared.write("KEY", "solo key")
            return .ok
        }
        switch muteSwitchPoint(ctx: ctx) {
        case .success(let p): return click(at: p, right: true, ctx: ctx)
        case .failure(let stop): return result(stop)
        }
    }
}

/// « Montrer le bouton mute dans FL… » : deux clics sur le bouton mute d'une piste (couper, puis remettre le son).
final class MuteSwitchTeacher: ObservableObject {
    static let shared = MuteSwitchTeacher()

    @Published private(set) var active = false
    @Published private(set) var message: String?

    private var timer: Timer?
    private var pid: Int32 = 0
    private var started = Date()
    private var first: (point: CGPoint, window: WinInfo)?
    private var patches: [Data] = []
    /// Clics pris en compte (une image demandée après chacun) ; une image en cours de lecture.
    private var shots = 0
    private var capturing = false
    private weak var returnWindow: NSWindow?

    private init() {}

    func start(pid: Int32, returnTo window: NSWindow?) {
        stop()
        guard let fl = NSRunningApplication(processIdentifier: pid) else {
            message = String(localized: "Ouvre FL Studio, puis recommence.")
            return
        }
        // L'image du bouton demande de lire la fenêtre de FL : autorisation demandée à l'accueil seulement (FL passe
        // ici devant la fenêtre de macOS) ; sans elle, la hauteur seule.
        self.pid = pid
        returnWindow = window
        first = nil
        patches = []
        shots = 0
        capturing = false
        active = true
        started = Date()
        message = String(localized: "Dans FL : clique le bouton mute d'une piste du Mixer, puis reclique-le (Échap pour annuler).")
        CreatorPresence.stepAside()
        fl.activate(options: [])
        ClickRecorder.shared.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, self.active,
                  let main = FLWindows.list(pid: pid).filter({ $0.layer == 0 })
                    .max(by: { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }) else { return }
            HintPanel.shared.show(String(localized: "Clique le bouton mute (le petit rond en haut) d'une piste du Mixer, puis reclique-le pour remettre le son. Échap : annuler."),
                                  near: CGPoint(x: main.bounds.midX, y: main.bounds.minY + 70))
        }
        let t = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func say(_ text: String) { message = text }

    func cancel(_ text: String) {
        stop()
        finish(text)
    }

    private func tick() {
        if CGEventSource.keyState(.combinedSessionState, key: 53) { return cancel(String(localized: "Annulé.")) }
        if Date().timeIntervalSince(started) > 40 {
            return first == nil ? cancel(String(localized: "Aucun clic montré dans FL en 40 s.")) : save()
        }
        guard !capturing else { return }
        let samples = ClickRecorder.shared.capturedSamples
        if first == nil, let sample = samples.first {
            guard let window = WinSnapshot.take(pid: pid).hit(sample.point), window.layer == 0 else {
                return cancel(String(localized: "Ce clic n'était pas dans une fenêtre de FL : recommence sur le bouton mute d'une piste."))
            }
            first = (sample.point, window)
            shots = 1
            capture(after: sample.point, in: window)
        } else if let first, shots == 1, samples.count >= 2 {
            // Deuxième clic ailleurs : le bouton est retenu avec la seule image du premier.
            let second = samples[1].point
            guard hypot(second.x - first.point.x, second.y - first.point.y) <= 8 else { return save() }
            shots = 2
            capture(after: second, in: first.window)
        } else if shots == 2 {
            save()
        }
    }

    /// Image du bouton juste après le clic (FL vient de changer son état). Écran non lisible : aucune image.
    private func capture(after point: CGPoint, in window: WinInfo) {
        guard MacroEffectsMac.canRead else { return }
        capturing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            ScreenLook.capture(windowNumber: window.number, size: window.bounds.size) { image in
                guard let self, self.active else { return }
                let local = CGPoint(x: point.x - window.bounds.minX, y: point.y - window.bounds.minY)
                if let image, let patch = MuteSwitch.patch(of: image, at: local) { self.patches.append(patch) }
                self.capturing = false
            }
        }
    }

    private func save() {
        guard let first else { return cancel(String(localized: "Aucun clic montré dans FL.")) }
        let spot = MuteSwitch(dy: Double(first.point.y - first.window.bounds.minY), side: MuteSwitch.defaultSide,
                              patches: patches)
        stop()
        guard spot.isValid else { return finish(String(localized: "Ce bouton n'a pas pu être retenu : recommence.")) }
        spot.save()
        let again = ClickRecorder.shared.capturedSamples.count < 2 ? String(localized: " Pense à remettre le son de cette piste.") : ""
        finish((spot.patches.isEmpty
                    ? String(localized: "Bouton mute retenu à sa hauteur (écran non lisible : clique tes pistes au milieu, sur leur nom).")
                    : String(localized: "Bouton mute retenu : il sera retrouvé sur chaque piste.")) + again)
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        if active {
            ClickRecorder.shared.stop()
            HintPanel.shared.hide()
        }
    }

    private func finish(_ text: String) {
        active = false
        message = text
        CreatorPresence.comeBack()
        if let window = returnWindow {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
        returnWindow = nil
    }
}
