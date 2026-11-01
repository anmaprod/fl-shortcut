// Écran Mixer de l'Organiser (maquette validée le 01/11, style suisse ; demandes du propriétaire : « faire comme dans
// FL », liens faciles et rapides, plusieurs sorties pour un son, familles en bandes qu'on glisse, double-clic pour le
// nom et la couleur, pistes sans son qu'on retire). Les pistes comme dans FL (le Master, puis le pré-master, puis les
// autres dans l'ordre où Organiser les rangera), les bandes des familles au-dessus. Un clic sur une piste la choisit :
// toute sa chaîne apparaît en rouge sous les pistes (808 → Drums Bus → Pré-master → Master), et la case sous chaque
// autre piste dit si elle y va ; un clic sur une case ajoute ou retire cette sortie. Tout passe par le plan
// (`MixerEdits`) : rien n'est envoyé à FL avant « Organiser ».
import SwiftUI

struct OrganizerMixerView: View {
    @ObservedObject var controller: OrganizerController
    /// Piste dont on change le nom et la couleur (double-clic), et le nom en cours de frappe.
    @State private var editing: Int?
    @State private var draft = ""
    /// Bande de famille prise et glissée (sa famille, son décalage).
    @State private var dragged: SoundFamily?
    @State private var dragOffset: CGFloat = 0

    static let stripWidth: CGFloat = 27
    static let masterWidth: CGFloat = 46
    static let premasterWidth: CGFloat = 36
    static let gap: CGFloat = 2
    static let stripHeight: CGFloat = 300

    /// Une piste à l'écran : sa piste d'origine (0 = le Master), sa place, son nom, sa couleur, sa famille.
    struct Strip: Identifiable {
        let id: Int
        let place: Int
        let name: String
        let color: Color
        let family: SoundFamily?
        let isBus: Bool
        let isPremaster: Bool
        let hasSound: Bool
        let width: CGFloat
        var isMaster: Bool { id == 0 }
    }

    /// Un saut de la chaîne de la piste choisie (pistes d'origine) et sa profondeur sous les pistes.
    struct Hop: Hashable {
        let from: Int
        let to: Int
        let level: Int
    }

    var body: some View {
        let plan = controller.plan
        let strips = Self.strips(controller: controller, plan: plan)
        let centers = Self.centers(strips)
        let width = (strips.map(\.width).reduce(0, +) + Self.gap * CGFloat(max(strips.count - 1, 0)))
        let selected = controller.mixerSelection.flatMap { id in strips.contains { $0.id == id } ? id : nil }
        let hops = selected.map { Self.chain(from: $0) { controller.destinations(of: $0, in: plan) } } ?? []
        let direct = selected.map { controller.destinations(of: $0, in: plan) } ?? []
        let depth = (hops.map(\.level).max() ?? -1) + 1
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.horizontal, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    bands(strips, centers: centers)
                        .frame(width: width, height: 22, alignment: .leading)
                        .padding(.bottom, 6)
                    HStack(spacing: Self.gap) {
                        ForEach(strips) { strip in
                            stripView(strip, selected: selected, direct: direct, plan: plan)
                        }
                    }
                    .frame(height: Self.stripHeight)
                    cables(hops, centers: centers)
                        .frame(width: width, height: 24 + CGFloat(max(depth, 1)) * 16)
                }
                .padding(.bottom, 6)
            }
            routing(selected: selected, direct: direct, strips: strips, plan: plan)
        }
    }

    // MARK: Pistes

    /// Pistes affichées : le Master, puis chaque piste dans l'ordre final (place 1 = piste 1).
    static func strips(controller: OrganizerController, plan: OrganizerPlan) -> [Strip] {
        guard let result = controller.result else { return [] }
        let mixer = plan.mixer
        let edits = controller.options.mixerEdits
        var byIndex: [Int: MixerTrackInfo] = [:]
        for track in result.mixer { byIndex[track.index] = track }
        let last = controller.mixerLast
        let order = mixer.final.isEmpty ? Array(1...max(last, 1)).filter { byIndex[$0] != nil } : mixer.final
        let sounds = controller.soundTracks(in: plan)
        var out = [Strip(id: 0, place: 0, name: "Master", color: Swiss.text, family: nil, isBus: false,
                         isPremaster: false, hasSound: false, width: masterWidth)]
        for (place, track) in order.enumerated() {
            let reset = mixer.resets.contains(track)
            let planned = mixer.names[track]
            // Le nom qu'aura la piste (vide : le nom de FL, « Insert 12 »).
            let name: String
            if reset {
                name = ""
            } else if let edited = edits.names[track] {
                name = edited
            } else if let planned {
                name = planned
            } else if byIndex[track]?.hasDefaultName ?? true {
                name = ""
            } else {
                name = byIndex[track]?.name ?? ""
            }
            let rgb = edits.colors[track] ?? mixer.colors[track] ?? byIndex[track]?.color
            let family = reset ? nil : mixer.verdicts[track]?.busFamily
            let isPre = mixer.premaster == track
            out.append(Strip(id: track, place: place + 1, name: name,
                             color: isPre ? Swiss.text : family == nil ? Swiss.line : (rgb.map(swiftColor) ?? Swiss.line),
                             family: family, isBus: mixer.buses[track] != nil, isPremaster: isPre,
                             hasSound: sounds.contains(track), width: isPre ? premasterWidth : stripWidth))
        }
        return out
    }

    /// Pur : le milieu de chaque piste (x), d'après les largeurs.
    static func centers(_ strips: [Strip]) -> [Int: CGFloat] {
        var x: CGFloat = 0
        var out: [Int: CGFloat] = [:]
        for strip in strips {
            out[strip.id] = x + strip.width / 2
            x += strip.width + gap
        }
        return out
    }

    /// Pur (testé) : toute la chaîne d'une piste jusqu'au Master, saut par saut (chaque sortie, puis les sorties de
    /// celles-ci…), chaque saut un peu plus bas que le précédent ; jamais deux fois la même piste (boucles).
    static func chain(from start: Int, destinations: (Int) -> [Int]) -> [Hop] {
        var hops: [Hop] = []
        var seen: Set<Int> = [start]
        var level = [start]
        var depth = 0
        while !level.isEmpty && depth < 8 {
            var next: [Int] = []
            for track in level where track != 0 {
                for dest in destinations(track).sorted(by: { ($0 == 0 ? 1 : 0, $0) < ($1 == 0 ? 1 : 0, $1) }) {
                    hops.append(Hop(from: track, to: dest, level: hops.count))
                    if !seen.contains(dest) {
                        seen.insert(dest)
                        next.append(dest)
                    }
                }
            }
            level = next
            depth += 1
        }
        return hops
    }

    /// Pur (testé) : le chemin principal d'une piste jusqu'au Master (à chaque piste, sa première sortie, le Master
    /// en dernier), pour la ligne « Routage ».
    static func path(from start: Int, destinations: (Int) -> [Int]) -> [Int] {
        var out = [start]
        var track = start
        while track != 0, out.count < 10 {
            guard let next = destinations(track).sorted(by: { ($0 == 0 ? 1 : 0, $0) < ($1 == 0 ? 1 : 0, $1) }).first,
                  !out.contains(next) else { break }
            out.append(next)
            track = next
        }
        return out
    }

    private func stripView(_ strip: Strip, selected: Int?, direct: [Int], plan: OrganizerPlan) -> some View {
        let isSelected = strip.id == selected
        let main = strip.isMaster || strip.isPremaster
        let empty = strip.name.isEmpty && !main
        let label = strip.isMaster ? "MASTER" : strip.isPremaster ? strip.name.uppercased() : strip.name
        return VStack(spacing: 0) {
            Text(verbatim: strip.isMaster ? "M" : "\(strip.place)")
                .font(Swiss.font(11).monospacedDigit())
                .foregroundStyle(isSelected ? Swiss.background : main ? Swiss.text : Swiss.gray)
                .frame(height: 24)
            Text(verbatim: String(label.prefix(26)))
                .font(.system(size: 11.5, weight: main || strip.isBus || isSelected ? .bold : .regular))
                .tracking(main ? 1.6 : 0)
                .foregroundStyle(isSelected ? Swiss.background : empty ? Color(white: 0.27) : Swiss.text)
                .lineLimit(1)
                .fixedSize()
                .rotationEffect(.degrees(-90))
                .frame(width: strip.width, height: Self.stripHeight - 24 - 34 - 3)
                // Choisie : blanche jusqu'au bord, sans la bande grise à gauche (01/11).
                .overlay(alignment: .leading) {
                    Rectangle().fill(isSelected ? Swiss.text : main ? Color.clear : Swiss.faint).frame(width: 1)
                }
            port(strip, selected: selected, direct: direct)
                .frame(width: strip.width, height: 34)
                .overlay(alignment: .top) {
                    Rectangle().fill(isSelected ? Swiss.text : Swiss.line).frame(height: 1)
                }
        }
        .frame(width: strip.width)
        .background(isSelected ? Swiss.text : strip.isMaster ? Color(white: 0.067) : strip.isPremaster ? Color(white: 0.04) : Swiss.background)
        .overlay(alignment: .top) { Rectangle().fill(strip.color).frame(height: 3) }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            guard !strip.isMaster else { return }
            draft = strip.name
            editing = strip.id
        }
        .onTapGesture {
            controller.mixerSelection = isSelected || strip.isMaster ? nil : strip.id
        }
        .popover(isPresented: Binding(get: { editing == strip.id }, set: { if !$0 { editing = nil } }),
                 arrowEdge: .bottom) {
            nameAndColor(strip)
        }
        .contextMenu {
            if !strip.isMaster {
                Button("Nom et couleur…") {
                    draft = strip.name
                    editing = strip.id
                }
                if controller.canRemove(strip.id, in: plan) {
                    Button("Retirer la piste (sans son)", role: .destructive) { controller.removeTrack(strip.id) }
                }
            }
        }
        .help(strip.isMaster ? String(localized: "Master")
              : String(localized: "Clic : voir où va cette piste, puis choisir ses sorties avec les cases. Double-clic : nom et couleur."))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(strip.isMaster ? "Master" : strip.name.isEmpty ? "Piste \(strip.place)" : strip.name)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// La case sous une piste : rouge plein (flèche) si la piste choisie y va, vide sinon ; un clic l'ajoute ou la
    /// retire. Rien sans piste choisie, ni sous la piste choisie elle-même.
    @ViewBuilder private func port(_ strip: Strip, selected: Int?, direct: [Int]) -> some View {
        if let selected, selected != strip.id {
            let on = direct.contains(strip.id)
            Button {
                controller.toggleRoute(from: selected, to: strip.id)
            } label: {
                ZStack {
                    Rectangle().fill(on ? Swiss.red : Color.clear)
                    Rectangle().strokeBorder(on ? Swiss.red : Color(white: 0.4), lineWidth: 1)
                    if on {
                        Image(systemName: "arrow.up").font(.system(size: 8, weight: .black)).foregroundStyle(Swiss.background)
                    }
                }
                .frame(width: 16, height: 16)
                .frame(width: strip.width, height: 34)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(on ? String(localized: "Ne plus envoyer dans cette piste") : String(localized: "Envoyer aussi dans cette piste"))
        } else {
            Color.clear
        }
    }

    // MARK: Chaîne et routage

    /// Un trait rouge par saut de la chaîne, chacun sur sa ligne, un peu plus bas que le précédent (01/11 : « qu'on voie
    /// toute la ligne », puis « un départ, et ça repart d'une autre ligne ») : dans chaque piste, le trait part d'un petit
    /// carré à droite et arrive par une flèche à gauche ; une piste qui reçoit et renvoie (un bus) a donc deux traits
    /// bien séparés.
    private func cables(_ hops: [Hop], centers: [Int: CGFloat]) -> some View {
        Canvas { ctx, _ in
            for hop in hops {
                guard let from = centers[hop.from], let to = centers[hop.to] else { continue }
                let a = from + Self.anchor, b = to - Self.anchor
                let y = 18 + CGFloat(hop.level) * 16
                var path = Path()
                path.move(to: CGPoint(x: a, y: 6))
                path.addLine(to: CGPoint(x: a, y: y))
                path.addLine(to: CGPoint(x: b, y: y))
                path.addLine(to: CGPoint(x: b, y: 6))
                ctx.stroke(path, with: .color(Swiss.red), lineWidth: 2)
                ctx.fill(Path(CGRect(x: a - 3, y: 0, width: 6, height: 6)), with: .color(Swiss.red))
                var head = Path()
                head.move(to: CGPoint(x: b - 5, y: 8))
                head.addLine(to: CGPoint(x: b, y: 1))
                head.addLine(to: CGPoint(x: b + 5, y: 8))
                head.closeSubpath()
                ctx.fill(head, with: .color(Swiss.red))
            }
        }
        .accessibilityHidden(true)
    }

    /// Écart du départ (à droite) et de l'arrivée (à gauche) par rapport au milieu de la piste.
    static let anchor: CGFloat = 5

    /// « ROUTAGE » : le chemin de la piste choisie jusqu'au Master (808 → Drums Bus → Pré-master → Master) et le nombre
    /// de ses sorties ; sans piste choisie, la consigne.
    private func routing(selected: Int?, direct: [Int], strips: [Strip], plan: OrganizerPlan) -> some View {
        let names = Dictionary(uniqueKeysWithValues: strips.map { ($0.id, $0) })
        func name(_ id: Int) -> String {
            guard let s = names[id] else { return String(localized: "Piste \(id)") }
            return s.isMaster ? "Master" : s.name.isEmpty ? String(localized: "Piste \(s.place)") : s.name
        }
        let path = selected.map { Self.path(from: $0) { controller.destinations(of: $0, in: plan) } } ?? []
        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("Routage").swissLabel().frame(width: 76, alignment: .leading)
            if path.isEmpty {
                Text("Clique une piste pour voir où elle va.")
                    .font(.system(size: 13))
                    .foregroundStyle(Swiss.gray)
            } else {
                path.enumerated().reduce(Text(verbatim: "")) { text, item in
                    text + (item.offset > 0 ? Text(verbatim: "  →  ").foregroundColor(Swiss.red) : Text(verbatim: ""))
                        + Text(verbatim: name(item.element))
                }
                .font(Swiss.font(20))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            }
            Spacer(minLength: 8)
            if !direct.isEmpty {
                Text(direct.count == 1 ? String(localized: "1 sortie") : String(localized: "\(direct.count) sorties"))
                    .swissLabel()
            }
        }
        .padding(.vertical, 12)
        .swissRule(Swiss.text, edge: .top)
        .swissRule(Swiss.line)
    }

    // MARK: Familles

    /// Les bandes des familles au-dessus de leurs pistes (poignée à six points, nom) ; une bande se prend et se glisse
    /// sur une autre : la famille prend sa place (Channel rack, Mixer et Playlist suivent).
    private func bands(_ strips: [Strip], centers: [Int: CGFloat]) -> some View {
        let runs = Self.runs(strips)
        return ZStack(alignment: .topLeading) {
            ForEach(runs, id: \.family) { run in
                let color = swiftColor(controller.style(of: run.family).color)
                HStack(spacing: 4) {
                    SixDots(color: Swiss.background.opacity(0.7))
                    Text(run.family.label)
                        .font(Swiss.font(9.5))
                        .tracking(0.8)
                        .textCase(.uppercase)
                        .foregroundStyle(Swiss.background)
                        .lineLimit(1)
                }
                .padding(.horizontal, 5)
                .frame(width: run.width, height: 22, alignment: .leading)
                .background(Rectangle().fill(color))
                .clipped()
                .offset(x: run.x + (dragged == run.family ? dragOffset : 0))
                .zIndex(dragged == run.family ? 1 : 0)
                .opacity(dragged != nil && dragged != run.family ? 0.75 : 1)
                .gesture(DragGesture(minimumDistance: 3)
                    .onChanged { value in
                        dragged = run.family
                        dragOffset = value.translation.width
                    }
                    .onEnded { value in
                        let drop = run.x + run.width / 2 + value.translation.width
                        if let target = runs.first(where: { drop >= $0.x && drop <= $0.x + $0.width }),
                           target.family != run.family {
                            withAnimation(Motion.quickMorph) { controller.moveFamily(run.family, onto: target.family) }
                        }
                        dragged = nil
                        dragOffset = 0
                    })
                .help(String(localized: "Reste appuyé et glisse la famille sur une autre : elle prend sa place"))
            }
        }
    }

    struct Run {
        let family: SoundFamily
        let x: CGFloat
        let width: CGFloat
    }

    /// Pur : les pistes qui se suivent d'une même famille, en bandes (x et largeur).
    static func runs(_ strips: [Strip]) -> [Run] {
        var out: [Run] = []
        var x: CGFloat = 0
        var current: (family: SoundFamily, x: CGFloat, width: CGFloat)?
        for strip in strips {
            if let family = strip.family, !strip.isPremaster {
                if let c = current, c.family == family {
                    current = (family, c.x, x + strip.width - c.x)
                } else {
                    if let c = current { out.append(Run(family: c.family, x: c.x, width: c.width)) }
                    current = (family, x, strip.width)
                }
            } else if let c = current {
                out.append(Run(family: c.family, x: c.x, width: c.width))
                current = nil
            }
            x += strip.width + gap
        }
        if let c = current { out.append(Run(family: c.family, x: c.x, width: c.width)) }
        // Une famille coupée en deux (une piste choisie à la main ailleurs) : une seule bande, la plus large.
        var best: [SoundFamily: Run] = [:]
        for run in out where (best[run.family]?.width ?? 0) < run.width { best[run.family] = run }
        return out.filter { best[$0.family]?.x == $0.x }
    }

    // MARK: Nom et couleur

    private func nameAndColor(_ strip: Strip) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(verbatim: String(localized: "Piste \(strip.place)")).swissLabel()
                Spacer()
                Text("Nom et couleur").swissLabel()
            }
            .padding(.bottom, 6)
            .swissRule()
            TextField("Nom", text: $draft)
                .textFieldStyle(.plain)
                .font(Swiss.font(22))
                .padding(.bottom, 6)
                .swissRule()
                .onSubmit { commit(strip) }
            FLColorSelector(initial: controller.options.mixerEdits.colors[strip.id]
                            ?? controller.plan.mixer.colors[strip.id]
                            ?? controller.result?.mixer.first { $0.index == strip.id }?.color
                            ?? RGBColor(r: 90, g: 90, b: 90)) { picked in
                controller.recolorTrack(strip.id, picked)
            }
            HStack(spacing: 0) {
                Spacer()
                Button("Annuler") { editing = nil }
                    .secondaryButton()
                    .keyboardShortcut(.cancelAction)
                Button("OK") { commit(strip) }
                    .primaryButton()
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 6)
            .swissRule(Swiss.line, edge: .top)
        }
        .padding(18)
        .frame(width: 380)
        .background(Swiss.background)
    }

    private func commit(_ strip: Strip) {
        if draft != strip.name { controller.renameTrack(strip.id, draft) }
        editing = nil
    }
}
