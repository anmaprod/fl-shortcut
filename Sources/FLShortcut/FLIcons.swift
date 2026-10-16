// Grille des icônes de FL (« Change icon… », ou le bouton de l'icône de « Rename, color and icon », F2) : 14
// colonnes de cases carrées, 15 rangées, sous une barre de titres. L'API de FL ne lit ni ne pose les icônes : elles
// passent par cette fenêtre de FL, et seule sa géométrie compte pour cliquer la bonne case (aucune lecture de
// l'écran). Dans FL Shortcut, chaque case est dessinée par un symbole de macOS proche de l'icône de FL (pas les
// dessins de FL, qui appartiennent à Image-Line), avec le nom anglais de FL.
import CoreGraphics

enum FLIconGrid {
    static let columns = FLIcon.columns
    static let rows = FLIcon.rows
    /// Colonne « Channel » : ses titres Quad / 5.1 / 7.1 décalent les cases, elle n'est pas proposée.
    static let channelColumn = 13

    /// Une case : symbole de macOS et nom anglais de FL.
    struct Cell: Equatable {
        let symbol: String
        let name: String
    }

    private static func c(_ symbol: String, _ name: String) -> Cell { Cell(symbol: symbol, name: name) }

    /// Titres de la barre du haut et leur première colonne (un titre couvre les colonnes jusqu'au suivant).
    /// Colonnes 1 à 5 : quel titre en couvre deux reste à confirmer sur la grille de FL (Synth, d'après ses
    /// dernières cases Decay et Monster).
    static let titles: [(column: Int, title: String)] = [
        (0, "Reset"), (1, "Content"), (2, "Instr"), (3, "Solfège"), (4, "Synth"), (6, "Effect"), (7, "Gear"),
        (8, "Misc"), (10, "Info"), (11, "Number"), (12, "Routing"), (13, "Channel"),
    ]

    /// Cases de chaque colonne, de haut en bas ; au-delà, les cases de FL sont vides. Colonnes 1 à 5 : cases à
    /// reprendre du relevé de la grille de FL (en attendant, rien n'y est proposé).
    static let table: [[Cell]] = [
        // Reset : retire l'icône dans FL.
        [c("arrow.uturn.backward", "Reset")],
        // Content
        [],
        // Instr
        [],
        // Solfège
        [],
        // Synth (1)
        [],
        // Synth (2) (se termine par Decay et Monster)
        [],
        // Effect
        [c("lightbulb", "Lamp"), c("rectangle.portrait", "Pedal"), c("chart.line.downtrend.xyaxis", "Low pass"),
         c("chart.line.uptrend.xyaxis", "High pass"), c("diamond", "Band"), c("building.columns", "Reverb"),
         c("film", "Film"), c("leaf", "Flower"), c("line.3.horizontal.decrease.circle", "Filter")],
        // Gear
        [c("megaphone.fill", "Horn"), c("circle.grid.cross", "MIDI"), c("headphones", "Headphones"),
         c("speaker.fill", "Speaker"), c("mic.fill", "Microphone"), c("cable.connector", "Jack"),
         c("opticaldisc", "CD"), c("record.circle", "Vinyl"), c("hand.tap", "Touch"), c("dial.min", "Knob"),
         c("gamecontroller", "Joystick")],
        // Misc (1)
        [c("gearshape", "Cog"), c("wrench", "Wrench"), c("scissors", "Scissors"), c("magnifyingglass", "Search"),
         c("battery.100", "Battery"), c("paperclip", "Magnet"), c("lock.open", "Lock"), c("folder", "Folder"),
         c("link", "Link"), c("shippingbox", "Box"), c("doc.on.doc", "Copy"), c("bandage", "Bandage"),
         c("clock", "Clock"), c("briefcase", "Case"), c("figure.walk", "Character")],
        // Misc (2)
        [c("hand.raised", "Hand"), c("hands.clap", "Clap")],
        // Info
        [c("info.circle", "Info"), c("pencil", "Pencil"), c("questionmark", "Question"),
         c("exclamationmark", "Exclamation"), c("hand.thumbsup.fill", "Thumbs up"),
         c("hand.thumbsdown.fill", "Thumbs down"), c("eyes", "Silly"), c("face.smiling", "Happy"),
         c("cloud.rain", "Sad"), c("nosign", "Forbidden"), c("eye", "Eye"), c("macwindow.on.rectangle", "Windows"),
         c("macwindow", "Window"), c("flame.fill", "Fire"), c("snowflake", "Snow")],
        // Number
        [c("1.circle", "1"), c("2.circle", "2"), c("3.circle", "3"), c("4.circle", "4"), c("5.circle", "5"),
         c("6.circle", "6"), c("7.circle", "7"), c("8.circle", "8"), c("9.circle", "9"), c("0.circle", "0")],
        // Routing
        [c("arrow.triangle.branch", "Route 1"), c("point.3.connected.trianglepath.dotted", "Route 2"),
         c("arrow.triangle.merge", "Route 3"), c("arrow.triangle.pull", "Route 4"), c("paperplane.fill", "Send"),
         c("arrow.right.to.line", "Input"), c("rectangle.portrait.and.arrow.right", "Output")],
    ]

    /// La case de FL, ou nil si elle est vide (ou dans la colonne Channel).
    static func cell(_ icon: FLIcon) -> Cell? {
        guard icon.column != channelColumn, icon.column < table.count, icon.row < table[icon.column].count else {
            return nil
        }
        return table[icon.column][icon.row]
    }

    /// Case proposée dans FL Shortcut : une case relevée, hors de la colonne Channel.
    static func isPickable(_ icon: FLIcon) -> Bool { cell(icon) != nil }

    /// Toutes les cases proposées dans FL Shortcut, colonne par colonne.
    static var pickable: [FLIcon] {
        var out: [FLIcon] = []
        for column in table.indices where column != channelColumn {
            for row in table[column].indices {
                if let icon = FLIcon(column: column, row: row) { out.append(icon) }
            }
        }
        return out
    }

    /// Centre de la case dans la fenêtre de la grille de FL (coordonnées de l'écran, origine en haut à gauche) :
    /// cases carrées de L / 14, barre des titres de H − 15 cases.
    static func center(of icon: FLIcon, in window: CGRect) -> CGPoint {
        let side = window.width / CGFloat(columns)
        let header = window.height - CGFloat(rows) * side
        return CGPoint(x: window.minX + (CGFloat(icon.column) + 0.5) * side,
                       y: window.minY + header + (CGFloat(icon.row) + 0.5) * side)
    }
}
