// Organiser : ce que l'IA intégrée apprend des corrections (demande du propriétaire : « si les gens sont pas heureux
// de leur résultat, l'IA peut apprendre selon ses erreurs »). Un son écouté puis corrigé (dans l'aperçu, ou avec
// « Pas content ? ») est gardé sur le Mac par son empreinte (des nombres, jamais le son ni son nom) avec la bonne
// réponse : un son presque identique est ensuite rangé pareil (règle « corrige », avant les autres). Avec l'accord
// de la personne, ses mesures partent aussi au serveur (table corrections_ia, supabase/corrections-ia.sql) pour le
// prochain apprentissage de l'IA de tout le monde (ia/corrections.py). Un son rangé d'après son nom (jamais écouté :
// pas d'empreinte) puis corrigé avec « Pas content ? » est gardé sur le Mac par son nom codé (jamais en clair, jamais
// envoyé) : un son de ce nom est ensuite rangé pareil (règle « corrige-nom »).
import Accelerate
import CryptoKit
import Foundation

/// Ce que l'IA intégrée a retenu d'un son écouté : ses mesures (1216 nombres par tranche, jamais le son), son
/// empreinte et son avis.
struct SoundPrint: Equatable {
    var mesures: [[Float]]
    var empreinte: [Float]
    var familleIA: SoundFamily
    var sorteIA: SoundKind?
}

/// Un son corrigé, gardé sur le Mac : son empreinte et la bonne réponse.
struct CorrectionIA: Codable, Equatable {
    var empreinte: [Float]
    var famille: SoundFamily
    var sorte: SoundKind?
    var date: Date
}

/// Un son rangé d'après son nom puis corrigé : son nom codé (empreinte SHA-256, jamais le nom) et la bonne réponse.
struct CorrectionNom: Codable, Equatable {
    var cle: String
    var famille: SoundFamily
    var sorte: SoundKind?
    var date: Date
}

final class CorrectionsIA {
    static let shared = CorrectionsIA()
    /// Ressemblance (cosinus des empreintes) à partir de laquelle c'est le même son (ou presque : le même sample
    /// réutilisé, coupé ou un peu traité).
    static let seuil: Float = 0.97
    /// Corrections gardées au plus (les plus anciennes partent).
    static let maximum = 500
    /// Tranches envoyées au plus par son (≈ 26 Ko par correction).
    static let tranchesEnvoyees = 8
    /// Clé de l'accord pour aider l'IA de tout le monde (absente : pas encore demandé).
    static let clePartage = "FLShortcuts.partageCorrectionsIA"

    private let url: URL
    private let urlNoms: URL
    private let defaults: UserDefaults
    private let verrou = NSLock()
    private var cache: [CorrectionIA]?
    private var cacheNoms: [CorrectionNom]?

    /// `noms` : le fichier des corrections par nom (par défaut à côté de `url`).
    init(url: URL = AppPaths.supportDirectory.appendingPathComponent("corrections-ia.json"), noms: URL? = nil,
         defaults: UserDefaults = .standard) {
        self.url = url
        self.urlNoms = noms ?? url.deletingLastPathComponent().appendingPathComponent("corrections-noms.json")
        self.defaults = defaults
    }

    /// Accord pour envoyer les corrections au serveur (nil : jamais demandé).
    var partage: Bool? {
        get { defaults.object(forKey: Self.clePartage) as? Bool }
        set { defaults.set(newValue, forKey: Self.clePartage) }
    }

    var nombre: Int {
        verrou.lock()
        defer { verrou.unlock() }
        return liste().count
    }

    /// La correction d'un son presque identique (la plus proche), s'il y en a une.
    func cherche(_ empreinte: [Float]?) -> CorrectionIA? {
        guard let empreinte else { return nil }
        verrou.lock()
        defer { verrou.unlock() }
        return Self.plusProche(empreinte, dans: liste())
    }

    /// Gardée sur le Mac ; un son déjà corrigé prend la nouvelle réponse.
    func ajoute(_ correction: CorrectionIA) {
        verrou.lock()
        defer { verrou.unlock() }
        var toutes = liste().filter { Self.ressemblance($0.empreinte, correction.empreinte) < Self.seuil }
        toutes.append(correction)
        if toutes.count > Self.maximum { toutes.removeFirst(toutes.count - Self.maximum) }
        cache = toutes
        if let data = try? JSONEncoder().encode(toutes) {
            try? SecureFile.ensureDirectory(url.deletingLastPathComponent())
            try? SecureFile.writeAtomically(data, to: url, mode: 0o600)
        }
    }

    /// La correction d'un son rangé d'après ce nom, s'il y en a une.
    func cherche(nom: String) -> CorrectionNom? {
        guard let cle = Self.cle(nom) else { return nil }
        verrou.lock()
        defer { verrou.unlock() }
        return listeNoms().last { $0.cle == cle }
    }

    /// Un son rangé d'après son nom, corrigé : gardé sur le Mac (son nom codé) ; le même nom prend la nouvelle
    /// réponse. Faux si le nom ne peut pas servir (vide, ou un nom que l'Organiser a donné : « Mélodie 3 »).
    @discardableResult
    func ajoute(nom: String, famille: SoundFamily, sorte: SoundKind?) -> Bool {
        guard let cle = Self.cle(nom), famille != .unsure else { return false }
        verrou.lock()
        defer { verrou.unlock() }
        var toutes = listeNoms().filter { $0.cle != cle }
        toutes.append(CorrectionNom(cle: cle, famille: famille, sorte: sorte, date: Date()))
        if toutes.count > Self.maximum { toutes.removeFirst(toutes.count - Self.maximum) }
        cacheNoms = toutes
        if let data = try? JSONEncoder().encode(toutes) {
            try? SecureFile.ensureDirectory(urlNoms.deletingLastPathComponent())
            try? SecureFile.writeAtomically(data, to: urlNoms, mode: 0o600)
        }
        return true
    }

    /// Pur (testé) : le nom codé (majuscules et espaces en trop ignorés) ; nil pour un nom vide ou donné par
    /// l'Organiser.
    static func cle(_ nom: String) -> String? {
        let propre = nom.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !propre.isEmpty, !SoundNames.isGenerated(nom) else { return nil }
        return SHA256.hash(data: Data(("fls-nom:" + propre).utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func listeNoms() -> [CorrectionNom] {
        if let cacheNoms { return cacheNoms }
        let lues = (try? SecureFile.read(urlNoms, maxBytes: 4 << 20)).flatMap { $0 }
            .flatMap { try? JSONDecoder().decode([CorrectionNom].self, from: $0) } ?? []
        cacheNoms = lues
        return lues
    }

    private func liste() -> [CorrectionIA] {
        if let cache { return cache }
        let lues = (try? SecureFile.read(url, maxBytes: 16 << 20)).flatMap { $0 }
            .flatMap { try? JSONDecoder().decode([CorrectionIA].self, from: $0) } ?? []
        cache = lues
        return lues
    }

    // MARK: Pur

    static func plusProche(_ empreinte: [Float], dans liste: [CorrectionIA]) -> CorrectionIA? {
        var meilleure: (CorrectionIA, Float)?
        for c in liste {
            let r = ressemblance(empreinte, c.empreinte)
            if r >= seuil, r > meilleure?.1 ?? -1 { meilleure = (c, r) }
        }
        return meilleure?.0
    }

    /// Cosinus de deux empreintes de longueur 1 (produit scalaire) ; 0 si leurs tailles diffèrent.
    static func ressemblance(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var r: Float = 0
        vDSP_dotpr(a, 1, b, 1, &r, vDSP_Length(a.count))
        return r
    }

    /// Famille de l'IA intégrée (ia/commun.py) pour une famille de l'Organiser ; nil pour « À vérifier ».
    static func nomIA(_ famille: SoundFamily) -> String? {
        switch famille {
        case .vocals: return "voix"
        case .melody: return "melodie"
        case .bass: return "basse"
        case .drums: return "drums"
        case .fx: return "fx"
        case .unsure: return nil
        }
    }

    /// Une correction à envoyer au serveur (table corrections_ia) : des nombres et des noms de familles et de sortes,
    /// jamais le son, son nom ni un texte tapé. nil si la bonne réponse n'apprend rien à l'IA (« À vérifier »).
    static func envoi(_ print: SoundPrint, avant: (SoundFamily, SoundKind?), apres: (SoundFamily, SoundKind?),
                      raisons: [String], appVersion: String) -> [String: Any]? {
        guard let famille = nomIA(apres.0), let familleIA = nomIA(print.familleIA),
              !print.mesures.isEmpty else { return nil }
        let tranches = Array(print.mesures.prefix(tranchesEnvoyees))
        guard tranches.allSatisfy({ $0.count == ClasseurSons.tailleMesures }) else { return nil }
        let apprise = { (k: SoundKind?) in k.flatMap { ClasseurSons.sortes.contains($0) ? $0.rawValue : nil } }
        var corps: [String: Any] = [
            "famille_ia": familleIA, "famille_avant": nomIA(avant.0) ?? "", "famille": famille,
            "mesures": demi(tranches.flatMap { $0 }).base64EncodedString(), "tranches": tranches.count,
            "raisons": raisons.joined(separator: ","), "modele": ClasseurSons.versionModele,
            "app_version": String(appVersion.prefix(20)),
        ]
        if let s = apprise(print.sorteIA) { corps["sorte_ia"] = s }
        if let s = apprise(avant.1) { corps["sorte_avant"] = s }
        if let s = apprise(apres.1) { corps["sorte"] = s }
        return corps
    }

    /// Nombres en 16 bits (IEEE 754, petit-boutiste) : deux fois moins lourds, assez précis pour apprendre.
    static func demi(_ valeurs: [Float]) -> Data {
        var sortie = [UInt16](repeating: 0, count: valeurs.count)
        guard !valeurs.isEmpty else { return Data() }
        var entree = valeurs
        entree.withUnsafeMutableBytes { e in
            sortie.withUnsafeMutableBytes { s in
                var src = vImage_Buffer(data: e.baseAddress, height: 1, width: vImagePixelCount(valeurs.count),
                                        rowBytes: valeurs.count * 4)
                var dst = vImage_Buffer(data: s.baseAddress, height: 1, width: vImagePixelCount(valeurs.count),
                                        rowBytes: valeurs.count * 2)
                _ = vImageConvert_PlanarFtoPlanar16F(&src, &dst, vImage_Flags(kvImageNoFlags))
            }
        }
        return sortie.withUnsafeBytes { Data($0) }
    }
}
