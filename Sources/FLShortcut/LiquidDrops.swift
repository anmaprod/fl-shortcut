// Gouttes de verre de la barre du bas du créateur : sans bloc choisi, la goutte « Ajouter » seule ; avec un bloc
// choisi, « Dupliquer » et « Supprimer » en sortent (ressort liquide, son « Tink ») et y rentrent (vif). Les boutons
// restent de vrais boutons (clic, ⌘D, VoiceOver) ; un bouton absent n'a plus de raccourci (rien à dupliquer).
// macOS 26 avec « Effet Liquid Glass » : fusion native du verre (GlassEffectContainer, glassEffectID) ; sinon (ou
// « Réduire la transparence ») des gouttes dessinées qui sortent de « Ajouter » en grandissant.
import SwiftUI

enum LiquidDrops {
    /// Fusion native du verre : macOS 26 avec « Effet Liquid Glass » et transparence non réduite ; sinon gouttes
    /// dessinées.
    static func useNativeGlass(available: Bool, glassEnabled: Bool, reduceTransparency: Bool) -> Bool {
        available && glassEnabled && !reduceTransparency
    }
}

/// Barre de gouttes : `add` toujours là ; `duplicate` et `delete` seulement si `showsExtra`.
struct LiquidDropsBar<Add: View, Duplicate: View, Delete: View>: View {
    let showsExtra: Bool
    @ViewBuilder let add: () -> Add
    @ViewBuilder let duplicate: () -> Duplicate
    @ViewBuilder let delete: () -> Delete
    @AppStorage(Appearance.glassKey) private var glassEnabled = true
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Namespace private var drops

    var body: some View {
        let native = LiquidDrops.useNativeGlass(available: Appearance.glassAvailable, glassEnabled: glassEnabled,
                                                reduceTransparency: reduceTransparency)
        bar(native: native)
            .motion(showsExtra ? Motion.spring(.liquide) : Motion.spring(.vif), value: showsExtra)
            .onChange(of: showsExtra) { if $0 { InterfaceSound.play(.dropDetach) } }
    }

    @ViewBuilder private func bar(native: Bool) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *), native {
            GlassEffectContainer(spacing: 20) {
                HStack(spacing: 10) {
                    add().dropPadding().glassEffect(.regular.interactive()).glassEffectID("ajouter", in: drops)
                    if showsExtra {
                        duplicate().dropPadding().glassEffect(.regular.interactive())
                            .glassEffectID("dupliquer", in: drops)
                        delete().dropPadding().glassEffect(.regular.interactive())
                            .glassEffectID("supprimer", in: drops)
                    }
                }
            }
        } else {
            drawn
        }
        #else
        drawn
        #endif
    }

    /// Gouttes dessinées : « Dupliquer » et « Supprimer » sortent de « Ajouter » (à sa gauche) en grandissant.
    private var drawn: some View {
        HStack(spacing: 10) {
            add().dropPadding().background(DropBackground())
            if showsExtra {
                duplicate().dropPadding().background(DropBackground()).transition(.dropOut)
                delete().dropPadding().background(DropBackground()).transition(.dropOut)
            }
        }
    }
}

private extension View {
    /// Marge d'une goutte autour de son libellé.
    func dropPadding() -> some View {
        padding(.horizontal, 10).frame(height: 26)
    }
}

/// Goutte dessinée (sans verre) : capsule légère au filet discret.
private struct DropBackground: View {
    var body: some View {
        Capsule(style: .continuous)
            .fill(Color.primary.opacity(0.07))
            .overlay(Capsule(style: .continuous).strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
    }
}

/// Goutte qui sort de la précédente : petite, floue et collée à sa gauche, puis à sa place.
private struct DropOut: ViewModifier {
    let amount: CGFloat

    func body(content: Content) -> some View {
        content
            .scaleEffect(0.3 + 0.7 * amount, anchor: .leading)
            .offset(x: -24 * (1 - amount))
            .blur(radius: 4 * (1 - amount))
            .opacity(amount)
    }
}

private extension AnyTransition {
    static var dropOut: AnyTransition {
        Motion.transition(.modifier(active: DropOut(amount: 0), identity: DropOut(amount: 1)))
    }
}
