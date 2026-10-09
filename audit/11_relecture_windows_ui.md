# 11 — Relecture des interfaces (Windows Fluent 2, animations Mac) et passe de sécurité

## Périmètre

Commits relus : `cee6b6d` (Mac : animations), `69ec026` (Windows : refonte Fluent 2), `e67765c` (README, concordance des tables). Diff `16f22ea..e67765c`.

- **Mac** : `GlassStyle.swift` (`Motion`, `MotionModifier`, `.motion`, `.bounceSymbol`, `PressableRowStyle`, `GlassGroup`, `glassCapsule(interactive:)`, `CapInfo` / `KeyCombo.caps`, `KeyCaps`), `EditorView.swift`, `OnboardingView.swift`, `FLShortcutApp.swift` (`PauseIndicator`, `PauseBadge`, `MenuContent`, `PanelItem`), `Tests/FLShortcutTests`.
- **Windows** : `MainWindow.xaml`, `MainWindow.xaml.cs`, `Motion.cs`, `App.xaml`, `AppController.cs`, `FLShortcut.Core/Actions.cs`, `FLShortcut.Core.Tests/CoreTests.cs`.

## Méthode

Il n'y a ni Swift, ni Xcode, ni .NET dans cet environnement. La relecture tient donc lieu de compilation, comme pour la relecture 10. Chaque fichier modifié a été lu en entier, et chaque API comparée à sa signature et à sa disponibilité connues :

- **Mac** : SwiftUI macOS 13 ; `symbolEffect` macOS 14 ; `GlassEffectContainer`, `glassEffect` et `Glass.interactive()` macOS 26 sous `#if compiler(>=6.2)`.
- **Windows** : WinUI 3 / Windows App SDK 1.6 (`SelectorBar` 1.5+, `SystemBackdrop` 1.3+, `MicaBackdrop.Kind`, `TitleBarHeightOption`, `InfoBadge`, `PipsPager`).

Contrôles faits par script :
- noms `x:Name` utilisés dans le code-behind ;
- gestionnaires d'événements déclarés en XAML, avec leur signature ;
- clés de ressources `StaticResource`, `ThemeResource` et `Res<…>(…)` ;
- points de code des glyphes Segoe Fluent Icons.

`Package.swift` est en `swift-tools-version:5.9`. Le mode de langage est donc Swift 5, même avec Xcode 26 : la concurrence stricte ne produit que des avertissements, aucune erreur.

## Constats

Gravités : **Compilation**, **Bloquant**, **Majeur**, **Mineur**, **Sécurité**.

| # | Fichier:ligne (après correction) | Gravité | Problème | Correction |
|---|---|---|---|---|
| UI-01 | `EditorView.swift:772-788` | Majeur (animation infinie) | La pulsation du champ de capture reposait sur `withAnimation(.repeatForever)` piloté par un état du parent. À l'arrêt, `.motion(snappy, value: recording)` animait la même ombre dans la même mise à jour. Les animations SwiftUI étant additives, la répétition infinie pouvait continuer en fond, invisible mais toujours active, et fausser la pulsation suivante. `withTransaction(disablesAnimations)` n'est pas une garantie documentée. | **Appliquée** : le contour n'existe plus que `if recording`. La lueur pulse dans une vue dédiée (`.pulsing`, nouveau `PulseModifier`, `GlassStyle.swift:57`) qui disparaît avec l'enregistrement, et l'animation meurt avec elle. « Réduire les animations » est lu dans l'environnement. |
| UI-02 | `OnboardingView.swift:191-207` | Mineur (effet absent) | Le point d'attente « qui respire » démarrait `repeatForever` dans `onAppear`, alors que `installed` était faux. L'opacité ne changeait donc pas et aucune animation n'était enregistrée. Après l'installation, le point passait d'un coup à 0,45 et restait fixe. La pulsation ne se voyait jamais dans le parcours normal. | **Appliquée** : vue propre à l'état « installé, en attente » avec `.pulsing(duration: 1.1)` ; état `breathe` supprimé. |
| UI-03 | `FLShortcutApp.swift:214-240` | Mineur (course) | En fin de fondu de sortie, le badge pause relisait `Store.shared.enabled`. C'est correct aujourd'hui grâce à `receive(on: RunLoop.main)`, mais cela dépend de l'ordre de publication de `@Published` (willSet). | **Appliquée** : drapeau local `wantsVisible`, décidé à chaque `update`. Un nouveau passage en pause pendant le fondu garde le panneau. |
| UI-04 | `Motion.cs:55-61, 80-84, 99-104` | Majeur (Windows) | Les Storyboard gardaient leur valeur finale (`FillBehavior.HoldEnd`), et une valeur animée maintenue l'emporte sur toute valeur locale. Deux conséquences. (a) Après un `Exit`, la notification restait maintenue à l'opacité 0 : si « Effets d'animation » était coupé ensuite, `Enter` posait `Opacity = 1` en local et la notification restait **invisible**. (b) `Exit` partait de la valeur locale, qui vaut 0 pendant et après `Enter` : la notification disparaissait d'un coup au lieu de s'estomper. | **Appliquée** : en fin d'`Enter` et de `Pop`, la valeur finale devient la valeur locale et le Storyboard est relâché (`Stop`). `Exit` part de la valeur affichée (`From` non renseigné) et se relâche après `done()`. |
| UI-05 | `MainWindow.xaml.cs:865-879` | Majeur (robustesse) | `Res<T>` faisait `(T)Application.Current.Resources[key]` : une clé absente lève une exception à l'exécution, par exemple dans `UpdateStatus()` au lancement. `TryRes` passait par `TryGetValue`, donc par `HasKey`, dont la recherche dans les dictionnaires fusionnés et de thème (`XamlControlsResources`) n'est pas garantie. `TryRes("CautionIconInfoBadgeStyle")` pouvait donc rendre `null` à tort. | **Appliquée** : `Lookup` passe par l'indexeur, qui cherche bien dans les dictionnaires fusionnés et de thème, dans un `try/catch`. Une clé absente donne un repli neutre (pinceau gris, style par défaut, coin de 8 px) au lieu d'un plantage. |
| UI-06 | `MainWindow.xaml.cs` (19 glyphes) | Mineur (maintenance) | Les glyphes étaient écrits comme caractères de la zone privée, invisibles dans un éditeur et effaçables sans s'en rendre compte. | **Appliquée** : séquences `\uE…`. Tous les points de code ont été vérifiés : E8D6 Audio, E7C8 Record, E767 Volume, E8A9 ViewAll, E765 KeyboardClassic, E71D AllApps, E71B Link, E73E CheckMark, E769 Pause, E7E8 PowerButton, E783 Error, E7BA Warning, E946 Info, E895 Sync, E76C ChevronRight, E74D Delete, E768 Play, E721 Search, E77B Contact, E711 Cancel, E710 Add, E72A Forward, E72E Lock. `E8A1` (XAML, `PortsIcon`) est remplacé dès le premier `UpdatePortsStep`. |
| SEC-11-01 | `Core/Model.cs:230-252`, `AppController.cs:296`, `Model.swift:296-309, 342`, `EditorView.swift:923` | Sécurité (Mineur) | La nouvelle description de ligne (Windows) affiche tel quel le nom d'action inconnu d'un profil importé : jusqu'à 512 Ko, avec des caractères invisibles possibles (inversion bidi U+202E, largeur nulle, contrôle). Le message d'erreur et le titre côté Mac font de même. Aucune exécution n'est possible : `TextBlock` et `Text(String)` n'interprètent aucun balisage. En revanche, un libellé pouvait être maquillé, par exemple « Action inconnue (‮exe.tset) ». | **Appliquée** : `DisplayText.Safe` (C#) et `String.displaySafe()` (Swift) retirent les catégories Cc et Cf, et coupent à 40 caractères sans casser une paire de substitution. Seul l'affichage change : la valeur stockée reste intacte (REL-01). Tests ajoutés : `DisplayTextTests`, `testImportedTextIsCleanedForDisplay`. |
| UI-07 | `tests/python/__pycache__/*.pyc` | Mineur (dépôt) | Des binaires Python compilés étaient suivis par git et réécrits à chaque exécution des tests. | **Appliquée** : retirés de l'index, nouveau `.gitignore`. |
| UI-08 | `MainWindow.xaml.cs` (couleurs posées en code) | Mineur | Les pinceaux lus en code (`Res<Brush>`) correspondent au thème de l'appli au moment de la lecture. Si l'utilisateur change de thème clair / sombre pendant que la fenêtre est ouverte, la carte d'état garde l'ancienne teinte jusqu'au prochain changement d'état. Les lignes, reconstruites souvent, sont moins touchées. | Laissé. Pour corriger : reconstruire sur `Root.ActualThemeChanged`. |
| UI-09 | `MainWindow.xaml.cs:59` | À vérifier | `AppWindow.TitleBar.PreferredHeightOption = Tall` ne s'applique que lorsque le contenu est étendu dans la barre de titre. Avec Windows App SDK 1.6, `Window.ExtendsContentIntoTitleBar` le fait aussi pour `AppWindow`, mais seulement d'après la documentation. Sans plantage possible : `IsCustomizationSupported()` protège l'appel. | À vérifier sur la machine : les boutons système doivent faire 48 px. |
| UI-10 | `MainWindow.xaml.cs:61-62` | À vérifier (aspect) | `ThemeShadow` sans `Receivers`, avec `Translation.Z = 32` : l'ombre portée dépend de la version de WinUI et de Windows (10 ou 11). | À vérifier visuellement. Sans conséquence fonctionnelle. |

### Vérifié sans problème

**Mac**
- `Animation.spring(response:dampingFraction:)` ; `withAnimation(_:_:)` avec une fermeture `() -> Void` (les fermetures à une seule expression comme `store.upsert(copy)` sont valides).
- `AnyTransition` `.move`, `.scale(scale:anchor:)`, `.offset(x:y:)`, `.asymmetric`, `.combined` : chaînes de membres implicites typées `AnyTransition`, sans ambiguïté avec le protocole `Transition` de macOS 14.
- `@Environment(\.accessibilityReduceMotion)` (macOS 10.15) ; `contentTransition(.interpolate)` (macOS 13) ; `.background { if … else … }` et `.overlay { if … }` (macOS 12) ; `matchedGeometryEffect` avec `@Namespace`, avec une seule source à la fois.
- `symbolEffect(.bounce, value:)` est bien protégé par `if #available(macOS 14.0, *)`. Sous `#if compiler(>=6.2)`, `GlassEffectContainer(spacing:content:)`, `glassEffect(_:in:)`, `Glass.regular.interactive()`, `.glass` et `.glassProminent` sont protégés par `if #available(macOS 26.0, *)`. Les deux chemins (Xcode 16 et Xcode 26) sont valides.
- Valeurs d'animation `Equatable` : `KeyCombo` et `Remap` (Hashable), `[Bool]`, `[String]`, `LinkStatus`, `ScriptIntegrity.State`, `ToastMessage` (égalité par `id`).
- `NSAnimationContext.runAnimationGroup(_:completionHandler:)` ; `CAMediaTimingFunction(name:)` (QuartzCore est exposé par AppKit) ; `NSWindow.animationBehavior = .alertPanel`.
- Pas de cycle de rétention : `[weak self]` dans `PauseIndicator`, et les vues sont des structures.
- `Tests/FLShortcutTests` n'utilise pas `KeyCombo.caps` : le passage de tuples à `[CapInfo]` ne casse aucun test.
- VoiceOver : les libellés sont conservés (`KeyCaps` en `children: .ignore` avec `spoken`, `CaptureField`, `StatusLine` combinée, notification `.contain`).
- « Réduire les animations » est respecté partout : `Motion.run`, `Motion.transition`, `MotionModifier`, `PulseModifier`, `PressableRowStyle`, fondu instantané du badge.

**Windows**
- Toutes les clés existent dans WinUI 3 / Windows App SDK 1.6 : `SystemFillColorCaution(Background)Brush`, `SystemFillColorSuccess/Critical/NeutralBrush`, `AcrylicInAppFillColorDefaultBrush`, `SurfaceStrokeColorFlyoutBrush`, `ControlCornerRadius`, `OverlayCornerRadius`, `SubtleFillColorSecondaryBrush`, `TextOnAccentFillColorPrimaryBrush`, `AccentFillColorDefaultBrush`, `AccentTextFillColorPrimaryBrush`, `CardBackgroundFillColorDefaultBrush`, `CardStrokeColorDefaultBrush`, `ControlStrokeColorSecondaryBrush`, `ControlFillColorDefaultBrush`, `TextFillColorSecondaryBrush`, `ApplicationPageBackgroundThemeBrush`, `CaptionTextBlockStyle`, `BodyStrongTextBlockStyle`, `SubtitleTextBlockStyle`, `TitleTextBlockStyle`, `TitleLargeTextBlockStyle`, `AccentButtonStyle`, `DefaultContentDialogStyle`, `CautionIconInfoBadgeStyle`. `LayerFillColorDefaultBrush` n'est pas utilisé.
- Les `StaticResource ControlCornerRadius` d'`App.xaml` sont résolus, car `XamlControlsResources` est fusionné avant.
- Les 13 gestionnaires XAML existent avec la bonne signature : `OnNavChanged(NavigationView, NavigationViewSelectionChangedEventArgs)`, `OnNavInvoked(NavigationView, NavigationViewItemInvokedEventArgs)`, `OnSearchChanged(AutoSuggestBox, AutoSuggestBoxTextChangedEventArgs)`, `Toggled` et `Click` en `(object, RoutedEventArgs)`.
- `SelectorBar.SelectionChanged` : la lambda `(bar, _)` est typée `SelectorBar`, `SelectedItem` est un `SelectorBarItem` dont on lit `Tag`. La réentrance par `cats.SelectedItem = …` dans `Refresh()` est neutralisée par la garde.
- Tous les `x:Name` utilisés en code existent. `SelectionChanged` levé au chargement par `IsSelected="True"` sort tout de suite (`tag == _navFilter`).
- `Storyboard.SetTarget(Timeline, DependencyObject)` et `SetTargetProperty(Timeline, string)` : les propriétés animées (`Opacity`, `TranslateTransform.X/Y`, `ScaleTransform`) sont indépendantes, aucune `EnableDependentAnimation` n'est requise.
- Lignes désactivées (opacité 0,5) : `Enter` lit l'opacité locale, posée avant l'appel. Les lignes sont reconstruites à chaque changement. Depuis UI-04, la valeur redevient locale en fin d'animation.
- Course de la notification : une notification arrivée pendant un fondu de sortie remet `_toastLeaving` à faux. `done()` ne masque alors rien, et `Stop()` du Storyboard de sortie laisse l'animation d'entrée aux commandes. Le minuteur précédent est arrêté avant d'en créer un autre.
- `MicaController.IsSupported()` puis `DesktopAcrylicController.IsSupported()`, sinon un fond uni ; `MicaKind` vient de `Microsoft.UI.Composition.SystemBackdrops`. Aucune collision de noms (`Motion` est résolu dans l'espace de noms de l'appli).
- `ShortcutRow.Category` (`required`) est bien renseigné à l'unique construction. `FlActionDetails.Detail` couvre les 38 clés, et le test `ActionTextTests` passe par lecture.

## Conclusions de sécurité

- **Aucune journalisation de touches.** Aucun `print`, `NSLog`, `os_log`, `Debug.WriteLine`, `Console` ou `Trace` n'a été ajouté. Les messages affichés (notification, aide) ne contiennent que les combinaisons choisies par l'utilisateur dans sa propre fiche.
- **Aucun nouvel accès réseau.** Le seul lien est le `HyperlinkButton` loopMIDI, déjà présent, ouvert dans le navigateur à la demande de l'utilisateur. Aucun `URLSession`, `HttpClient` ou `Launcher` n'a été ajouté.
- **Liste blanche et signature intactes.** « Tester » passe par `link.test(action:)` / `_app.TestAction(id)` avec un identifiant venu de la table des actions. Le sélecteur ne propose que `FlActions.All`, et les actions indisponibles sont désactivées. Aucun nouveau chemin d'envoi MIDI ou d'injection.
- **Aucune injection hors de FL.** La capture dans la fiche se fait par `PreviewKeyDown` sur un bouton de **notre** fenêtre, avec `SetRecording(true)` côté crochet. Sur Mac, elle passe par `Recorder` (moniteur local). Rien n'est envoyé à une autre fenêtre.
- **Chaînes importées.** Elles sont affichées en texte brut, sans balisage interprété. Elles sont désormais nettoyées et raccourcies à l'affichage (SEC-11-01). Les étiquettes de lignes viennent de la table des actions, pas du profil.

## À vérifier à la première compilation

**Mac (Xcode 16 / macos-15, puis Xcode 26)**
- [ ] `swift build` et `swift test` passent, dont `testImportedTextIsCleanedForDisplay`. Seuls des avertissements sont acceptables : `onChange(of:perform:)` déprécié en macOS 14, concurrence en mode Swift 5.
- [ ] Avec Xcode 26 : `GlassGroup` (`GlassEffectContainer`) et `glassCapsule(interactive: true)` compilent. Le champ de recherche réagit au pointeur.
- [ ] Champ de capture : la lueur pulse pendant l'enregistrement et **s'arrête net** à la fin. Profiler (Instruments › Animation Hitches) : plus aucune transaction après la fermeture de la fiche.
- [ ] Accueil, étape 2 : le point orange respire après « Installer le lien », puis devient la coche verte qui rebondit (macOS 14+).
- [ ] Badge pause : fondu à l'entrée et à la sortie. ⌃⌥⌘F deux fois rapidement : le badge reste affiché si l'état final est « en pause ».
- [ ] « Réduire les animations » activé : fondus seulement, aucune pulsation, aucun rebond, aucun enfoncement.

**Windows (Windows App SDK 1.6, .NET 8)**
- [ ] `dotnet build` et `dotnet test FLShortcut.Core.Tests` passent (`ActionTextTests`, `DisplayTextTests`).
- [ ] La fenêtre se charge sans `XamlParseException` en thème clair, en thème sombre et en contraste élevé.
- [ ] La pastille « attention » (`InfoBadge` de style Caution) apparaît sur une rubrique dont un raccourci a un conflit.
- [ ] Barre de titre de 48 px avec boutons système alignés (UI-09). Mica sur Windows 11, acrylique sur Windows 10.
- [ ] Notification : apparition, remplacement par une autre, fermeture pendant l'apparition (fondu depuis l'état courant), puis « Effets d'animation » coupé dans Réglages : la notification suivante est **visible** (UI-04).
- [ ] Ombre de la notification (UI-10) ; `SelectorBar` dans la fiche (l'indicateur glisse, la recherche désélectionne) ; `PipsPager` affiché sans être cliquable.
- [ ] Ligne désactivée : 50 % d'opacité après l'animation d'apparition, et 100 % après « Activer ».
