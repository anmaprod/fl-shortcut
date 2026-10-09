// Audit : SEC-05 (fichiers 0600, propriétaire vérifié), SEC-06 (aucun lien symbolique suivi, fichier temporaire
//         dans le même dossier puis rename(2) atomique), REL-02 (écriture atomique, erreurs remontées), REL-22.
import Darwin
import Foundation

/// Écriture et lecture de fichiers sans suivre de lien symbolique.
enum SecureFile {
    enum Failure: Error, LocalizedError, Equatable {
        case missing(String)
        case symlink(String)
        case notADirectory(String)
        case notARegularFile(String)
        case notOwned(String)
        case tooLarge(String)
        case posix(String, Int32)

        var errorDescription: String? {
            switch self {
            case .missing(let p): return "Introuvable : \(p)"
            case .symlink(let p): return "Refusé : \(p) est un lien symbolique."
            case .notADirectory(let p): return "Refusé : \(p) n'est pas un dossier."
            case .notARegularFile(let p): return "Refusé : \(p) n'est pas un fichier ordinaire."
            case .notOwned(let p): return "Refusé : \(p) n'appartient pas à ton compte."
            case .tooLarge(let p): return "Fichier trop volumineux : \(p)"
            case .posix(let what, let code): return "\(what) : \(String(cString: strerror(code)))"
            }
        }
    }

    enum Kind { case none, directory, regular, symlink, other }

    /// Type de l'élément lui-même (lstat : un lien n'est jamais suivi).
    static func kind(at path: String) -> Kind {
        var st = stat()
        guard lstat(path, &st) == 0 else { return .none }
        switch Int(st.st_mode) & Int(S_IFMT) {
        case Int(S_IFDIR): return .directory
        case Int(S_IFREG): return .regular
        case Int(S_IFLNK): return .symlink
        default: return .other
        }
    }

    /// Vérifie qu'un dossier est un vrai dossier (pas un lien) appartenant à l'utilisateur.
    static func checkDirectory(_ dir: URL) throws {
        let path = dir.path
        var st = stat()
        guard lstat(path, &st) == 0 else {
            let code = errno
            throw code == ENOENT ? Failure.missing(path) : Failure.posix("Accès refusé à \(path)", code)
        }
        let type = Int(st.st_mode) & Int(S_IFMT)
        if type == Int(S_IFLNK) { throw Failure.symlink(path) }
        guard type == Int(S_IFDIR) else { throw Failure.notADirectory(path) }
        guard st.st_uid == getuid() else { throw Failure.notOwned(path) }
    }

    /// Vrai si un composant du chemin est un lien symbolique.
    static func pathContainsSymlink(_ url: URL) -> Bool {
        var current = URL(fileURLWithPath: "/")
        for component in url.standardizedFileURL.pathComponents.dropFirst() {
            current.appendPathComponent(component)
            if kind(at: current.path) == .symlink { return true }
        }
        return false
    }

    /// Crée le dossier (0700) s'il manque, puis le vérifie.
    static func ensureDirectory(_ dir: URL) throws {
        if kind(at: dir.path) == .none {
            if mkdir(dir.path, 0o700) != 0 && errno != EEXIST {
                throw Failure.posix("mkdir \(dir.lastPathComponent)", errno)
            }
        }
        try checkDirectory(dir)
    }

    /// Écrit `data` de façon atomique : fichier temporaire (O_EXCL | O_NOFOLLOW) dans le même dossier, fsync,
    /// puis rename(2), qui remplace la cible sans jamais suivre un lien. La cible, si elle existe,
    /// doit être un fichier ordinaire.
    static func writeAtomically(_ data: Data, to url: URL, mode: mode_t = 0o600) throws {
        let dir = url.deletingLastPathComponent()
        try checkDirectory(dir)
        switch kind(at: url.path) {
        case .none, .regular: break
        case .symlink: throw Failure.symlink(url.path)
        default: throw Failure.notARegularFile(url.path)
        }

        let tmp = dir.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        let fd = open(tmp.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode)
        guard fd >= 0 else { throw Failure.posix("open", errno) }
        var renamed = false
        var closed = false
        defer {
            if !closed { close(fd) }
            if !renamed { unlink(tmp.path) }
        }

        try data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) in
            guard let base = buf.baseAddress, buf.count > 0 else { return }
            var offset = 0
            while offset < buf.count {
                let n = write(fd, base + offset, buf.count - offset)
                if n < 0 {
                    if errno == EINTR { continue }
                    throw Failure.posix("write", errno)
                }
                offset += n
            }
        }
        guard fchmod(fd, mode) == 0 else { throw Failure.posix("fchmod", errno) }
        guard fsync(fd) == 0 else { throw Failure.posix("fsync", errno) }
        closed = true
        guard close(fd) == 0 else { throw Failure.posix("close", errno) }
        guard rename(tmp.path, url.path) == 0 else { throw Failure.posix("rename", errno) }
        renamed = true
    }

    /// Lit un fichier ordinaire sans suivre de lien, taille bornée. `nil` s'il n'existe pas.
    static func read(_ url: URL, maxBytes: Int, requirePrivate: Bool = false) throws -> Data? {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        if fd < 0 {
            if errno == ENOENT { return nil }
            if errno == ELOOP { throw Failure.symlink(url.path) }
            throw Failure.posix("open", errno)
        }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        var st = stat()
        guard fstat(fd, &st) == 0 else { throw Failure.posix("fstat", errno) }
        guard Int(st.st_mode) & Int(S_IFMT) == Int(S_IFREG) else { throw Failure.notARegularFile(url.path) }
        guard Int(st.st_size) <= maxBytes else { throw Failure.tooLarge(url.path) }
        if requirePrivate {
            guard st.st_uid == getuid() else { throw Failure.notOwned(url.path) }
        }
        return try handle.readToEnd() ?? Data()
    }

    /// Droits d'un fichier existant (sans suivre de lien), pour vérifier le 0600.
    static func permissions(at path: String) -> (mode: Int, owner: uid_t)? {
        var st = stat()
        guard lstat(path, &st) == 0 else { return nil }
        return (Int(st.st_mode) & 0o777, st.st_uid)
    }
}
