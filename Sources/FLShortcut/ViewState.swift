// État local d'une vue, sans la macro `@ViewState`.
// Sur macOS 27, `@ViewState` est une macro dont l'implémentation (SwiftUIMacros) n'est livrée qu'avec Xcode :
// les outils en ligne de commande seuls ne peuvent pas la développer. `@ViewState` fait la même chose
// (valeur propre à la vue, conservée entre deux rendus, `$valeur` pour un Binding) en s'appuyant sur
// `StateObject`, qui n'est pas une macro : le projet se compile avec ou sans Xcode.
import Combine
import SwiftUI

final class ViewStateBox<Value>: ObservableObject {
    @Published var value: Value
    init(_ value: Value) { self.value = value }
}

@propertyWrapper
struct ViewState<Value>: DynamicProperty {
    @StateObject private var box: ViewStateBox<Value>

    init(wrappedValue: Value) {
        _box = StateObject(wrappedValue: ViewStateBox(wrappedValue))
    }

    var wrappedValue: Value {
        get { box.value }
        nonmutating set { box.value = newValue }
    }

    var projectedValue: Binding<Value> {
        let box = self.box
        return Binding(get: { box.value }, set: { box.value = $0 })
    }
}
