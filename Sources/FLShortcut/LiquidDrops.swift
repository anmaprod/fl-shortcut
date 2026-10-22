// Gouttes de verre de la barre du bas du créateur (tâche 7 du plan des animations) : sans bloc choisi, la goutte
// « Ajouter » seule ; avec un bloc choisi, « Dupliquer » et « Supprimer » en sortent (ressort liquide) et y rentrent
// (vif). macOS 26 avec le verre : fusion native (GlassEffectContainer) ; sinon gouttes dessinées (flou + seuil). Ici,
// les règles pures : place des gouttes et choix du chemin. La barre elle-même reste à faire : voir
// docs/contexte/REPRISE-ANIMATIONS.md.
import CoreGraphics

enum DropLayout {
    /// Centres des gouttes depuis le bord gauche de la barre, à `progress` (0 : toutes dans la première, 1 : posées
    /// côte à côte). Barre trop étroite : le pas se resserre (les gouttes se fondent) pour que la dernière tienne.
    static func positions(count: Int, progress: CGFloat, width: CGFloat, size: CGFloat, spacing: CGFloat) -> [CGFloat] {
        guard count > 0 else { return [] }
        let start = size / 2
        var step = size + spacing
        if count > 1 {
            let room = max(width - size / 2 - start, 0)                // place pour les centres suivants
            step = min(step, room / CGFloat(count - 1))
        }
        let p = min(max(progress, 0), 1)
        return (0..<count).map { i in start + CGFloat(i) * step * p }
    }
}

enum LiquidDrops {
    /// Fusion native du verre : macOS 26 avec « Effet Liquid Glass » et transparence non réduite ; sinon gouttes
    /// dessinées.
    static func useNativeGlass(available: Bool, glassEnabled: Bool, reduceTransparency: Bool) -> Bool {
        available && glassEnabled && !reduceTransparency
    }
}
