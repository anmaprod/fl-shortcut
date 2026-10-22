// Cartes au lieu des feuilles (tâche 6 du plan des animations) : les fiches (raccourci, touche d'une action de FL,
// guide, modèles, Communauté) deviendront des cartes de verre qui sortent de la ligne cliquée et y retournent. Ici,
// la règle pure de la file : une seule carte à la fois ; une carte demandée pendant qu'une autre est ouverte la
// ferme d'abord ; demandée pendant une fermeture, elle attend la fin ; fermer est sans effet si rien n'est ouvert ;
// fenêtre fermée : tout est oublié. La présentation (voile, carte, vraie modale) reste à faire : voir
// docs/contexte/REPRISE-ANIMATIONS.md.
import Foundation

enum CardKind {
    case editRemap(Remap, isNew: Bool)
    case editCatalog(CatalogRow, notice: String?)
    case guide(page: Int)
    case templates
    case communityShare(Share)
    case communityCompose
    case communityReport(Share)
}

struct CardRequest: Identifiable {
    let id = UUID()
    let kind: CardKind
    /// Cadre de départ dans la couche de vol (ligne cliquée) ; nil : la carte sort du centre.
    let source: String?
}

struct CardQueue {
    private(set) var current: CardRequest?
    private(set) var closing = false
    private(set) var waiting: [CardRequest] = []

    /// Rien d'ouvert : la carte s'ouvre. Une carte ouverte : elle se ferme d'abord. Une fermeture en cours : attente.
    mutating func request(_ request: CardRequest) {
        if current == nil {
            current = request
            return
        }
        waiting.append(request)
        closing = true
    }

    /// Ferme la carte ouverte (sans effet si rien n'est ouvert ou si elle se ferme déjà).
    mutating func close() {
        guard current != nil else { return }
        closing = true
    }

    /// Fermeture finie : la carte suivante, s'il y en a une, s'ouvre. Sans effet si rien ne se fermait.
    mutating func closeFinished() {
        guard closing || current == nil else { return }
        closing = false
        current = waiting.isEmpty ? nil : waiting.removeFirst()
    }

    /// Fenêtre fermée pendant une carte : plus rien d'ouvert ni d'attendu.
    mutating func reset() {
        current = nil
        closing = false
        waiting = []
    }
}
