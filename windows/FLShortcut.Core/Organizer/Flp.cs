// Fichier de projet de FL Studio (.flp), lu et réécrit événement par événement, à l'octet près : l'Organiser y lit
// exactement ce que joue chaque pattern et où chaque clip est posé dans la Playlist, puis écrit une copie rangée (le
// fichier d'origine n'est jamais touché). Format : PROTOCOL.md §9. Pur (testé) : ni FL ni Windows.
// Miroir de Sources/FLShortcut/FLPFile.swift et FLPProject.swift (mêmes règles, mêmes arrêts).
using System.Text;

namespace FLShortcut.Core.Organizer;

/// Un événement du fichier : son numéro et ses octets (1, 2 ou 4 pour les numéros < 192, sinon de longueur libre).
/// Immuable : un changement fait un nouvel événement (la copie rangée ne touche jamais l'original).
public sealed record FlpEvent(byte Id, byte[] Bytes)
{
    /// Nombre d'octets d'un événement d'après son numéro ; null : longueur écrite devant (numéros 192 et plus).
    public static int? FixedSize(byte id) => id switch
    {
        < 64 => 1,
        < 128 => 2,
        < 192 => 4,
        _ => null,
    };

    /// Événement 172 de FL 2025 : un octet de forme, puis 4 octets (forme 0) ou 2 (forme 1). Il ne suit pas la règle
    /// des numéros 128 à 191 (vu dans le projet de test du propriétaire). Une autre forme arrête tout.
    public const byte Shaped = 172;

    /// Valeur d'un événement de 1, 2 ou 4 octets.
    public uint Value => FlpBytes.UInt(Bytes, 0, Bytes.Length);

    /// Texte d'un événement de texte : UTF-16 (petit-boutiste) terminé par un zéro.
    public string Text
    {
        get
        {
            var units = new List<char>();
            for (var i = 0; i + 1 < Bytes.Length; i += 2)
            {
                var unit = (char)(Bytes[i] | Bytes[i + 1] << 8);
                if (unit == 0) break;
                units.Add(unit);
            }
            return new string(units.ToArray());
        }
    }

    public FlpEvent With(byte[] bytes) => new(Id, bytes);

    public bool Equals(FlpEvent? other) => other is not null && Id == other.Id && Bytes.AsSpan().SequenceEqual(other.Bytes);
    public override int GetHashCode() => HashCode.Combine(Id, Bytes.Length);
}

public enum FlpErrorKind { NotProject, Damaged, Unsupported }

/// Pas un projet de FL, fichier coupé ou abîmé, ou forme que l'Organiser ne sait pas ranger sans risque (`What` :
/// raison pour le diagnostic, jamais un nom).
public sealed class FlpException : Exception
{
    public FlpErrorKind Kind { get; }
    public string What { get; }

    public FlpException(FlpErrorKind kind, string what = "") : base($"{kind} {what}".Trim())
    {
        Kind = kind;
        What = what;
    }

    public static FlpException Unsupported(string what) => new(FlpErrorKind.Unsupported, what);
    public static FlpException Damaged() => new(FlpErrorKind.Damaged);
}

/// Lecture et écriture des nombres du fichier (petit-boutistes).
public static class FlpBytes
{
    public static uint UInt(IReadOnlyList<byte> bytes, int offset, int size)
    {
        uint value = 0;
        for (var k = 0; k < size; k++) value |= (uint)bytes[offset + k] << (8 * k);
        return value;
    }

    public static void Put(uint value, byte[] bytes, int offset, int size)
    {
        for (var k = 0; k < size; k++) bytes[offset + k] = (byte)(value >> (8 * k));
    }

    public static byte[] Le(long value, int size)
    {
        var out_ = new byte[size];
        for (var k = 0; k < size; k++) out_[k] = (byte)(value >> (8 * k));
        return out_;
    }

    /// Longueur d'un événement de longueur libre : 7 bits par octet, le bit du haut dit qu'un octet suit.
    public static byte[] Varint(int value)
    {
        var out_ = new List<byte>();
        var rest = value;
        do
        {
            var b = (byte)(rest & 0x7F);
            rest >>= 7;
            if (rest > 0) b |= 0x80;
            out_.Add(b);
        } while (rest > 0);
        return out_.ToArray();
    }

    /// Texte d'un événement : UTF-16 petit-boutiste terminé par un zéro.
    public static byte[] Utf16Z(string text) => Encoding.Unicode.GetBytes(text).Concat(new byte[] { 0, 0 }).ToArray();
}

/// Le fichier entier : en-tête, puis la suite des événements.
public sealed class FlpFile
{
    public ushort Format { get; set; }
    public ushort ChannelCount { get; set; }
    /// Pas par noire (positions et longueurs de la Playlist et des notes).
    public ushort Ppq { get; set; }
    public List<FlpEvent> Events { get; set; }
    /// Ce qui suivrait l'en-tête ou les événements : gardé tel quel.
    public byte[] HeaderExtra { get; set; } = Array.Empty<byte>();
    public byte[] Trailer { get; set; } = Array.Empty<byte>();

    public FlpFile(ushort channelCount, ushort ppq, List<FlpEvent> events, ushort format = 0)
    {
        Format = format;
        ChannelCount = channelCount;
        Ppq = ppq;
        Events = events;
    }

    /// Une copie indépendante (les événements sont immuables : la liste suffit).
    public FlpFile Clone() => new(ChannelCount, Ppq, new List<FlpEvent>(Events), Format)
    {
        HeaderExtra = HeaderExtra,
        Trailer = Trailer,
    };

    public static FlpFile Read(string path) => Parse(File.ReadAllBytes(path));

    public static FlpFile Parse(byte[] bytes)
    {
        var reader = new Reader(bytes);
        if (bytes.Length < 4 || !reader.Take(4).AsSpan().SequenceEqual("FLhd"u8)) throw new FlpException(FlpErrorKind.NotProject);
        var headerSize = reader.Int(4);
        if (headerSize < 6) throw FlpException.Damaged();
        var format = (ushort)reader.Int(2);
        var channelCount = (ushort)reader.Int(2);
        var ppq = (ushort)reader.Int(2);
        var headerExtra = reader.Take(headerSize - 6);
        if (!reader.Take(4).AsSpan().SequenceEqual("FLdt"u8)) throw FlpException.Damaged();
        var size = reader.Int(4);
        if (size > bytes.Length - reader.Offset) throw FlpException.Damaged();
        var end = reader.Offset + size;
        var dataStart = reader.Offset;
        var events = new List<FlpEvent>();
        var starts = new HashSet<int>();
        var firstChannel = end;
        while (reader.Offset < end)
        {
            var start = reader.Offset;
            var id = reader.Byte();
            int length;
            if (id == FlpEvent.Shaped)
            {
                length = reader.Peek() switch
                {
                    0 => 5,
                    1 => 3,
                    _ => throw FlpException.Unsupported("événement 172"),
                };
            }
            else
            {
                length = FlpEvent.FixedSize(id) ?? reader.Varint();
            }
            if (length > end - reader.Offset) throw FlpException.Damaged();
            // Un canal : son numéro puis son type (21).
            if (firstChannel == end && id == 64 && reader.Offset + length < end && bytes[reader.Offset + length] == 21)
                firstChannel = start;
            starts.Add(start);
            events.Add(new FlpEvent(id, reader.Take(length)));
        }
        if (!NotesAligned(bytes, dataStart, firstChannel, starts)) throw FlpException.Unsupported("lecture");
        return new FlpFile(channelCount, ppq, events, format)
        {
            HeaderExtra = headerExtra,
            Trailer = bytes[end..],
        };
    }

    /// Les notes de chaque pattern (65, son numéro, puis 224 et des notes de 24 octets) sont écrites avant les
    /// canaux : chacune doit commencer là où la lecture a vu commencer un événement. Sinon un événement inconnu a
    /// décalé la lecture (des notes auraient disparu) : rien n'est deviné, tout s'arrête.
    public static bool NotesAligned(byte[] bytes, int from, int to, HashSet<int> starts)
    {
        var limit = Math.Min(to, bytes.Length);
        for (var p = Math.Max(from, 0); p + 5 < limit; p++)
        {
            if (bytes[p] != 65 || bytes[p + 3] != 224) continue;
            var pattern = bytes[p + 1] | bytes[p + 2] << 8;
            if (pattern < 1 || pattern > 999) continue;
            var size = 0;
            var q = p + 4;
            var ok = false;
            for (var shift = 0; shift <= 21 && q < bytes.Length; shift += 7)
            {
                var b = bytes[q];
                q++;
                size |= (b & 0x7F) << shift;
                if ((b & 0x80) == 0) { ok = true; break; }
            }
            if (!ok || size <= 0 || size % 24 != 0 || q + size > bytes.Length) continue;
            if (!starts.Contains(p)) return false;
        }
        return true;
    }

    public byte[] Encoded()
    {
        var data = new List<byte>();
        foreach (var e in Events)
        {
            data.Add(e.Id);
            if (FlpEvent.FixedSize(e.Id) is null) data.AddRange(FlpBytes.Varint(e.Bytes.Length));
            data.AddRange(e.Bytes);
        }
        var out_ = new List<byte>();
        out_.AddRange("FLhd"u8.ToArray());
        out_.AddRange(FlpBytes.Le(6 + HeaderExtra.Length, 4));
        out_.AddRange(FlpBytes.Le(Format, 2));
        out_.AddRange(FlpBytes.Le(ChannelCount, 2));
        out_.AddRange(FlpBytes.Le(Ppq, 2));
        out_.AddRange(HeaderExtra);
        out_.AddRange("FLdt"u8.ToArray());
        out_.AddRange(FlpBytes.Le(data.Count, 4));
        out_.AddRange(data);
        out_.AddRange(Trailer);
        return out_.ToArray();
    }

    private sealed class Reader
    {
        private readonly byte[] _bytes;
        public int Offset;

        public Reader(byte[] bytes) => _bytes = bytes;

        public byte Peek()
        {
            if (Offset >= _bytes.Length) throw FlpException.Damaged();
            return _bytes[Offset];
        }

        public byte Byte()
        {
            if (Offset >= _bytes.Length) throw FlpException.Damaged();
            return _bytes[Offset++];
        }

        public byte[] Take(int count)
        {
            if (count < 0 || count > _bytes.Length - Offset) throw FlpException.Damaged();
            var out_ = _bytes[Offset..(Offset + count)];
            Offset += count;
            return out_;
        }

        public int Int(int size) => (int)FlpBytes.UInt(Take(size), 0, size);

        /// Au plus 4 octets (assez pour 256 Mo) : au-delà, le fichier est abîmé.
        public int Varint()
        {
            var value = 0;
            for (var shift = 0; shift <= 21; shift += 7)
            {
                var b = Byte();
                value |= (b & 0x7F) << shift;
                if ((b & 0x80) == 0) return value;
            }
            throw FlpException.Damaged();
        }
    }
}
