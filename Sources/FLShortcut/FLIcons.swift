// Grille des icônes de FL (« Change icon… », ou le bouton de l'icône de « Rename, color and icon », F2) : 14
// colonnes de cases carrées, 15 rangées, sous une barre de titres. L'API de FL ne lit ni ne pose les icônes : elles
// passent par cette fenêtre de FL, et seule sa géométrie compte pour cliquer la bonne case (aucune lecture de
// l'écran). Le nom de chaque case et la répartition des titres sur les colonnes restent à relever sur la grille de
// FL : en attendant, une case se désigne par sa place (colonne et rangée).
import CoreGraphics

enum FLIconGrid {
    static let columns = FLIcon.columns
    static let rows = FLIcon.rows
    /// Colonne « Channel » : ses titres Quad / 5.1 / 7.1 décalent les cases, elle n'est pas proposée.
    static let channelColumn = 13

    /// Case proposée dans FL Shortcut (toute la grille sauf la colonne « Channel »).
    static func isPickable(_ icon: FLIcon) -> Bool { icon.column != channelColumn }

    /// Symbole de macOS et nom anglais de FL d'une case ; nil tant que la case n'est pas relevée.
    static func cell(_ icon: FLIcon) -> (symbol: String, name: String)? { nil }

    /// Centre de la case dans la fenêtre de la grille (coordonnées de l'écran, origine en haut à gauche) : cases de
    /// L / 14 de côté, barre de titres de H − 15 × L / 14 (L, H : largeur et hauteur de la fenêtre).
    static func center(of icon: FLIcon, in window: CGRect) -> CGPoint {
        let side = window.width / CGFloat(columns)
        let titleBar = window.height - CGFloat(rows) * side
        return CGPoint(x: window.minX + (CGFloat(icon.column) + 0.5) * side,
                       y: window.minY + titleBar + (CGFloat(icon.row) + 0.5) * side)
    }
}
