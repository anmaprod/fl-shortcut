// Mute et solo d'une piste sans le lien avec FL (mode léger). FL n'a pas de touche pour couper le son d'une piste
// partout : seulement le petit rond de la piste (Mixer : sous son nom ; Channel rack : à gauche des boutons et du
// numéro ; Playlist : en bas à droite de l'en-tête). Retour du 08/11 (« si la personne veut solo ou mute, ce sera la
// piste sélectionnée, c'est pour ça qu'il n'y a pas besoin de montrer ») :
// - la piste est la dernière cliquée dans FL (TrackMemory : celle que FL vient de sélectionner) ;
// - son rond est retrouvé tout seul dans la fenêtre de FL (MuteDots.swift), lue au moment du clic avec l'autorisation
//   « Enregistrement de l'écran » ; plus rien à montrer une fois ;
// - mute : clic gauche sur le rond ; solo : ⌘ + clic gauche (la touche S de FL ne fait le solo que dans le Mixer :
//   jamais utilisée). Les deux inversent l'état, comme le lien avec FL quand le script est là.
import AppKit

/// « Action de FL » mute ou solo sans le lien : ce que l'app sait faire sans le script.
enum MuteSolo {
    static func handlesWithoutLink(_ key: String) -> Bool { key == "mute" || key == "solo" }

    /// Bouton mute montré une fois (avant le 08/11) : ce réglage ne sert plus, il est effacé.
    static func forgetOldSpot(_ defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: "macroSpots.v2.muteSwitch")
    }
}

extension RGBAImage {
    /// Pixels d'une image de l'écran, en rouge, vert, bleu, alpha (jamais gardés).
    init?(_ image: CGImage) {
        let w = image.width, h = image.height
        guard w > 0, h > 0, w <= 16_000, h <= 16_000 else { return nil }
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                          bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
        self.init(width: w, height: h, pixels: bytes)
    }
}

extension MacroEffectsMac {
    /// Le rond de la piste cliquée juste avant la macro (point global), ou la raison de l'échec.
    private func muteDot(ctx: Context) -> Result<CGPoint, MenuStop> {
        MuteSolo.forgetOldSpot()
        guard targetTrackIsInFL(),
              let window = WinSnapshot.take(pid: ctx.pid).fl.first(where: { $0.layer == 0 && $0.bounds.contains(ctx.track) })
        else {
            return .failure(.fail(String(localized: "clique d'abord sur ta piste dans FL, puis lance la macro")))
        }
        guard MacroEffectsMac.canRead else {
            return .failure(.fail(String(localized: "autorise « Enregistrement de l'écran » : le bouton mute de la piste est retrouvé dans la fenêtre de FL")))
        }
        guard let shot = ScreenLook.captureImage(windowNumber: window.number, size: window.bounds.size, scale: 2),
              let image = RGBAImage(shot) else {
            return .failure(.fail(String(localized: "fenêtre de FL illisible")))
        }
        let sx = Double(image.width) / Double(window.bounds.width), sy = Double(image.height) / Double(window.bounds.height)
        let click = (x: Double(ctx.track.x - window.bounds.minX) * sx, y: Double(ctx.track.y - window.bounds.minY) * sy)
        guard let dot = MuteDots.target(in: image, click: click) else {
            MacroLog.shared.write("MUTE", "no dot near the clicked track")
            return .failure(.fail(String(localized: "bouton mute introuvable : clique sur ta piste (Mixer, Channel rack ou Playlist), puis relance")))
        }
        MacroLog.shared.write("MUTE", "dot found (\(dot.page.rawValue)\(dot.inferred ? ", unlit" : ""))")
        return .success(CGPoint(x: window.bounds.minX + CGFloat(dot.x / sx), y: window.bounds.minY + CGFloat(dot.y / sy)))
    }

    /// Sans le lien : clic gauche sur le rond de la piste cliquée (inverse le mute).
    func muteWithoutLink(ctx: Context) -> StepResult {
        switch muteDot(ctx: ctx) {
        case .success(let p): return click(at: p, right: false, ctx: ctx)
        case .failure(let stop): return result(stop)
        }
    }

    /// Sans le lien : ⌘ + clic gauche sur le rond de la piste cliquée (inverse le solo), dans le Mixer, le Channel rack
    /// ou la Playlist.
    func soloWithoutLink(ctx: Context) -> StepResult {
        switch muteDot(ctx: ctx) {
        case .success(let p): return click(at: p, right: false, ctx: ctx, flags: .maskCommand)
        case .failure(let stop): return result(stop)
        }
    }
}
