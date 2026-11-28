// Barre des familles en haut de l'aperçu de l'Organiser. (L'écran Mixer de l'aperçu, qui était dans ce fichier, est
// retiré le 02/11 à la demande du propriétaire : « on enlève le mixeur dans Organiser… tout ce qu'on fait, on peut le
// faire dans FL » ; il reste dans l'historique git, commit 99ed40d et avant.)
import SwiftUI

/// En haut de l'aperçu, d'un coup d'œil (barre empilée façon graphiques de BKLIT UI, en style suisse) : combien de sons
/// l'Organiser a trouvés dans chaque famille, dans l'ordre choisi, chaque famille de sa couleur ; elle suit les
/// changements (famille glissée, son changé de famille).
struct OrganizerFamilyBar: View {
    @ObservedObject var controller: OrganizerController

    var body: some View {
        let families = controller.presentFamilies
        let counts = families.map { controller.members(of: $0).count }
        let total = max(counts.reduce(0, +), 1)
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let room = max(0, geo.size.width - CGFloat(max(families.count - 1, 0)) * 2)
                HStack(spacing: 2) {
                    ForEach(Array(families.enumerated()), id: \.element) { index, family in
                        Rectangle()
                            .fill(swiftColor(controller.style(of: family).color))
                            .frame(width: max(2, room * CGFloat(counts[index]) / CGFloat(total)))
                    }
                }
            }
            .frame(height: 6)
            .animation(.easeOut(duration: 0.35), value: counts)
            HStack(spacing: 14) {
                ForEach(Array(families.enumerated()), id: \.element) { index, family in
                    HStack(spacing: 5) {
                        Text(family.label).swissLabel(size: 10)
                        Text(verbatim: "\(counts[index])").swissLabel(Swiss.text, size: 10)
                    }
                    .fixedSize()
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
