// Programme prêt à tourner (miroir de MacroProgram, Sources/FLShortcut/MacroValidation.swift) : blocs validés une
// fois, besoins agrégés, raison du refus. Immuable : l'interpréteur ne revalide jamais.
namespace FLShortcut.Core.Macros;

public sealed class MacroProgram
{
    /// Macro de la bibliothèque d'où il vient (Guid.Empty : essais).
    public Guid Id { get; }
    public int Revision { get; }
    public string Name { get; }
    public IReadOnlyList<Block> Blocks { get; }
    public IReadOnlyList<VariableDecl> Variables { get; }
    /// Besoins agrégés des blocs actifs.
    public BlockNeeds Needs { get; }
    /// null = prêt à tourner.
    public string? Problem { get; }

    public bool IsRunnable => Problem is null;

    /// Titre du journal : noms des blocs du premier niveau (« trackMenu > waitDialog > … », comme le Mac).
    public string Title => string.Join(" > ", Blocks.Where(b => b.Enabled && b.Body is not BlockBody.Comment)
        .Select(b => BlockRegistry.Journal(b.Body)));

    public MacroProgram(IReadOnlyList<Block> blocks, string name, ValidationContext context,
                        IReadOnlyList<VariableDecl>? variables = null, Guid? id = null, int revision = 0)
    {
        Id = id ?? Guid.Empty;
        Revision = revision;
        Name = name;
        Blocks = blocks;
        Variables = variables ?? Array.Empty<VariableDecl>();
        Needs = MacroValidation.Needs(blocks);
        Problem = MacroValidation.Problem(blocks, Variables, context);
    }

    /// Macro refusée avant ses blocs (nom, format) : rien ne tourne.
    private MacroProgram(string failed, string name, Guid id, int revision)
    {
        Id = id;
        Revision = revision;
        Name = name;
        Blocks = Array.Empty<Block>();
        Variables = Array.Empty<VariableDecl>();
        Needs = BlockNeeds.None;
        Problem = failed;
    }

    /// Macro de la bibliothèque : règles strictes des fichiers ; preset hors du dossier personnel permis pour une
    /// copie de l'ancien modèle « Enregistrement rapide » (comme le Mac). `context` : dossier personnel des essais.
    public static MacroProgram Compile(MacroDoc doc, ValidationContext? context = null)
    {
        var ctx = (context ?? new ValidationContext()) with
        {
            StrictFiles = true,
            PresetAnywhere = doc.Origin is { Kind: "template", Template: "autoRecord" },
        };
        return MacroValidation.Problem(doc, ctx) is { } why
            ? new MacroProgram(why, doc.Name, doc.Id, doc.Revision)
            : new MacroProgram(doc.Blocks, doc.Name, ctx, doc.Variables, doc.Id, doc.Revision);
    }
}
