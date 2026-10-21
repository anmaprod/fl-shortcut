// Reprise : après « Quitter et rouvrir » (proposé par macOS une fois une autorisation donnée) ou une relance juste
// après avoir quitté, l'app revient là où on en était (accueil et son écran, panneau des autorisations, fenêtre
// principale et sa page, macro ouverte dans le créateur, Organiser), pas seulement l'icône (demande du propriétaire).
// Noté à la fermeture (des identifiants seulement, jamais un nom), repris au lancement s'il date de moins de
// 2 minutes : un démarrage du Mac le lendemain n'ouvre rien de lui-même. Lu une seule fois, puis effacé.
import AppKit
import Foundation

/// Ce qui était ouvert au moment de quitter.
struct ResumeState: Codable, Equatable {
    /// Écran de l'accueil ouvert (nil : accueil fermé).
    var onboarding: String?
    var guidePage = 0
    /// Panneau « Autoriser FL Shortcuts » affiché.
    var permissions = false
    /// Fenêtre principale ouverte, sur cette page (SidebarItem.resumeKey).
    var editor = false
    var page: String?
    /// Macro ouverte dans le créateur ; `macroIsNew` : créée à l'instant (au retour, l'enregistrer ou la supprimer).
    var macro: UUID?
    var macroIsNew = false
    var organizer = false
    var savedAt = Date()

    /// Au-delà, la relance n'est plus une reprise (Mac redémarré, app relancée plus tard).
    static let maxAge: TimeInterval = 120

    /// Rien à rouvrir : seule l'icône de la barre des menus était là.
    var isEmpty: Bool { onboarding == nil && !permissions && !editor && !organizer }

    /// Pur (testé) : l'état à reprendre au lancement, s'il est récent et s'il y a quelque chose à rouvrir.
    static func pending(_ state: ResumeState?, now: Date) -> ResumeState? {
        guard let state, !state.isEmpty else { return nil }
        let age = now.timeIntervalSince(state.savedAt)
        return age >= 0 && age <= maxAge ? state : nil
    }
}

final class AppResume {
    static let shared = AppResume()
    static let key = "resumeState"

    // Tenu à jour par les fenêtres pendant qu'elles sont ouvertes.
    weak var editorWindow: NSWindow?
    var page: SidebarItem?
    weak var creator: MacroEditorModel?
    var onboardingStage: String?
    var guidePage = 0

    /// Repris au lancement ; la fenêtre principale et l'accueil y prennent leur part une seule fois.
    private(set) var pending: ResumeState?

    /// Au lancement : l'état noté à la dernière fermeture, s'il est récent. Effacé aussitôt (repris une seule fois).
    @discardableResult
    func load(_ defaults: UserDefaults = .standard, now: Date = Date()) -> ResumeState? {
        let saved = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(ResumeState.self, from: $0) }
        defaults.removeObject(forKey: Self.key)
        pending = ResumeState.pending(saved, now: now)
        return pending
    }

    /// Écran de l'accueil à rouvrir (lu une fois, par la vue de l'accueil).
    func takeOnboarding() -> (stage: String, guidePage: Int)? {
        guard let stage = pending?.onboarding else { return nil }
        pending?.onboarding = nil
        return (stage, pending?.guidePage ?? 0)
    }

    /// Page et macro à rouvrir dans la fenêtre principale (lues une fois, à son apparition).
    func takeEditor() -> (page: SidebarItem?, macro: UUID?, isNew: Bool)? {
        guard let p = pending, p.editor else { return nil }
        pending?.editor = false
        return (p.page.flatMap(SidebarItem.init(resumeKey:)), p.macro, p.macroIsNew)
    }

    /// À la fermeture de l'app : la macro en cours est enregistrée, puis ce qui est ouvert est noté.
    func saveOnQuit(_ defaults: UserDefaults = .standard, permissions: Bool, organizer: Bool, now: Date = Date()) {
        creator?.saveNow()
        var state = ResumeState()
        state.onboarding = onboardingStage
        state.guidePage = guidePage
        state.permissions = permissions
        let editorOpen = editorWindow.map { $0.isVisible || $0.isMiniaturized } ?? false
        state.editor = editorOpen
        if editorOpen {
            state.page = page?.resumeKey
            if let creator, !creator.ephemeral, let id = creator.draft?.id {
                state.macro = id
                state.macroIsNew = creator.isNewMacro
            }
        }
        state.organizer = organizer
        state.savedAt = now
        if state.isEmpty {
            defaults.removeObject(forKey: Self.key)
        } else if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
