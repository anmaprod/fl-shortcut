// La grille « Change icon… » de FL (14 colonnes, 15 rangées) : titres de la barre du haut et nom anglais de chaque
// case, comme la barre d'aide de FL. Miroir de FLIconGrid du Mac (Sources/FLShortcut/FLIcons.swift, même ordre, essai
// qui compare) ; les images viennent de la même planche (Resources/FLIcons.png, cases de 88 pixels).
namespace FLShortcut.Core.Organizer;

public static class FlIconGrid
{
    public const int Columns = FlIcon.Columns;
    public const int Rows = FlIcon.Rows;
    /// Colonne « Channel » : ses titres Quad / 5.1 / 7.1 décalent les cases, elle n'est pas proposée.
    public const int ChannelColumn = 13;
    /// Côté d'une case dans la planche (pixels).
    public const int CellPixels = 88;

    /// Titres de la barre du haut et leur première colonne (un titre couvre les colonnes jusqu'au suivant).
    public static readonly IReadOnlyList<(int Column, string Title)> Titles = new[]
    {
        (0, "Reset"), (1, "Content"), (2, "Instr"), (4, "Solfège"), (5, "Synth"), (6, "Effect"), (7, "Gear"),
        (8, "Misc"), (10, "Info"), (11, "Number"), (12, "Routing"), (13, "Channel"),
    };

    /// Nom de chaque case, colonne par colonne, de haut en bas ; au-delà, les cases de FL sont vides.
    public static readonly IReadOnlyList<string[]> Table = new[]
    {
        new[] { "Reset" },
        new[] { "Score", "Melodic score", "Step sequence", "Automation", "Automation", "Audio", "Master", "Cloud" },
        new[]
        {
            "Dry guitar", "Electric guitar", "Violin", "Banjo", "Trumpet", "Saxophone", "Snare drum", "Kick drum", "Bongos",
            "Tambourine", "Shaker", "Drum machine", "Drum pads", "Cymbal", "High Hat",
        },
        new[]
        {
            "Gong", "Triangle", "Bell", "More cowbell", "Chimes", "Glockenspiel", "Piano / keyboard", "Organ", "Pan flute",
            "Flute", "Whistle", "Harp",
        },
        new[] { "Treble clef", "Bass clef", "Diapason", "Arpeggiato" },
        new[]
        {
            "Sawtooth / synthesizer", "Pulse / synthesizer", "Wobbling", "Sample", "Sliced loop", "Speech", "Male speech",
            "Female speech", "Vocoder", "Additive", "Subtractive", "FM", "Sustaining", "Plucked", "Harmor",
        },
        new[] { "Effect", "Compression", "Low-pass", "High-pass", "Equalizer", "Reverb", "Movie score", "Nature sounds", "Filter" },
        new[]
        {
            "Plugin", "MIDI", "Headphones", "Speakers", "Microphone", "Jack plug", "CD / DVD", "LP", "Touchscreen",
            "Knob / remote control", "Joystick / remote control",
        },
        new[]
        {
            "Gear", "Wrench", "Scissors", "Magnifying glass", "Battery", "Magnet", "Padlock", "Folder", "Link", "Package",
            "Project", "Patch", "Time", "Building block", "Jet Set Willy",
        },
        new[] { "Snap", "Clap" },
        new[]
        {
            "Comment", "Pencil", "?", "!", "Good", "Bad", "Ugly", "Happy", "Sad", "Forbidden", "Visual", "Foreground",
            "Background", "Hot", "Snowflake",
        },
        new[] { "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Zero" },
        new[] { "Track routing", "Track routing", "Track routing", "Track routing", "Send", "In", "Out" },
    };

    /// Le nom de la case, ou null si elle est vide (ou dans la colonne Channel).
    public static string? Name(FlIcon icon) =>
        icon.Column != ChannelColumn && icon.Column < Table.Count && icon.Row < Table[icon.Column].Length
            ? Table[icon.Column][icon.Row]
            : null;

    /// Case proposée dans FL Shortcuts : une case relevée, hors de la colonne Channel. « Reset » n'en est pas une
    /// (dans FL, il retire l'icône) : c'est « Aucune » dans FL Shortcuts.
    public static bool IsPickable(FlIcon icon) => !icon.IsReset && Name(icon) is not null;

    /// Un titre de la barre du haut de la grille proposée (ni Reset ni Channel) et le nombre de colonnes qu'il couvre.
    public static IReadOnlyList<(int Column, string Title, int Span)> Headers()
    {
        var shown = Titles.Where(t => t.Column > 0 && t.Column < ChannelColumn).ToList();
        var out_ = new List<(int, string, int)>();
        for (var i = 0; i < shown.Count; i++)
        {
            var next = i + 1 < shown.Count ? shown[i + 1].Column : ChannelColumn;
            out_.Add((shown[i].Column, shown[i].Title, next - shown[i].Column));
        }
        return out_;
    }
}
