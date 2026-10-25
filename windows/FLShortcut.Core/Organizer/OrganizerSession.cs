// Organiser : tout le projet d'un coup, d'après son fichier. FL enregistre le projet, l'Organiser le lit : les sons de
// chaque pattern et de chaque piste sont ceux de ses notes et de ses clips (rien n'est deviné) ; les sons sans note ni
// clip sont laissés de côté (puis supprimés dans la copie). Chaque son est reconnu à son nom ou écouté seul, dans le
// premier pattern où il a des notes, toujours au tempo du projet (jamais accéléré : refusé par le propriétaire) ; un
// clip audio : son fichier lu directement, son passage le plus fort. Les envois du Mixer sont lus. FL est toujours
// remis comme avant (opération 7 : sourdines…), même après une erreur ou Échap. Les noms ne sont jamais journalisés.
// Miroir de Sources/FLShortcut/OrganizerSession.swift (analyse sur le fichier, la seule de l'appli).
namespace FLShortcut.Core.Organizer;

public sealed class OrganizerSession
{
    public sealed record Timing
    {
        /// Écoute de ta partie (le pattern depuis son début), au plus.
        public double Listen { get; init; } = 3;
        /// Durée de chaque note d'essai.
        public double TestNote { get; init; } = 0.3;
        /// Queue du son après les notes d'essai.
        public double Tail { get; init; } = 0.4;
        /// Échap est vu au plus tard après ce délai.
        public double Slice { get; init; } = 0.05;
        /// Écoute après le premier son entendu : assez pour le classer.
        public double AfterSound { get; init; } = 1.5;
        /// Encore rien entendu au bout de ce délai : les notes d'essai tout de suite.
        public double SilentGiveUp { get; init; } = 1.5;
        /// Piste de la Playlist jouée seule : ce qui y joue, relevé pendant ce temps (vérifications).
        public double TrackListen { get; init; } = 1.5;
        /// Clip audio pas retrouvé sur le disque : sa note de base tenue ce temps-là une fois qu'il sonne…
        public double ClipListen { get; init; } = 1.5;
        /// … attendu au plus ce temps-là (un enregistrement commence souvent par un silence).
        public double ClipWait { get; init; } = 5;
    }

    /// Famille, confiance et règle appliquée (diagnostic : « melodie+iv12 », jamais un nom).
    public delegate (SoundFamily Family, double Confidence, string Rule) Classify(float[] samples, double rate);
    /// Sorte d'un son classé en drums.
    public delegate SoundKind NameDrum(float[] samples, double rate);
    /// Sorte d'un son classé en mélodie ; null : rien de sûr.
    public delegate SoundKind? NameMelody(float[] samples, double rate);
    /// Sorte d'une voix, d'une basse ou d'un FX (IA intégrée) ; null : le mot général de la famille.
    public delegate SoundKind? NameKind(float[] samples, double rate, SoundFamily family);
    /// Ce que l'IA intégrée retient d'un son écouté (des nombres) ; null sans elle.
    public delegate SoundPrint? Fingerprint(float[] samples, double rate);
    /// Le fichier de son d'un clip audio, lu directement : son passage le plus fort ; null s'il n'est pas retrouvé.
    public delegate SampleSound? SoundFile(string path, string project);

    /// Notes d'essai : C3 puis C5 (pour FPC, ses deux premiers pads).
    public static readonly byte[] TestNotes = { 48, 60 };
    /// Note de base d'un clip audio (C5) : il joue tel quel, ni plus grave ni plus lent.
    public const byte ClipNote = 60;
    public const byte TestVelocity = 100;
    /// Un classement fait avec les notes d'essai compte moins.
    public const double TestNotesFactor = 0.7;
    /// Classé d'après son nom : aussi sûr qu'une bonne écoute.
    public const double NameConfidence = 0.9;
    /// Pistes du Mixer dont les envois sont lus au plus.
    public const int MaxRouted = 64;

    private readonly IOrganizerLink _link;
    private readonly IAudioSource _audio;
    private readonly Classify _classify;
    private readonly NameDrum? _nameDrum;
    private readonly NameMelody? _nameMelody;
    private readonly NameKind? _nameKind;
    private readonly Fingerprint? _fingerprint;
    private readonly SoundFile? _soundFile;
    private readonly ProjectFileAccess _files;
    private readonly Timing _timing;
    private readonly Action<double> _sleep;
    private readonly Func<bool> _escape;
    private readonly Action<int, int> _progress;
    private readonly object _gate = new();
    private bool _stopped;
    private readonly OrganizerDiagnostics _diag = new();
    private Dictionary<int, string> _clipPaths = new();
    private string? _projectPath;
    private int _stepsDone;
    private int _stepsTotal;

    public OrganizerSession(IOrganizerLink link, IAudioSource audio, Classify classify, ProjectFileAccess files,
        NameDrum? nameDrum = null, NameMelody? nameMelody = null, NameKind? nameKind = null, Fingerprint? fingerprint = null,
        Timing? timing = null, Action<double>? sleep = null, Func<bool>? escape = null, SoundFile? soundFile = null,
        Action<int, int>? progress = null)
    {
        _link = link;
        _audio = audio;
        _classify = classify;
        _files = files;
        _nameDrum = nameDrum;
        _nameMelody = nameMelody;
        _nameKind = nameKind;
        _fingerprint = fingerprint;
        _timing = timing ?? new Timing();
        _sleep = sleep ?? (s => Thread.Sleep(TimeSpan.FromSeconds(s)));
        _escape = escape ?? (() => false);
        _soundFile = soundFile;
        _progress = progress ?? ((_, _) => { });
    }

    /// Ce que l'analyse a fait (lu une fois `Run` fini).
    public OrganizerDiagnostics Diagnostics
    {
        get
        {
            lock (_gate)
            {
                var out_ = _diag.Copy();
                out_.Capture = _audio.Stats;
                return out_;
            }
        }
    }

    private void Note(Action<OrganizerDiagnostics> change)
    {
        lock (_gate) change(_diag);
    }

    /// Échap : l'analyse s'arrête au plus tard après `Timing.Slice`, puis FL est remis comme avant.
    public void Cancel()
    {
        lock (_gate) _stopped = true;
    }

    private bool IsCancelled { get { lock (_gate) return _stopped; } }

    private void Plan(int more)
    {
        _stepsTotal += more;
        _progress(_stepsDone, _stepsTotal);
    }

    private void Step()
    {
        if (IsCancelled) throw OrganizerError.Cancelled;
        _progress(_stepsDone, _stepsTotal);
        _stepsDone++;
    }

    /// Bloquant (à lancer hors du fil de l'interface) ; `progress(fait, total)` est appelé à chaque étape et à la fin.
    /// Renvoie le résultat, ou l'erreur.
    public (OrganizerResult? Result, OrganizerError? Error) Run()
    {
        try
        {
            // La première commande réveille le script ; un script d'avant la v14 la refuse : FL à redémarrer, rien
            // n'est touché.
            _link.HeardTracks();
            // Sur le fichier : tous les sons, comme « All » dans le Channel rack, même s'il montre un groupe.
            _link.AllChannels = true;
            var lengths = _link.PatternLengths();
            var patterns = _link.ListPatterns();
            var channels = _link.ListChannels();
            var mixer = _link.ListMixer();
            return (RunOnFile(channels, patterns, mixer, lengths.Tempo), null);
        }
        catch (OrganizerError e)
        {
            Note(d => d.Error = e.Code);
            return (null, e);
        }
        catch (Exception e)
        {
            Note(d => d.Error = e.GetType().Name);
            return (null, OrganizerError.Failed(Loc.F("Écoute de FL impossible (%@).", e.GetType().Name)));
        }
    }

    /// L'analyse sur le fichier du projet : FL l'enregistre, l'Organiser le lit. Puis chaque son est reconnu à son nom
    /// ou écouté seul, dans le premier pattern où il a des notes.
    private OrganizerResult RunOnFile(List<ChannelInfo> channels, List<PatternInfo> patterns, List<MixerTrackInfo> mixer, double tempo)
    {
        Note(d =>
        {
            d.Listed = channels.Count;
            d.Patterns = patterns.Count;
            d.Selection = "fichier";
            d.Tempo = (int)Math.Round(tempo, MidpointRounding.AwayFromZero);
        });
        try
        {
            var read = ProjectFile.Read(_files, null, channels, patterns, why => Note(d => d.File = why));
            // Chaque pattern de plusieurs sons séparé son par son (« Split by channel » de FL), comme il le sera dans
            // la copie rangée. L'écoute se fait dans le projet ouvert : les patterns d'avant.
            var split = ProjectFile.Splitting(read.Project, read.File);
            var notSounds = channels.Where(c => c.Type == ChannelInfo.AutomationType).Select(c => c.Index).ToHashSet();
            var exact = ProjectFile.Sounds(split.Project, notSounds);
            var homes = Homes(ProjectFile.Sounds(read.Project, notSounds).Patterns);
            Note(d =>
            {
                d.File = "oui";
                d.Clips = split.Project.Clips.Count;
                d.Split = split.Added;
                d.PatternMap = SoundMap(exact.Patterns, "pattern");
                d.TrackMap = SoundMap(exact.Tracks, "piste");
            });
            var unused = Organize.Sounds(channels).Select(c => c.Index).Where(i => !exact.Used.Contains(i)).ToHashSet();
            var targets = Organize.Sounds(channels).Where(c => !unused.Contains(c.Index)).ToList();
            Note(d => d.Unused = unused.Count);
            _audio.Start();
            try
            {
                _clipPaths = ProjectFile.ClipPaths(read.Project);
                _projectPath = read.Path;
                AppLog.Write("ORGANIZE", $"project read: {split.Project.Clips.Count} clips, {split.Added} split, "
                    + $"{_clipPaths.Count} audio files, {targets.Count} sounds");
                var items = ClassifyChannels(targets, homes, ProjectFile.SampleNames(read.Project));
                var routes = ReadRoutes(targets, mixer);
                _progress(_stepsTotal, _stepsTotal);
                return new OrganizerResult
                {
                    Channels = channels,
                    Items = items,
                    Patterns = ProjectFile.Patterns(patterns, split.Project),
                    PatternSounds = exact.Patterns,
                    Mixer = mixer,
                    Routes = routes,
                    TrackSounds = exact.Tracks,
                    Unused = unused,
                    Project = ProjectFile.Snapshot(split.Project, read.Path, notSounds, split.Added),
                };
            }
            finally
            {
                // FL d'abord remis (lecture arrêtée, sourdines), puis la capture arrêtée : FL redevient audible.
                _link.StopRestore();
                _audio.Stop();
            }
        }
        finally
        {
            var found = _files.Search();
            Note(d => d.Search = found);
        }
    }

    /// Pur (testé) : sons laissés de côté sans fichier (FL a sélectionné ceux qui n'ont aucune note), jamais un clip
    /// audio ni un son entendu.
    public static HashSet<int> Unused(IEnumerable<ChannelInfo> channels, ISet<int>? selected, ISet<int> heard, bool complete)
    {
        var candidates = Organize.Sounds(channels).Where(c => c.Type != ChannelInfo.AudioClipType && !heard.Contains(c.Index))
            .Select(c => c.Index).ToList();
        if (selected is not null) return candidates.Where(selected.Contains).ToHashSet();
        if (!complete || heard.Count == 0) return new HashSet<int>();
        return candidates.ToHashSet();
    }

    /// Pur (testé) : les sons de chaque pattern ou piste (index 0 = le premier de FL), en numéros pour le diagnostic :
    /// « pattern1:c0,c3 pattern2:c1 ».
    public static string SoundMap(IReadOnlyDictionary<int, HashSet<int>> sounds, string label) =>
        string.Join(" ", sounds.Keys.OrderBy(k => k).Select(k => $"{label}{k + 1}:" + string.Join(",", sounds[k].OrderBy(s => s).Select(s => $"c{s}"))));

    /// Pur (testé) : le premier pattern (1 = le premier de FL) où joue chaque son.
    public static Dictionary<int, int> Homes(IReadOnlyDictionary<int, HashSet<int>> patternSounds)
    {
        var out_ = new Dictionary<int, int>();
        foreach (var pattern in patternSounds.Keys.OrderBy(p => p))
            foreach (var channel in patternSounds[pattern])
                out_.TryAdd(channel, pattern + 1);
        return out_;
    }

    // ---------- Sons du Channel rack ----------

    /// Chaque son : son nom s'il dit ce qu'il est, sinon son écoute (la capture est déjà lancée), dans le pattern où il
    /// joue. Un nom que l'Organiser a pu donner reste seulement si l'écoute ne le contredit pas. Pas un son entendu et
    /// rien d'après les noms : la capture ne reçoit rien (`NoSound`).
    private List<OrganizerItem> ClassifyChannels(List<ChannelInfo> targets, Dictionary<int, int> homes, Dictionary<int, string> hints)
    {
        var byIndex = new Dictionary<int, OrganizerItem>();
        var toListen = new List<ChannelInfo>();
        foreach (var channel in targets)
        {
            // Le nom du canal, sinon celui de son fichier de son.
            var named = SoundNames.IsGenerated(channel.Name) ? null : SoundNames.KindOf(channel.Name);
            var kind = named ?? (hints.TryGetValue(channel.Index, out var hint) ? SoundNames.KindOf(hint) : null);
            if (kind is { } k) byIndex[channel.Index] = ByName(channel, k);
            else toListen.Add(channel);
        }
        Note(d =>
        {
            d.Targets = targets.Count;
            d.ByName = targets.Count - toListen.Count;
        });
        if (toListen.Count > 0)
        {
            Plan(toListen.Count);
            var heard = Listen(toListen, homes);
            foreach (var item in heard.Items)
            {
                var channel = toListen.FirstOrDefault(c => c.Index == item.Index);
                if (channel is not null && SoundNames.KindOf(channel.Name) is { } kind
                    && SoundNames.Keeps(kind, new Verdict(item.Family, item.Kind)))
                {
                    byIndex[item.Index] = ByName(channel, kind);
                }
                else if (channel is not null && SoundNames.IsMelodicSynth(channel.Name)
                         && item.Family is SoundFamily.Drums or SoundFamily.Fx)
                {
                    // Un synthé de mélodies entendu comme des drums ou un FX : une mélodie.
                    byIndex[item.Index] = item with { Family = SoundFamily.Melody, Kind = null };
                    Note(d => d.Rules.Add($"c{item.Index}:synthe"));
                }
                else
                {
                    byIndex[item.Index] = item;
                }
            }
            if (!heard.AnyHeard && !byIndex.Values.Any(i => i.ByName)) throw OrganizerError.NoSound;
        }
        return targets.Where(c => byIndex.ContainsKey(c.Index)).Select(c => byIndex[c.Index]).ToList();
    }

    private static OrganizerItem ByName(ChannelInfo channel, SoundKind kind) => new()
    {
        Index = channel.Index, Name = channel.Name, Family = kind.Family(), Confidence = NameConfidence, TestNotes = false,
        MixerTrack = channel.MixerTrack, Color = channel.Color, Kind = kind, ByName = true,
    };

    /// Chaque son écouté seul, dans un pattern où il joue (sinon le pattern ouvert), puis deux notes d'essai s'il se
    /// tait ; un clip audio : son fichier lu directement, sinon sa note de base jouée dans FL.
    private (List<OrganizerItem> Items, bool AnyHeard) Listen(List<ChannelInfo> targets, Dictionary<int, int> homes)
    {
        var items = new List<OrganizerItem>();
        var heardAny = false;
        for (var k = 0; k < targets.Count; k++)
        {
            var channel = targets[k];
            Step();
            float[] samples;
            var rate = _audio.Rate;
            var tested = false;
            var source = "";
            if (channel.Type == ChannelInfo.AudioClipType && FileSound(channel.Index) is { } sound)
            {
                samples = sound.Samples;
                rate = sound.Rate;
                source = "+fichier";
            }
            else
            {
                _audio.Reset();
                _link.PlaySolo(channel.Index, homes.TryGetValue(channel.Index, out var home) ? home : null);
                if (channel.Type == ChannelInfo.AudioClipType)
                {
                    samples = PlayClip(channel.Index);
                }
                else
                {
                    samples = ListenUntilHeard();
                    tested = PeakDB(samples) < FamilyFusion.SilenceDB;
                    if (tested) samples = PlayTestNotes(channel.Index);
                }
            }
            AppLog.Write("ORGANIZE", $"listen {k + 1}/{targets.Count}{(source.Length == 0 ? "" : " file")}");
            var heard = PeakDB(samples) >= FamilyFusion.SilenceDB;
            if (heard) heardAny = true;
            var verdict = _classify(samples, rate);
            Note(d =>
            {
                d.Listened++;
                if (heard) d.Heard++;
                if (tested) d.TestNotes++;
                d.Rules.Add($"c{channel.Index}:{verdict.Rule}{source}");
            });
            var kind = heard ? NameOf(samples, rate, verdict.Family) : null;
            items.Add(new OrganizerItem
            {
                Index = channel.Index, Name = channel.Name, Family = verdict.Family,
                Confidence = tested ? verdict.Confidence * TestNotesFactor : verdict.Confidence, TestNotes = tested,
                MixerTrack = channel.MixerTrack, Color = channel.Color, Kind = kind,
                SoundPrint = heard ? _fingerprint?.Invoke(samples, rate) : null,
            });
        }
        return (items, heardAny);
    }

    /// Sorte d'un son entendu et classé : drums et mélodies par leurs règles, voix, basses et FX par l'IA intégrée.
    private SoundKind? NameOf(float[] samples, double rate, SoundFamily family) => family switch
    {
        SoundFamily.Drums => _nameDrum?.Invoke(samples, rate),
        SoundFamily.Melody => _nameMelody?.Invoke(samples, rate),
        SoundFamily.Vocals or SoundFamily.Bass or SoundFamily.Fx => _nameKind?.Invoke(samples, rate, family),
        _ => null,
    };

    /// Le fichier d'un clip audio lu directement ; null sans fichier retrouvé.
    private SampleSound? FileSound(int channel)
    {
        if (!_clipPaths.TryGetValue(channel, out var path) || _projectPath is null || _soundFile is null) return null;
        return _soundFile(path, _projectPath);
    }

    // ---------- Mixer ----------

    /// Envois des pistes du Mixer reliées à un son, puis de celles qui les reçoivent, `MaxRouted` pistes au plus. La
    /// piste « Current » (la dernière) ne compte pas ; le Master (0) est dit, mais pas suivi.
    private Dictionary<int, List<int>> ReadRoutes(List<ChannelInfo> targets, List<MixerTrackInfo> mixer)
    {
        var last = mixer.Count - 2;
        if (last < 1) return new Dictionary<int, List<int>>();
        var todo = targets.Select(c => c.MixerTrack).Where(t => t >= 1 && t <= last).Distinct().OrderBy(t => t).ToList();
        var seen = todo.ToHashSet();
        var out_ = new Dictionary<int, List<int>>();
        Note(d => d.MixerUsed = todo.Count);
        while (todo.Count > 0 && out_.Count < MaxRouted)
        {
            if (IsCancelled) throw OrganizerError.Cancelled;
            var track = todo[0];
            todo.RemoveAt(0);
            var all = _link.Routes(track);
            var dests = all.Where(d => d >= 1 && d <= last && d != track).ToList();
            // Le Master gardé s'il y est : une piste qui envoie au Master et à une autre n'est pas une piste de groupe.
            out_[track] = all.Contains(0) ? new[] { 0 }.Concat(dests).ToList() : dests;
            foreach (var d in dests) if (seen.Add(d)) todo.Add(d);
        }
        var sends = out_.Values.Sum(d => d.Count(x => x != 0));
        Note(d => d.Routes = sends);
        return out_;
    }

    // ---------- Écoute ----------

    /// Écoute jusqu'à `AfterSound` après le premier son entendu (`Listen` au plus) ; toujours muet au bout de
    /// `SilentGiveUp` : on arrête là (les notes d'essai prennent le relais).
    private float[] ListenUntilHeard()
    {
        var step = _timing.Slice;
        var steps = Math.Max(1, (int)Math.Ceiling(_timing.Listen / step));
        int? heardAt = null;
        var kept = new List<float>();
        for (var k = 1; k <= steps; k++)
        {
            Pause(step);
            var elapsed = k * step;
            var chunk = _audio.Take();
            if (heardAt is not null) kept.AddRange(chunk);
            else if (PeakDB(chunk) >= FamilyFusion.SilenceDB)
            {
                heardAt = k;
                kept = chunk.ToList();
            }
            if (heardAt is { } at && (k - at) * step >= _timing.AfterSound - 1e-9) break;
            if (heardAt is null && elapsed >= _timing.SilentGiveUp - 1e-9) break;
        }
        kept.AddRange(_audio.Take());
        return kept.ToArray();
    }

    /// Clip audio pas retrouvé : sa note de base tenue jusqu'à ce qu'il sonne (`ClipWait` au plus), puis `ClipListen`
    /// de son et la queue ; le silence du début ne compte pas. La note est toujours coupée, même après Échap.
    private float[] PlayClip(int channel)
    {
        _audio.Reset();
        _link.Audition(channel, ClipNote, TestVelocity);
        var kept = new List<float>();
        double silent = 0, sounding = 0;
        var finished = true;
        while (sounding < _timing.ClipListen - 1e-9)
        {
            if (!Wait(_timing.Slice)) { finished = false; break; }
            var chunk = _audio.Take();
            if (kept.Count == 0 && PeakDB(chunk) < FamilyFusion.SilenceDB)
            {
                silent += _timing.Slice;
                if (silent >= _timing.ClipWait - 1e-9) break;
                continue;
            }
            kept.AddRange(chunk);
            sounding += _timing.Slice;
        }
        _link.Audition(channel, ClipNote, 0);
        if (!finished) throw OrganizerError.Cancelled;
        Pause(_timing.Tail);
        kept.AddRange(_audio.Take());
        return kept.ToArray();
    }

    /// Chaque note est toujours coupée (vélocité 0), même après Échap.
    private float[] PlayTestNotes(int channel)
    {
        _audio.Reset();
        foreach (var note in TestNotes)
        {
            _link.Audition(channel, note, TestVelocity);
            var finished = Wait(_timing.TestNote);
            _link.Audition(channel, note, 0);
            if (!finished) throw OrganizerError.Cancelled;
        }
        Pause(_timing.Tail);
        return _audio.Take();
    }

    private void Pause(double seconds)
    {
        if (!Wait(seconds)) throw OrganizerError.Cancelled;
    }

    /// Attend par petites tranches ; faux si Échap a été pressé.
    private bool Wait(double seconds)
    {
        var steps = Math.Max(1, (int)Math.Ceiling(seconds / _timing.Slice));
        for (var i = 0; i < steps; i++)
        {
            if (_escape()) Cancel();
            if (IsCancelled) return false;
            _sleep(seconds / steps);
        }
        return !IsCancelled;
    }

    // ---------- Pur ----------

    /// Crête en dBFS (−180 pour un son vide).
    public static double PeakDB(IReadOnlyCollection<float> samples)
    {
        if (samples.Count == 0) return -180;
        float peak = 0;
        foreach (var v in samples) peak = Math.Max(peak, Math.Abs(v));
        return 20 * Math.Log10(Math.Max(peak, 1e-9));
    }

    /// Classement réel : mesures du son et l'IA intégrée (`ClasseurSons`, sans internet) qui reconnaît les voix et
    /// donne son avis quand les règles hésitent (à la place de l'IA de macOS, dans les mêmes règles). La règle dit ce
    /// que l'IA intégrée a entendu (« +iv » et sa probabilité de voix en %, un nombre seulement).
    public static Classify LiveClassifier(ClasseurSons? classeur, CorrectionsIA? corrections) => (samples, rate) =>
    {
        var features = SoundFeatures.Measure(samples, rate);
        var labels = AILabels.None;
        var avis = classeur?.Avis(samples, rate);
        if (avis is not null) labels.Merge(avis);
        var verdict = FamilyFusion.DecideWithRule(features, labels);
        // Un son déjà corrigé par l'utilisateur (le même, ou presque) : sa réponse, avant toute règle.
        if (verdict.Rule != "silence" && corrections?.Cherche(avis?.Empreinte) is { } corrige)
            verdict = (corrige.Famille, 1, "corrige");
        // Les règles hésitent (« à vérifier ») : l'avis de l'IA intégrée s'il est net.
        if (verdict.Family == SoundFamily.Unsure && verdict.Rule != "silence" && avis is not null
            && avis.Familles[(int)avis.Famille] >= 0.6)
            verdict = (ClasseurSons.Famille(avis.Famille), avis.Familles[(int)avis.Famille], "famille-iv");
        var rule = verdict.Rule + (labels.Heard ? "+ia" : "");
        if (avis is not null) rule += $"+iv{(int)Math.Round(avis.VoixMax * 100, MidpointRounding.AwayFromZero)}";
        return (verdict.Family, verdict.Confidence, rule);
    };

    private static readonly IReadOnlyDictionary<string, double> NoScores = new Dictionary<string, double>();

    /// Sorte d'après l'IA intégrée (le même classeur : le son n'est écouté qu'une fois), si elle l'emporte nettement ;
    /// celle d'une correction de l'utilisateur d'abord.
    public static NameKind LiveKindNamer(ClasseurSons? classeur, CorrectionsIA? corrections) => (samples, rate, family) =>
    {
        var avis = classeur?.Avis(samples, rate);
        return Corrigee(avis, family, corrections) ?? avis?.SorteNette(family);
    };

    /// Sorte des drums : celle d'une correction, puis ce que les mesures disent sûrement, l'IA intégrée, les mesures.
    public static NameDrum LiveDrumNamer(ClasseurSons? classeur, CorrectionsIA? corrections) => (samples, rate) =>
    {
        var avis = classeur?.Avis(samples, rate);
        if (Corrigee(avis, SoundFamily.Drums, corrections) is { } kind) return kind;
        return DrumNaming.Kind(SoundFeatures.Measure(samples, rate), NoScores, avis?.SorteNette(SoundFamily.Drums));
    };

    /// Sorte des mélodies : celle d'une correction, puis l'IA intégrée, les mesures.
    public static NameMelody LiveMelodyNamer(ClasseurSons? classeur, CorrectionsIA? corrections) => (samples, rate) =>
    {
        var avis = classeur?.Avis(samples, rate);
        if (Corrigee(avis, SoundFamily.Melody, corrections) is { } kind) return kind;
        return MelodyNaming.Kind(SoundFeatures.Measure(samples, rate), NoScores, avis?.SorteNette(SoundFamily.Melody));
    };

    /// La sorte qu'un utilisateur a donnée à ce son (le même, ou presque), si elle va avec la famille.
    private static SoundKind? Corrigee(ClasseurAvis? avis, SoundFamily family, CorrectionsIA? corrections)
    {
        if (corrections?.Cherche(avis?.Empreinte) is not { } corrige || corrige.Famille != family) return null;
        return corrige.Sorte;
    }

    /// Ce que l'IA intégrée retient d'un son écouté (même classeur : rien n'est réécouté) ; null sans ses mesures.
    public static Fingerprint LiveFingerprint(ClasseurSons? classeur) => (samples, rate) =>
    {
        if (classeur?.Avis(samples, rate) is not { } avis || avis.Empreinte is not { } empreinte) return null;
        var famille = ClasseurSons.Famille(avis.Famille);
        return new SoundPrint(avis.Mesures, empreinte, famille, avis.SorteNette(famille));
    };
}
