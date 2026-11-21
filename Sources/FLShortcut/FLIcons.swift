// Grille des icônes de FL (« Change icon… » du menu du clic droit d'un son ou d'une piste) : 14
// colonnes de cases carrées, 15 rangées, sous une barre de titres. L'API de FL ne lit ni ne pose les icônes : elles
// passent par cette fenêtre de FL, et seule sa géométrie compte pour cliquer la bonne case (aucune lecture de
// l'écran). Dans FL Shortcuts, chaque case montre la vraie icône de FL (demande du propriétaire du 25/10, découpée de
// sa capture : FLIconArt), avec le nom anglais de FL ; le symbole de macOS proche ne sert que sans la planche.
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

    /// Titres de la barre du haut et leur première colonne (un titre couvre les colonnes jusqu'au suivant) :
    /// Instr couvre les colonnes 2 et 3, Misc les colonnes 8 et 9.
    static let titles: [(column: Int, title: String)] = [
        (0, "Reset"), (1, "Content"), (2, "Instr"), (4, "Solfège"), (5, "Synth"), (6, "Effect"), (7, "Gear"),
        (8, "Misc"), (10, "Info"), (11, "Number"), (12, "Routing"), (13, "Channel"),
    ]

    /// Cases de chaque colonne, de haut en bas, avec le nom de la barre d'aide de FL au survol ; au-delà, les
    /// cases de FL sont vides.
    static let table: [[Cell]] = [
        // Reset : retire l'icône dans FL (barre d'aide : « None »).
        [c("arrow.uturn.backward", "Reset")],
        // Content (deux cases portent le nom « Automation » dans FL)
        [c("music.note", "Score"), c("pianokeys", "Melodic score"), c("square.grid.4x3.fill", "Step sequence"),
         c("chart.bar.fill", "Automation"), c("point.topleft.down.to.point.bottomright.curvepath", "Automation"),
         c("waveform", "Audio"), c("crown", "Master"), c("cloud.fill", "Cloud")],
        // Instr (1)
        [c("guitars", "Dry guitar"), c("guitars.fill", "Electric guitar"), c("guitars", "Violin"),
         c("guitars", "Banjo"), c("horn", "Trumpet"), c("horn.fill", "Saxophone"), c("hockey.puck", "Snare drum"),
         c("circle.circle", "Kick drum"), c("cylinder.split.1x2", "Bongos"), c("circle.dotted", "Tambourine"),
         c("dot.radiowaves.left.and.right", "Shaker"), c("square.grid.3x3.fill", "Drum machine"),
         c("rectangle.grid.2x2", "Drum pads"), c("circle.and.line.horizontal.fill", "Cymbal"),
         c("circle.and.line.horizontal", "High Hat")],
        // Instr (2)
        [c("smallcircle.filled.circle", "Gong"), c("triangle", "Triangle"), c("bell", "Bell"),
         c("bell.fill", "More cowbell"), c("wind", "Chimes"), c("rectangle.split.3x3", "Glockenspiel"),
         c("pianokeys.inverse", "Piano / keyboard"), c("music.note.house", "Organ"), c("chart.bar.xaxis", "Pan flute"),
         c("line.diagonal", "Flute"), c("wave.3.right", "Whistle"), c("lines.measurement.vertical", "Harp")],
        // Solfège
        [c("music.quarternote.3", "Treble clef"), c("music.note.list", "Bass clef"), c("tuningfork", "Diapason"),
         c("stairs", "Arpeggiato")],
        // Synth
        [c("waveform.path", "Sawtooth / synthesizer"), c("waveform.path.ecg", "Pulse / synthesizer"),
         c("wave.3.forward", "Wobbling"), c("waveform.circle", "Sample"), c("rectangle.split.3x1", "Sliced loop"),
         c("mouth", "Speech"), c("person.fill", "Male speech"), c("figure.stand.dress", "Female speech"),
         c("waveform.badge.mic", "Vocoder"), c("plus", "Additive"), c("minus", "Subtractive"), c("function", "FM"),
         c("mountain.2", "Sustaining"), c("arrow.down.right", "Plucked"), c("theatermasks", "Harmor")],
        // Effect
        [c("lightbulb", "Effect"), c("rectangle.portrait", "Compression"), c("chart.line.downtrend.xyaxis", "Low-pass"),
         c("chart.line.uptrend.xyaxis", "High-pass"), c("diamond", "Equalizer"), c("building.columns", "Reverb"),
         c("film", "Movie score"), c("leaf", "Nature sounds"), c("line.3.horizontal.decrease.circle", "Filter")],
        // Gear
        [c("megaphone.fill", "Plugin"), c("circle.grid.cross", "MIDI"), c("headphones", "Headphones"),
         c("speaker.fill", "Speakers"), c("mic.fill", "Microphone"), c("cable.connector", "Jack plug"),
         c("opticaldisc", "CD / DVD"), c("record.circle", "LP"), c("hand.tap", "Touchscreen"),
         c("dial.min", "Knob / remote control"), c("gamecontroller", "Joystick / remote control")],
        // Misc (1)
        [c("gearshape", "Gear"), c("wrench", "Wrench"), c("scissors", "Scissors"),
         c("magnifyingglass", "Magnifying glass"), c("battery.100", "Battery"), c("paperclip", "Magnet"),
         c("lock.open", "Padlock"), c("folder", "Folder"), c("link", "Link"), c("shippingbox", "Package"),
         c("doc.on.doc", "Project"), c("bandage", "Patch"), c("clock", "Time"), c("briefcase", "Building block"),
         c("figure.walk", "Jet Set Willy")],
        // Misc (2)
        [c("hand.raised", "Snap"), c("hands.clap", "Clap")],
        // Info
        [c("info.circle", "Comment"), c("pencil", "Pencil"), c("questionmark", "?"), c("exclamationmark", "!"),
         c("hand.thumbsup.fill", "Good"), c("hand.thumbsdown.fill", "Bad"), c("eyes", "Ugly"),
         c("face.smiling", "Happy"), c("cloud.rain", "Sad"), c("nosign", "Forbidden"), c("eye", "Visual"),
         c("macwindow.on.rectangle", "Foreground"), c("macwindow", "Background"), c("flame.fill", "Hot"),
         c("snowflake", "Snowflake")],
        // Number
        [c("1.circle", "One"), c("2.circle", "Two"), c("3.circle", "Three"), c("4.circle", "Four"),
         c("5.circle", "Five"), c("6.circle", "Six"), c("7.circle", "Seven"), c("8.circle", "Eight"),
         c("9.circle", "Nine"), c("0.circle", "Zero")],
        // Routing (les quatre premières cases portent le nom « Track routing » dans FL)
        [c("arrow.triangle.branch", "Track routing"), c("point.3.connected.trianglepath.dotted", "Track routing"),
         c("arrow.triangle.merge", "Track routing"), c("arrow.triangle.pull", "Track routing"),
         c("paperplane.fill", "Send"), c("arrow.right.to.line", "In"), c("rectangle.portrait.and.arrow.right", "Out")],
    ]

    /// La case de FL, ou nil si elle est vide (ou dans la colonne Channel).
    static func cell(_ icon: FLIcon) -> Cell? {
        guard icon.column != channelColumn, icon.column < table.count, icon.row < table[icon.column].count else {
            return nil
        }
        return table[icon.column][icon.row]
    }

    /// Case proposée dans FL Shortcuts : une case relevée, hors de la colonne Channel.
    /// « Reset » n'en est pas une (retour du 31/10 : dans FL, il retire l'icône) : « Aucune » dans FL Shortcuts.
    static func isPickable(_ icon: FLIcon) -> Bool { !icon.isReset && cell(icon) != nil }

    /// Toutes les cases proposées dans FL Shortcuts, colonne par colonne.
    static var pickable: [FLIcon] {
        var out: [FLIcon] = []
        for column in table.indices where column != channelColumn {
            for row in table[column].indices {
                if let icon = FLIcon(column: column, row: row), !icon.isReset { out.append(icon) }
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
