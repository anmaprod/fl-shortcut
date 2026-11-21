// Communauté du 11/11, les écrans (maquette validée : artefact `1EFC8zLVn5ATRWAnQMBZrB`, planche « Communaute », écran
// B · Vitrine et page d'une personne) : onglets avec le point rouge, vitrine « Pour toi » (de tes abonnements,
// créateurs à suivre, les plus ajoutées), page d'une personne (← pseudo, Suivre / Abonné, photo et abonnés, son travail
// trié), bouton Suivre, étoiles de la fiche. Style suisse des trois thèmes ; rien d'autre affiché (« pas trop d'infos »).
// Windows : CommunityPage.cs, les mêmes écrans.
import SwiftUI

/// Onglets de la Communauté (maquette « plus lisible » du 16/11) : des mots en petites capitales, le choisi à l'encre et
/// souligné, les autres en gris ; « Abonnements » porte le point rouge.
struct CommunityTabs: View {
    @ObservedObject var community: CommunityStore

    /// Maquette « Minimal » (21/11, « Communauté, c'est pas le même ») : Les plus ajoutées, Abonnements, Les miens ;
    /// « Pour toi » seulement sans le serveur du 11/11 (les deux premiers en ont besoin).
    private var tabs: [CommunityTab] {
        community.social ? [.mostAdded, .following, .mine] : [.forYou, .mine]
    }

    private var current: CommunityTab? {
        community.isPersonPage || !community.search.trimmingCharacters(in: .whitespaces).isEmpty ? nil : community.tab
    }

    var body: some View {
        HStack(spacing: 24) {
            ForEach(tabs) { tab in
                let on = current == tab
                Button {
                    Task { await community.choose(tab) }
                } label: {
                    HStack(spacing: 7) {
                        Text(tab.title)
                            .font(Swiss.font(14, on ? .semibold : .regular))
                            .foregroundStyle(on ? Swiss.text : Swiss.gray)
                        if tab == .following, community.newFromFollowed > 0 {
                            Rectangle().fill(Swiss.red).frame(width: 6, height: 6)
                                .accessibilityLabel(String(localized: "Nouveautés"))
                        }
                    }
                    .frame(height: 34)
                    .overlay(alignment: .bottom) {
                        if on { Rectangle().fill(Swiss.text).frame(height: 2) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
            }
        }
        .fixedSize()
    }
}

/// Suivre / Abonné ✓ (un clic sur « Abonné » arrête de suivre). Jamais pour soi-même. 19/11 : « Abonné » a la même
/// couleur que « Suivre », et le même survol.
struct CommunityFollowButton: View {
    @ObservedObject var community: CommunityStore
    let id: UUID
    var small = true

    var body: some View {
        if id != community.session?.userID {
            if community.following.contains(id) {
                Button(String(localized: "Abonné ✓")) { Task { await community.unfollow(id) } }
                    .primaryButton()
                    .controlSize(small ? .small : .regular)
                    .help(String(localized: "Ne plus suivre"))
            } else {
                Button(String(localized: "Suivre")) { Task { await community.follow(id) } }
                    .primaryButton()
                    .controlSize(small ? .small : .regular)
                    .help(String(localized: "Voir ses nouveaux partages dans Abonnements"))
            }
        }
    }
}

/// Pseudo cliquable (mène à la page de la personne).
private struct AuthorLink: View {
    @ObservedObject var community: CommunityStore
    let id: UUID
    let name: String
    var size: CGFloat = 11
    var color: Color = Swiss.text

    var body: some View {
        Button {
            Task { await community.openPerson(CommunityMember(id: id, username: name, shareCount: 0)) }
        } label: {
            Text(verbatim: "@" + name.displaySafe(max: 24))
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(color)
                .lineLimit(1)
        }
        .buttonStyle(.plain)
        .help(String(localized: "Voir la page de @\(name.displaySafe(max: 24))"))
    }
}

/// Vitrine « Pour toi » : trois rangées, chacune avec « Tout voir » (sauf les créateurs), puis les nouveautés
/// (dessinées par la page). Une rangée vide n'est pas montrée.
struct CommunityShowcase: View {
    @ObservedObject var community: CommunityStore
    let open: (Share) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            if !community.followedPreview.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    header(String(localized: "De tes abonnements"), new: community.newFromFollowed, more: .following)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16, alignment: .top), count: 3),
                              spacing: 16) {
                        ForEach(Array(community.followedPreview.enumerated()), id: \.element.id) { index, share in
                            followedCard(share, new: index < community.newFromFollowed)
                        }
                    }
                }
            }
            if !community.creators.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    header(String(localized: "Créateurs à suivre"), more: nil)
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(community.creators) { creator in creatorTile(creator) }
                    }
                }
            }
            if !community.topPreview.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    header(String(localized: "Les plus ajoutées"), more: .mostAdded)
                    ForEach(Array(community.topPreview.enumerated()), id: \.element.id) { index, share in
                        topRow(share, rank: index + 1)
                    }
                }
            }
        }
    }

    private func header(_ title: String, new: Int = 0, more: CommunityTab?) -> some View {
        HStack(spacing: 10) {
            Text(title).swissLabel(Swiss.text)
            if new > 0 {
                Rectangle().fill(Swiss.red).frame(width: 7, height: 7)
                Text(new == 1 ? String(localized: "1 nouvelle") : String(localized: "\(new) nouvelles"))
                    .swissLabel(Swiss.red)
            }
            Spacer(minLength: 8)
            if let more {
                Button {
                    Task { await community.choose(more) }
                } label: {
                    Text("Tout voir →").swissLabel(Swiss.text).padding(.horizontal, 6).padding(.vertical, 3)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .menuHover(tint: Swiss.text, cornerRadius: 0)
            }
        }
        .padding(.bottom, 8)
        .swissRule(Swiss.line)
    }

    private func followedCard(_ share: Share, new: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                AvatarView(photo: community.photos[share.authorID], username: share.authorName, size: 16)
                AuthorLink(community: community, id: share.authorID, name: share.authorName)
                Spacer(minLength: 4)
                if new {
                    Rectangle().fill(Swiss.red).frame(width: 7, height: 7)
                        .accessibilityLabel(String(localized: "Nouveau"))
                }
            }
            Text(share.title.displaySafe(max: 80))
                .font(Swiss.title(19)).tracking(Swiss.titleTracking(19))
                .lineLimit(2, reservesSpace: true)
            Text(CommunityStats.line(share) ?? " ").swissLabel().lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Rectangle().fill(Swiss.background))
        .overlay(Rectangle().strokeBorder(Swiss.line, lineWidth: 1))
        .swissCard()
        .contentShape(Rectangle())
        .onTapGesture { open(share) }
        .accessibilityElement(children: .contain)
    }

    private func creatorTile(_ creator: CommunityCreator) -> some View {
        VStack(spacing: 8) {
            Button {
                Task { await community.openPerson(CommunityMember(id: creator.id, username: creator.username, shareCount: 0)) }
            } label: {
                AvatarView(photo: community.photos[creator.id], username: creator.username, size: 56)
            }
            .buttonStyle(.plain)
            AuthorLink(community: community, id: creator.id, name: creator.username, size: 13.5)
            Text(CommunityStats.followers(creator.followerCount))
                .font(.system(size: 12)).foregroundStyle(Swiss.gray).lineLimit(1)
            CommunityFollowButton(community: community, id: creator.id)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity)
        .background(Rectangle().fill(Swiss.background))
        .overlay(Rectangle().strokeBorder(Swiss.line, lineWidth: 1))
        .swissCard()
    }

    private func topRow(_ share: Share, rank: Int) -> some View {
        HStack(spacing: 18) {
            Text(String(format: "%02d", rank))
                .font(Swiss.title(28)).tracking(Swiss.titleTracking(28))
                .foregroundStyle(Swiss.gray)
                .frame(width: 44, alignment: .leading)
            Text(share.title.displaySafe(max: 60))
                .font(Swiss.title(18)).tracking(Swiss.titleTracking(18))
                .lineLimit(1)
            AuthorLink(community: community, id: share.authorID, name: share.authorName, size: 13, color: Swiss.gray)
            Spacer(minLength: 8)
            if let stats = CommunityStats.line(share) {
                Text(stats).swissLabel().lineLimit(1).fixedSize()
            }
            Button(String(localized: "Voir")) { open(share) }
                .secondaryButton()
                .controlSize(.small)
        }
        .frame(minHeight: 56)
        .swissRule(Swiss.faint)
    }
}

/// Page d'une personne : son pseudo est le titre de la fenêtre (à la place de « communauté. », avec la flèche pour
/// revenir : EditorView.pageHeader, 11/11) ; ici sa photo en grand, son nombre d'abonnés et Suivre / Abonné ;
/// « Son travail » et son tri. Rien d'autre (ni bio, ni date). Clic droit sur la photo : la signaler, ou la retirer
/// (administrateur).
struct CommunityPersonHeader: View {
    @ObservedObject var community: CommunityStore
    let author: CommunityMember

    private var photo: NSImage? { community.photos[author.id] }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 22) {
                AvatarView(photo: photo, username: author.username, size: 96)
                    .swissContextMenu {
                        guard photo != nil else { return [] }
                        var items: [RightClickMenu.Item?] = [
                            RightClickMenu.Item(title: String(localized: "Signaler la photo…"), action: report),
                        ]
                        if community.isAdmin {
                            items.append(RightClickMenu.Item(title: String(localized: "Retirer la photo"), destructive: true,
                                                             action: remove))
                        }
                        return items
                    }
                // 19/11 (« mieux valoriser les abonnés et les partages ») : les deux en grand, côte à côte.
                HStack(alignment: .top, spacing: 36) {
                    if community.social, let followers = community.personFollowers {
                        bigNumber(followers, followers == 1 ? String(localized: "Abonné") : String(localized: "Abonnés"))
                    }
                    bigNumber(community.shares.count,
                              community.shares.count == 1 ? String(localized: "Partage") : String(localized: "Partages"))
                }
                Spacer(minLength: 8)
                if community.social {
                    CommunityFollowButton(community: community, id: author.id, small: false)
                }
            }
            HStack(spacing: 12) {
                Text("Son travail").swissLabel(Swiss.text)
                Spacer(minLength: 8)
                if community.social {
                    HStack(spacing: -2) {
                        ForEach(PersonSort.allCases, id: \.self) { sort in sortBox(sort) }
                    }
                    .fixedSize()
                }
            }
            .padding(.bottom, 8)
            .swissRule(Swiss.line)
        }
    }

    private func bigNumber(_ value: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: CommunityStats.number(value))
                .font(Swiss.title(34)).tracking(Swiss.titleTracking(34))
                .monospacedDigit()
            Text(label).swissLabel()
        }
    }

    private func sortBox(_ sort: PersonSort) -> some View {
        let on = community.personSort == sort
        return Button {
            Task { await community.sortPerson(sort) }
        } label: {
            Text(sort.title)
                .font(Swiss.font(10.5)).tracking(1.2).textCase(.uppercase)
                .foregroundStyle(on ? Swiss.background : Swiss.text)
                .padding(.horizontal, 11)
                .frame(height: 30)
                .background(Rectangle().fill(on ? Swiss.text : Swiss.background))
                .overlay(Rectangle().strokeBorder(Swiss.text, lineWidth: 2))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    private func report() {
        guard Dialogs.confirm(String(localized: "Signaler la photo de @\(author.username.displaySafe(max: 24)) ?"),
                              "")
        else { return }
        Task { await community.reportPhoto(of: author) }
    }

    private func remove() {
        guard Dialogs.confirm(String(localized: "Retirer la photo de @\(author.username.displaySafe(max: 24)) ?"),
                              String(localized: "Elle disparaît pour tout le monde."))
        else { return }
        Task { await community.removePhoto(of: author) }
    }
}

/// « Ta note » en demi-étoiles, comme Letterboxd (19/11) : chaque moitié d'étoile se clique ; la note s'affiche dès le
/// survol, en rouge, avec son chiffre (« 3,5 ») ; un nouveau clic la change. `half` : 1 à 10 (0,5 à 5 étoiles).
struct CommunityStarsRow: View {
    let half: Int?
    let rate: (Int) -> Void
    @State private var hover: Int?

    var body: some View {
        let shown = hover ?? half ?? 0
        HStack(spacing: 14) {
            Text("Ta note").swissLabel(Swiss.text)
            HStack(spacing: 2) {
                ForEach(1...5, id: \.self) { i in
                    Image(systemName: shown >= i * 2 ? "star.fill" : shown == i * 2 - 1 ? "star.leadinghalf.filled" : "star")
                        .font(.system(size: 24))
                        .foregroundStyle(shown >= i * 2 - 1 ? Swiss.red : Swiss.gray)
                        .frame(width: 30, height: 30)
                        .overlay {
                            HStack(spacing: 0) {
                                halfTarget(i * 2 - 1)
                                halfTarget(i * 2)
                            }
                        }
                }
            }
            .onHover { inside in if !inside { hover = nil } }
            Text(verbatim: shown > 0 ? CommunityStats.rating(Double(shown) / 2, locale: .current) : "")
                .font(Swiss.font(20))
                .monospacedDigit()
                .frame(minWidth: 36, alignment: .leading)
            Spacer(minLength: 0)
        }
    }

    /// Une moitié d'étoile : survolée, la note s'affiche ; cliquée, elle est envoyée.
    private func halfTarget(_ n: Int) -> some View {
        let label = CommunityStats.rating(Double(n) / 2, locale: .current)
        return Rectangle()
            .fill(Color.clear)
            .contentShape(Rectangle())
            .onHover { inside in if inside { hover = n } }
            .onTapGesture { rate(n) }
            .help(String(localized: "\(label) sur 5"))
            .accessibilityElement()
            .accessibilityLabel(String(localized: "\(label) sur 5"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { rate(n) }
    }
}

/// La note et le nombre d'ajouts d'un partage, en grand (19/11, « les étoiles et le nombre d'utilisation… + gros ») :
/// « ★ 4,6 sur 5   312 ajouts », l'étoile en rouge, le mot en gris.
struct CommunityBigStats: View {
    let share: Share

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 20) {
            if let value = share.rating {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(verbatim: "★").font(.system(size: 20)).foregroundStyle(Swiss.red)
                    Text(verbatim: CommunityStats.rating(value)).font(Swiss.font(21, .semibold)).monospacedDigit()
                        .foregroundStyle(Swiss.text)
                    Text("sur 5").font(.system(size: 13)).foregroundStyle(Swiss.gray)
                }
            }
            if let adds = CommunityStats.adds(share) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(verbatim: adds.number).font(Swiss.font(21, .semibold)).monospacedDigit().foregroundStyle(Swiss.text)
                    Text(verbatim: adds.word).font(.system(size: 13)).foregroundStyle(Swiss.gray)
                }
            }
        }
        .lineLimit(1)
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}
