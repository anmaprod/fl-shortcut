// Fenêtre de couleur copiée sur le « Color selector » de FL (vidéos de l'utilisateur) : la roue à 16 secteurs et
// 5 anneaux, le curseur de luminosité, les 10 cases 0 à 9 (ici les 10 dernières couleurs choisies dans FL Shortcuts),
// le champ « #RRGGBB », teinte / saturation / luminance (échelle de FL) et rouge / vert / bleu, Reset et Accept. Style
// suisse (02/11) ; les 10 récentes en haut, un clic sur l'une la pose.
// Ouverte seulement à la demande (bouton « Choisir… » du bloc Nom et couleur) : rien ne tourne au repos.
import SwiftUI

struct FLColorSelector: View {
    let initial: RGBColor
    let accept: (RGBColor) -> Void

    @State private var color: RGBColor
    @State private var hex: String
    @State private var recent: [RGBColor] = []

    init(initial: RGBColor, accept: @escaping (RGBColor) -> Void) {
        self.initial = initial
        self.accept = accept
        _color = State(initialValue: initial)
        _hex = State(initialValue: "#" + initial.hex)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Les 10 dernières couleurs, en haut (02/11, « comme dans FL… ils ont juste à cliquer sur la petite
            // couleur ») : un clic la pose tout de suite.
            slots
            HStack(alignment: .top, spacing: 12) {
                FLColorWheelView(selected: color) { set($0) }
                    .frame(width: 210, height: 210)
                LuminanceSlider(color: color) { set($0) }
                    .frame(width: 18, height: 210)
            }
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Rectangle()
                        .fill(swiftColor(color))
                        .frame(width: 84, height: 40)
                        .overlay(Rectangle().strokeBorder(Swiss.line, lineWidth: 1))
                    TextField("#RRGGBB", text: $hex)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .padding(.horizontal, 6)
                        .frame(width: 84, height: 22)
                        .overlay(Rectangle().strokeBorder(Swiss.line, lineWidth: 1))
                        .onSubmit { if let c = RGBColor(hex: hex) { set(c) } }
                        .help("Code de la couleur (#RRGGBB), comme dans FL")
                }
                Grid(alignment: .trailing, horizontalSpacing: 6, verticalSpacing: 4) {
                    let v = color.flHSL
                    GridRow {
                        Text("Hue").swissLabel(size: 9)
                        number(v.hue, 0...359) { var w = v; w.hue = $0; set(RGBColor(flHSL: w)) }
                        Text("Red").swissLabel(size: 9)
                        number(Int(color.r), 0...255) { set(RGBColor(r: UInt8($0), g: color.g, b: color.b)) }
                    }
                    GridRow {
                        Text("Sat").swissLabel(size: 9)
                        number(v.saturation, 0...240) { var w = v; w.saturation = $0; set(RGBColor(flHSL: w)) }
                        Text("Green").swissLabel(size: 9)
                        number(Int(color.g), 0...255) { set(RGBColor(r: color.r, g: UInt8($0), b: color.b)) }
                    }
                    GridRow {
                        Text("Lum").swissLabel(size: 9)
                        number(v.luminance, 0...240) { var w = v; w.luminance = $0; set(RGBColor(flHSL: w)) }
                        Text("Blue").swissLabel(size: 9)
                        number(Int(color.b), 0...255) { set(RGBColor(r: color.r, g: color.g, b: UInt8($0))) }
                    }
                }
            }
            HStack {
                Button("Reset") { set(initial) }
                    .secondaryButton()
                    .controlSize(.small)
                    .help("Revenir à la couleur de départ")
                Spacer()
                Button("Accept") { use(color) }
                    .primaryButton()
                    .controlSize(.small)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(width: 290)
        .background(Swiss.background)
        .onAppear { recent = RecentColors.list() }
    }

    /// Cases 0 à 9 : les 10 dernières couleurs posées (0 = la plus récente), comme les cases de FL. Une 11e prend la
    /// case 0 et la plus ancienne s'en va ; une couleur déjà là remonte en 0.
    private var slots: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Récentes").swissLabel(size: 9)
            HStack(spacing: 4) {
                ForEach(0..<RecentColors.limit, id: \.self) { slot($0) }
            }
        }
    }

    private func slot(_ i: Int) -> some View {
        let c: RGBColor? = i < recent.count ? recent[i] : nil
        let label: Color = c.map { $0.flHSL.luminance > 140 ? Color.black : Color.white } ?? Swiss.gray
        return Button {
            if let c { use(c) }
        } label: {
            ZStack(alignment: .bottomTrailing) {
                Rectangle().fill(c.map(swiftColor) ?? Swiss.background)
                Text("\(i)")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(label.opacity(0.8))
                    .padding(.trailing, 2)
            }
            .frame(width: 22, height: 22)
            .overlay(Rectangle()
                .strokeBorder(c != nil && c == color ? Swiss.text : Swiss.line, lineWidth: c != nil && c == color ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(c == nil)
        .help(c.map { String(localized: "#\($0.hex) : cliquer pour la poser") } ?? String(localized: "Case vide"))
    }

    private func number(_ value: Int, _ range: ClosedRange<Int>, _ set: @escaping (Int) -> Void) -> some View {
        TextField("", value: Binding(get: { value }, set: { set(min(max($0, range.lowerBound), range.upperBound)) }),
                  format: .number)
            .textFieldStyle(.plain)
            .multilineTextAlignment(.trailing)
            .font(.system(size: 11, design: .monospaced))
            .padding(.horizontal, 4)
            .frame(width: 40, height: 20)
            .overlay(Rectangle().strokeBorder(Swiss.line, lineWidth: 1))
    }

    /// La couleur est posée : retenue en tête des récentes (comme FL), puis rendue.
    private func use(_ c: RGBColor) {
        RecentColors.remember(c)
        accept(c)
    }

    private func set(_ c: RGBColor) {
        color = c
        hex = "#" + c.hex
    }
}

func swiftColor(_ c: RGBColor) -> Color {
    Color(red: Double(c.r) / 255, green: Double(c.g) / 255, blue: Double(c.b) / 255)
}

/// Dégradé recopié sur le « Gradient editor » de FL (vidéo de l'utilisateur) : cases First et Last (chacune ouvre la
/// fenêtre de couleur), aperçu du dégradé entre elles, puis ▶ (First devient aussi Last), ◀▶ (échange) et ◀ (Last
/// devient aussi First).
struct GradientField: View {
    let first: RGBColor
    let last: RGBColor
    let set: (RGBColor, RGBColor) -> Void
    @State private var pickingFirst = false
    @State private var pickingLast = false

    /// Last proposé au départ : la même couleur, plus sombre (comme le dégradé de la vidéo, du clair au foncé).
    static func defaultLast(for c: RGBColor) -> RGBColor { c.lerp(RGBColor(r: 0, g: 0, b: 0), 0.45) }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                box("First", first, picking: $pickingFirst) { set($0, last) }
                Rectangle()
                    .fill(LinearGradient(colors: [swiftColor(first), swiftColor(last)], startPoint: .leading, endPoint: .trailing))
                    .frame(height: 34)
                    .overlay(Rectangle().strokeBorder(Swiss.line, lineWidth: 1))
                    .accessibilityLabel("Aperçu du dégradé")
                box("Last", last, picking: $pickingLast) { set(first, $0) }
            }
            HStack {
                Button { set(first, first) } label: { Image(systemName: "arrowtriangle.right.fill") }
                    .help("First devient aussi Last")
                Spacer()
                Button { set(last, first) } label: { Image(systemName: "arrow.left.arrow.right") }
                    .help("Échanger First et Last")
                Spacer()
                Button { set(last, last) } label: { Image(systemName: "arrowtriangle.left.fill") }
                    .help("Last devient aussi First")
            }
            .buttonStyle(SwissChoiceStyle(chosen: false, uppercase: false))
            .controlSize(.small)
        }
    }

    private func box(_ title: String, _ c: RGBColor, picking: Binding<Bool>,
                     choose: @escaping (RGBColor) -> Void) -> some View {
        Button { picking.wrappedValue = true } label: {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(c.flHSL.luminance > 140 ? Color.black : Color.white)
                .frame(width: 44, height: 34)
                .background(Rectangle().fill(swiftColor(c)))
                .overlay(Rectangle().strokeBorder(Swiss.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help("\(title) : #\(c.hex) — cliquer pour choisir")
        .popover(isPresented: picking, arrowEdge: .leading) {
            FLColorSelector(initial: c) { picked in
                choose(picked)
                picking.wrappedValue = false
            }
        }
    }
}

/// La roue de FL, dessinée d'un seul tenant (Canvas) : un clic ou un glisser choisit la case sous la souris.
private struct FLColorWheelView: View {
    let selected: RGBColor
    let pick: (RGBColor) -> Void

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let radius = side / 2
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            Canvas { ctx, _ in
                draw(in: ctx, center: center, radius: radius)
            }
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                let dx = (g.location.x - center.x) / radius
                let dy = (g.location.y - center.y) / radius
                guard let cell = FLColorWheel.hit(dx: dx, dy: dy), cell.ring > 0 else { return }
                pick(FLColorWheel.color(ring: cell.ring, sector: cell.sector))
            })
        }
        .accessibilityLabel("Roue des couleurs de FL")
    }

    private func draw(in ctx: GraphicsContext, center: CGPoint, radius: CGFloat) {
        let step = 360.0 / Double(FLColorWheel.sectors)
        // La case choisie est entourée de blanc en dernier : tracée avec les autres, ses voisines recouvraient une partie
        // de son contour (01/11, « le blanc est gros d'un côté, petit de l'autre »).
        var chosen: Path?
        for ring in stride(from: FLColorWheel.edges.count - 1, through: 1, by: -1) {
            let outer = CGFloat(FLColorWheel.edges[ring]) * radius
            let inner = CGFloat(FLColorWheel.edges[ring - 1]) * radius
            for k in 0..<FLColorWheel.sectors {
                // 0° en haut, sens des aiguilles d'une montre (comme FL) ; les angles de Path partent de la droite.
                let start = Angle.degrees(Double(k) * step - step / 2 - 90)
                let end = Angle.degrees(Double(k) * step + step / 2 - 90)
                var p = Path()
                p.addArc(center: center, radius: outer, startAngle: start, endAngle: end, clockwise: false)
                p.addArc(center: center, radius: inner, startAngle: end, endAngle: start, clockwise: true)
                p.closeSubpath()
                let c = FLColorWheel.color(ring: ring, sector: k)
                ctx.fill(p, with: .color(swiftColor(c)))
                ctx.stroke(p, with: .color(.black.opacity(0.35)), lineWidth: 1)
                if c == selected { chosen = p }
            }
        }
        if let chosen { ctx.stroke(chosen, with: .color(.white), lineWidth: 2) }
        let r0 = CGFloat(FLColorWheel.edges[0]) * radius
        let disc = Path(ellipseIn: CGRect(x: center.x - r0, y: center.y - r0, width: 2 * r0, height: 2 * r0))
        ctx.fill(disc, with: .color(swiftColor(selected)))
        ctx.stroke(disc, with: .color(.black.opacity(0.35)), lineWidth: 1)
    }
}

/// Curseur vertical de luminosité : du blanc (en haut) au noir, en passant par la teinte choisie.
private struct LuminanceSlider: View {
    let color: RGBColor
    let set: (RGBColor) -> Void

    var body: some View {
        GeometryReader { geo in
            let v = color.flHSL
            let mid = RGBColor(flHSL: FLHSL(hue: v.hue, saturation: v.saturation, luminance: 120))
            let y = geo.size.height * CGFloat(1 - Double(v.luminance) / FLHSL.scale)
            ZStack(alignment: .top) {
                Rectangle()
                    .fill(LinearGradient(colors: [.white, swiftColor(mid), .black], startPoint: .top, endPoint: .bottom))
                    .overlay(Rectangle().strokeBorder(Swiss.line, lineWidth: 1))
                Rectangle()
                    .fill(swiftColor(color))
                    .overlay(Rectangle().strokeBorder(Swiss.text, lineWidth: 2))
                    .frame(width: 14, height: 14)
                    .offset(y: min(max(y - 7, 0), geo.size.height - 14))
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                let ratio = 1 - min(max(Double(g.location.y / geo.size.height), 0), 1)
                set(RGBColor(flHSL: FLHSL(hue: v.hue, saturation: v.saturation,
                                          luminance: Int((ratio * FLHSL.scale).rounded()))))
            })
        }
        .accessibilityLabel("Luminosité")
    }
}
