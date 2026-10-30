// Feuille « Modifier le profil » (maquette 5, page Mon compte et photo de la barre d'outils) : la photo dans un grand
// rond, réglée avant l'envoi (zoom, glisser pour la placer), « Choisir une photo… » et « Retirer » ; le pseudo vérifié
// au fil de la frappe. « Enregistrer » envoie le pseudo (s'il change) puis la photo, préparée sur ce Mac (256 × 256 en
// JPEG : ProfilePhoto). Rien n'est envoyé avant « Enregistrer ».
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct EditProfileSheet: View {
    @ObservedObject var community: CommunityStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var check = CommunityStore.NameCheck.empty
    /// Image choisie (pas encore envoyée), son zoom et sa position (-1 à 1 sur chaque axe).
    @State private var chosen: CGImage?
    @State private var zoom = 1.0
    @State private var offset = CGPoint.zero
    @State private var dragStart: CGPoint?
    /// « Retirer » : la photo du compte sera retirée à l'enregistrement.
    @State private var removed = false
    @State private var saving = false
    @State private var tried = false
    @State private var photoProblem: String?

    private static let circle: CGFloat = 128

    /// Le pseudo actuel dès l'ouverture (retour du 30/10 : « on ne peut pas enregistrer directement » après avoir
    /// changé la photo : le pseudo, posé après coup, restait « à vérifier » et « Enregistrer » restait grisé).
    init(community: CommunityStore) {
        self.community = community
        let current = community.session?.username ?? ""
        _name = State(initialValue: current)
        _check = State(initialValue: current.isEmpty ? .empty : .mine)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Modifier le profil").font(.system(size: 17, weight: .bold))
            VStack(spacing: 14) {
                photo
                zoomSlider
                HStack(spacing: 8) {
                    Button { choosePhoto() } label: {
                        Label("Choisir une photo…", systemImage: "photo")
                    }
                    .secondaryButton()
                    Button {
                        chosen = nil
                        removed = true
                        photoProblem = nil
                    } label: {
                        Text("Retirer").foregroundStyle(hasPhoto ? Color.red : Color.secondary)
                    }
                    .secondaryButton()
                    .disabled(!hasPhoto)
                    .help(String(localized: "Retirer ta photo : ton initiale de couleur la remplace"))
                }
                if let photoProblem {
                    Label(photoProblem, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity)
            AuthField(title: String(localized: "Pseudo"), text: $name, prompt: "malo.beats", prefix: "@") {
                UsernameStatus(check: check)
            }
            .modifier(UsernameChecker(community: community, name: name, check: $check))
            if case .invalid(let why) = check {
                Text(why).font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            } else if tried, let error = community.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Spacer()
                Button("Annuler") { dismiss() }
                    .secondaryButton()
                    .keyboardShortcut(.cancelAction)
                Button {
                    Task { await save() }
                } label: {
                    if saving {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Enregistrer")
                    }
                }
                .primaryButton()
                .keyboardShortcut(.defaultAction)
                .disabled(saving || !canSave)
            }
        }
        .padding(.horizontal, 26)
        .padding(.top, 24)
        .padding(.bottom, 22)
        .frame(width: 440)
        .onAppear { community.error = nil }
    }

    // MARK: Photo

    /// Il y a une photo à montrer : choisie, ou celle du compte (pas retirée).
    private var hasPhoto: Bool { chosen != nil || (!removed && community.myPhoto != nil) }

    /// Le grand rond : l'image choisie telle qu'elle sera envoyée (glisser pour la placer), sinon la photo du compte,
    /// sinon l'initiale.
    private var photo: some View {
        let size = Self.circle
        return Group {
            if let preview {
                Image(nsImage: preview).resizable().interpolation(.high).frame(width: size, height: size).clipShape(Circle())
            } else {
                AvatarView(photo: removed ? nil : community.myPhoto, username: name.isEmpty ? (community.session?.username ?? "") : name,
                           size: size)
            }
        }
        .overlay(Circle().strokeBorder(AuthLook.blue, lineWidth: 3).padding(-3))
        .padding(3)
        .contentShape(Circle())
        .gesture(DragGesture(minimumDistance: 1)
            .onChanged { drag(by: $0.translation) }
            .onEnded { _ in dragStart = nil })
        .onTapGesture(count: 2) { choosePhoto() }
        .help(chosen == nil ? String(localized: "Choisis une photo, puis glisse-la pour la placer")
              : String(localized: "Glisse la photo pour la placer"))
        .accessibilityLabel(String(localized: "Ta photo"))
    }

    /// Le carré visible de l'image choisie (celui qui sera envoyé).
    private var preview: NSImage? {
        guard let chosen else { return nil }
        let rect = ProfilePhoto.cropRect(width: chosen.width, height: chosen.height, zoom: zoom, offset: offset)
        guard let cropped = chosen.cropping(to: rect) else { return nil }
        return NSImage(cgImage: cropped, size: NSSize(width: Self.circle, height: Self.circle))
    }

    /// Glisser l'image vers la droite la montre plus à gauche : le carré visible part dans l'autre sens.
    private func drag(by translation: CGSize) {
        guard let chosen else { return }
        let start = dragStart ?? offset
        if dragStart == nil { dragStart = offset }
        let w = Double(chosen.width), h = Double(chosen.height)
        let visible = min(w, h) / zoom
        let pixelsPerPoint = visible / Double(Self.circle)
        func moved(_ from: CGFloat, _ by: CGFloat, margin: Double) -> CGFloat {
            guard margin > 0.5 else { return 0 }
            return CGFloat(min(max(Double(from) - Double(by) * pixelsPerPoint / margin, -1), 1))
        }
        offset = CGPoint(x: moved(start.x, translation.width, margin: (w - visible) / 2),
                         y: moved(start.y, translation.height, margin: (h - visible) / 2))
    }

    private var zoomSlider: some View {
        HStack(spacing: 10) {
            Image(systemName: "minus").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            Slider(value: $zoom, in: 1...3)
                .tint(AuthLook.blue)
                .frame(width: 194)
                .accessibilityLabel(String(localized: "Zoom de la photo"))
            Image(systemName: "plus").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
        }
        .disabled(chosen == nil)
        .opacity(chosen == nil ? 0.5 : 1)
        .help(chosen == nil ? String(localized: "Choisis une photo pour la recadrer") : String(localized: "Zoom de la photo"))
    }

    private func choosePhoto() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = String(localized: "Choisir")
        panel.message = String(localized: "Choisis ta photo de profil : tu pourras la recadrer avant de l'enregistrer.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let image = ProfilePhoto.load(url) else {
            photoProblem = String(localized: "Cette image ne se lit pas (ou elle est trop lourde) : choisis-en une autre.")
            return
        }
        chosen = image
        zoom = 1
        offset = .zero
        removed = false
        photoProblem = nil
    }

    // MARK: Enregistrer

    private var canSave: Bool {
        // Pseudo inchangé : rien à vérifier, la photo s'enregistre tout de suite.
        if let current = community.session?.username,
           name.trimmingCharacters(in: .whitespaces).lowercased() == current.lowercased() { return true }
        switch check {
        case .invalid, .taken, .checking, .empty: return false
        case .free, .mine, .unknown: return true
        }
    }

    private func save() async {
        tried = true
        photoProblem = nil
        let change: CommunityStore.PhotoChange
        if let chosen {
            guard let jpeg = ProfilePhoto.jpeg(from: chosen, zoom: zoom, offset: offset) else {
                photoProblem = String(localized: "Cette image ne se lit pas (ou elle est trop lourde) : choisis-en une autre.")
                return
            }
            change = .set(jpeg)
        } else if removed && community.myPhoto != nil {
            change = .remove
        } else {
            change = .keep
        }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if change == .keep, trimmed == community.session?.username {
            dismiss()
            return
        }
        saving = true
        defer { saving = false }
        if await community.saveProfile(username: trimmed, photo: change) {
            dismiss()
        }
    }
}
