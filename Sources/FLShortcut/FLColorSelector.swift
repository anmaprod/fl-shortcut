// Fenêtre de couleur copiée sur le « Color selector » de FL (vidéos de l'utilisateur) : la roue à 16 secteurs et
// 5 anneaux, le curseur de luminosité, les 10 cases 0 à 9 (ici les 10 dernières couleurs choisies dans FL Shortcuts),
// le champ « #RRGGBB », teinte / saturation / luminance (échelle de FL) et rouge / vert / bleu, Reset et Accept.
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
            HStack(alignment: .top, spacing: 12) {
                FLColorWheelView(selected: color) { set($0) }
                    .frame(width: 210, height: 210)
                LuminanceSlider(color: color) { set($0) }
                    .frame(width: 18, height: 210)
            }
            HStack(spacing: 6) {
                TextField("#RRGGBB", text: $hex)
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 96)
                    .onSubmit { if let c = RGBColor(hex: hex) { set(c) } }
                    .help("Code de la couleur (#RRGGBB), comme dans FL")
                Spacer()
            }
            slots
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 4) {
                    Text("#" + color.hex).font(.system(size: 11, design: .monospaced))
                }
                .frame(width: 84, height: 66)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(swiftColor(color)))
                .foregroundStyle(color.flHSL.luminance > 140 ? Color.black : Color.white)
                Grid(alignment: .trailing, horizontalSpacing: 6, verticalSpacing: 4) {
                    let v = color.flHSL
                    GridRow {
                        Text("Hue").font(.system(size: 11)).foregroundStyle(.secondary)
                        number(v.hue, 0...359) { var w = v; w.hue = $0; set(RGBColor(flHSL: w)) }
                        Text("Red").font(.system(size: 11)).foregroundStyle(.secondary)
                        number(Int(color.r), 0...255) { set(RGBColor(r: UInt8($0), g: color.g, b: color.b)) }
                    }
                    GridRow {
                        Text("Saturation").font(.system(size: 11)).foregroundStyle(.secondary)
                        number(v.saturation, 0...240) { var w = v; w.saturation = $0; set(RGBColor(flHSL: w)) }
                        Text("Green").font(.system(size: 11)).foregroundStyle(.secondary)
                        number(Int(color.g), 0...255) { set(RGBColor(r: color.r, g: UInt8($0), b: color.b)) }
                    }
                    GridRow {
                        Text("Luminance").font(.system(size: 11)).foregroundStyle(.secondary)
                        number(v.luminance, 0...240) { var w = v; w.luminance = $0; set(RGBColor(flHSL: w)) }
                        Text("Blue").font(.system(size: 11)).foregroundStyle(.secondary)
                        number(Int(color.b), 0...255) { set(RGBColor(r: color.r, g: color.g, b: UInt8($0))) }
                    }
                }
            }
            HStack {
                Button("Reset") { set(initial) }
                    .help("Revenir à la couleur de départ")
                Spacer()
                Button("Accept") {
                    RecentColors.remember(color)
                    accept(color)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(width: 290)
        .onAppear { recent = RecentColors.list() }
    }

    /// Cases 0 à 9 : les 10 dernières couleurs choisies (0 = la plus récente), comme les cases de FL.
    private var slots: some View {
        VStack(spacing: 4) {
            ForEach(0..<2, id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(0..<5, id: \.self) { col in
                        slot(row * 5 + col)
                    }
                }
            }
        }
    }

    private func slot(_ i: Int) -> some View {
        let c: RGBColor? = i < recent.count ? recent[i] : nil
        let label: Color = c.map { $0.flHSL.luminance > 140 ? Color.black : Color.white } ?? Color.secondary
        return Button {
            if let c { set(c) }
        } label: {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(c.map(swiftColor) ?? Color.primary.opacity(0.08))
                Text("\(i)")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(label)
                    .padding(.trailing, 3)
            }
            .frame(height: 18)
            .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous)
                .strokeBorder(c == color ? Color.accentColor : Color.primary.opacity(0.15), lineWidth: c == color ? 2 : 1))
        }
        .buttonStyle(.plain)
        .disabled(c == nil)
        .help(c.map { "#" + $0.hex } ?? "Case vide")
    }

    private func number(_ value: Int, _ range: ClosedRange<Int>, _ set: @escaping (Int) -> Void) -> some View {
        TextField("", value: Binding(get: { value }, set: { set(min(max($0, range.lowerBound), range.upperBound)) }),
                  format: .number)
            .multilineTextAlignment(.trailing)
            .font(.system(size: 12, design: .monospaced))
            .frame(width: 42)
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
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(LinearGradient(colors: [swiftColor(first), swiftColor(last)], startPoint: .leading, endPoint: .trailing))
                    .frame(height: 34)
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.primary.opacity(0.15)))
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
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(swiftColor(c)))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.primary.opacity(0.15)))
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
                if c == selected { ctx.stroke(p, with: .color(.white), lineWidth: 2) }
            }
        }
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
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(LinearGradient(colors: [.white, swiftColor(mid), .black], startPoint: .top, endPoint: .bottom))
                Circle()
                    .strokeBorder(Color.white, lineWidth: 2)
                    .background(Circle().fill(swiftColor(color)))
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
