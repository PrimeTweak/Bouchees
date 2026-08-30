//  BoucheesApp.swift
//
//  Entry point and navigation. Native tabs, and a guided onboarding
//  au premier lancement — pas un profile bidon qu'il faudrait corriger.

import SwiftUI

@main
@MainActor
struct BoucheesApp: App {
    @State private var etat = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(etat)
                /* nil hands the decision back to iOS, which is the default:
                 * the parent already chose light or dark once, at the system
                 * level, and an app that ignores that is an app that fights
                 * its user. */
                /* Not preferredColorScheme: it cannot return to Auto once
                 * set, and sheets do not inherit it. See ThemeWindow.swift. */
                .appTheme(etat.theme)
                .tint(Tone.brand)
                .task { await etat.start() }
        }
    }
}

struct RootView: View {
    @Environment(AppState.self) private var etat
    @State private var tab = 0
    @State private var path = NavigationPath()
    @State private var sheet: AppSheet?

    var body: some View {
        Group {
            if let error = etat.fatalError {
                FatalErrorScreen(message: error)
            } else if etat.isLoading && etat.recipes.isEmpty {
                /* The mark on the theme's canvas, rather than a spinner on
                 * white. It removes the flash between launch and first frame,
                 * and it is the first thing the app says about itself. */
                LaunchView()
            } else if etat.needsOnboarding {
                OnboardingFlow()
            } else {
                onglets
            }
        }
        .animation(.easeInOut(duration: 0.25), value: etat.needsOnboarding)
    }

    /// THREE TABS, NOT FIVE.
    ///
    /// "Best" was a permanent tab showing "come back later" until five people
    /// had rated something — expensive in trust for a screen that is empty at
    /// launch. It is now a filter of the one list.
    ///
    /// "Children" was a tab you had to visit to learn who the app was filtering
    /// for. It is now the context header, in view on every screen, because
    /// knowing who you are cooking for is a state, not a destination.
    /// THREE TABS, IN A FLOATING GLASS CAPSULE.
    ///
    /// iOS 26 detaches the tab bar from the screen edges — a pill, inset 21pt,
    /// with content scrolling beneath it and fading out at the bottom. That is
    /// the native geometry, not an interpretation of it.
    ///
    /// Glass belongs here and to almost nowhere else: it is the navigation
    /// layer, floating above content. Applied to list rows it becomes mush.
    /// THREE TABS, IN A FLOATING GLASS CAPSULE.
    ///
    /// Not a TabView: the system bar is opaque, full width, and sits on top of
    /// a safe-area inset. iOS 26 wants the bar detached — a pill inset 21pt
    /// with content scrolling beneath it — so the screens run full height and
    /// the bar floats over them.
    /// THE BAR AS A SAFE-AREA INSET, NOT AN OVERLAY.
    ///
    /// A ZStack put the capsule on top of the content: it reserved no space,
    /// so the last rows scrolled under it, and taps landed on the scroll view
    /// behind rather than on the buttons.
    ///
    /// `safeAreaInset` is the pattern for this. The bar becomes a sibling that
    /// owns its strip of the screen — the content ends above it on its own,
    /// and hit testing goes where it looks like it should.
    /// ONE NavigationStack, HERE, around everything.
    ///
    /// Each screen used to open its own. A `safeAreaInset` reduces the safe
    /// area of its DIRECT child, and a NavigationStack resets it for its
    /// content — so the bar below reached none of the four screens. That one
    /// mistake produced the dead back button, the pill that survived every
    /// pushed screen, the tab bar covering text, and thirty-six compensating
    /// paddings across nine files.
    ///
    /// With a single stack the inset reaches the content, pushed screens hide
    /// the bar the way iOS intends, and no screen has to guess.
    private var onglets: some View {
        NavigationStack(path: $path) {
            Group {
                switch tab {
                case 0: RecipesScreen(tab: $tab)
                case 1: ShoppingScreen()
                case 2: ScannerScreen(tab: $tab)
                default: SettingsScreen()
                }
            }
            /* THE INSET GOES INSIDE THE STACK.
             *
             * Placed on the NavigationStack it sat OUTSIDE, and a stack does
             * not hand its parent's safe area down to the scrolling content
             * inside it. That is the same trap as before, one level up: the
             * bar reserved space nobody could see.
             *
             * Inside, on the screen itself, it does both halves of what Apple
             * describes — the list passes behind the glass, and the scroll
             * gains enough inset that its last row clears the bar. */
            .safeAreaInset(edge: .bottom, spacing: 0) {
                FloatingTabBar(selection: $tab)
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .recipe(let id):
                    if let pair = etat.pairFor(pour: id) {
                        RecipeDetailScreen(recipe: pair.recipe, result: pair.result,
                                           firstName: etat.activeProfile.firstName)
                    }
                case .saved:
                    SavedScreen()
                case .topRated:
                    TopRatedScreen()
                case .profiles:
                    ProfilesScreen()
                }
            }
        }
        .ignoresSafeArea(.keyboard)
        .environment(\.navigate, NavigateAction { route in path.append(route) })
        .environment(\.presentSheet, PresentSheetAction { sheet = $0 })
        /* On the root, which never gets rebuilt by a scrolling layout. */
        .sheet(item: $sheet) { quoi in
            switch quoi {
            case .childPicker: ChildPickerSheet()
            case .search: SearchSheet()
            }
        }
    }

}

/// Everything the stack can push. One enum, so the destinations live in one
/// place rather than being re-declared on each screen.
///
/// FILE SCOPE, not nested: every screen refers to it, so nesting it inside
/// RootView made it RootView.Route and nothing else could see it.
enum Route: Hashable {
    case recipe(String)
    case saved
    case topRated
    case profiles
}

/// With no engine the app can assert nothing. Better to say so plainly than to
/// show recipes that were never verified.
struct FatalErrorScreen: View {
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(Tone.no)
            Text("Bouchées can’t start")
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
            Text("The safety tables couldn’t be loaded, so the app can’t make a call on any recipe. Reinstalling usually fixes this.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.top, 6)
        }
        .padding(28)
    }
}

// MARK: - Guided onboarding

// MARK: - Age picker

/// Stages first, fine tuning after. Stepping to six years one month at a time
/// demanderait soixante-six tapes.
struct AgePicker: View {
    @Binding var ageMonths: Int

    private static let stages: [(min: Int, name: String, texte: String)] = [
        (6, "6–8 months", "Smooth purées and large melt-in-the-mouth sticks"),
        (9, "9–11 months", "Coarsely mashed and small soft pieces"),
        (12, "1–2 years", "Tender pieces; most family dishes work"),
        (24, "2–3 years", "Normal cutting, with care"),
        (48, "4 years and up", "Any texture")
    ]

    private func borneSuivante(_ index: Int) -> Int {
        index + 1 < Self.stages.count ? Self.stages[index + 1].min : 999
    }

    var body: some View {
        VStack(spacing: 9) {
            ForEach(Array(Self.stages.enumerated()), id: \.offset) { index, stage in
                let isOn = ageMonths >= stage.min && ageMonths < borneSuivante(index)
                Button {
                    ageMonths = stage.min
                } label: {
                    HStack(spacing: 14) {
                        Text(LocalizedStringKey(stage.name))
                            .font(.headline)
                            .frame(width: 82, alignment: .leading)
                        Text(LocalizedStringKey(stage.texte))
                            .font(.footnote)
                            .foregroundStyle(isOn ? Tone.brand : Color.secondary)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 15)
                    .padding(.vertical, 13)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(isOn ? Tone.brand.opacity(0.1) : Color(.secondarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(isOn ? Tone.brand : Color.primary.opacity(0.1),
                                          lineWidth: isOn ? 2 : 1.5)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? [.isSelected] : [])
            }

            HStack(spacing: 14) {
                Button { ageMonths = max(6, ageMonths - 1) } label: {
                    Image(systemName: "minus").frame(width: 40, height: 40)
                }
                .accessibilityLabel("One month younger")

                VStack(spacing: 0) {
                    Text("\(ageMonths)")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("months exactly").font(.caption2).foregroundStyle(.secondary)
                }
                .frame(minWidth: 110)

                Button { ageMonths = min(72, ageMonths + 1) } label: {
                    Image(systemName: "plus").frame(width: 40, height: 40)
                }
                .accessibilityLabel("One month older")
            }
            .buttonStyle(.bordered)
            .padding(.top, 8)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Exact age: \(ageMonths) months")
        }
    }
}

// MARK: - Allergen grid

struct AllergenGrid: View {
    @Binding var selection: [String]
    @Binding var showAllAllergens: Bool
    let allergens: [Allergen]

    private static let common = ["lait", "oeuf", "arachide", "noix", "ble", "soya"]

    private var visible: [Allergen] {
        showAllAllergens ? allergens : allergens.filter { Self.common.contains($0.id) }
    }

    private var otherCount: Int { max(0, allergens.count - Self.common.count) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 9)], spacing: 9) {
                ForEach(visible) { a in
                    AllergenToggle(allergene: a, isOn: selection.contains(a.id)) {
                        if let i = selection.firstIndex(of: a.id) {
                            selection.remove(at: i)
                        } else {
                            selection.append(a.id)
                        }
                    }
                }
            }

            if !showAllAllergens && otherCount > 0 {
                Button {
                    showAllAllergens = true
                } label: {
                    Label(String(format: String(localized: "See the %lld other allergens"),
                                 otherCount), systemImage: "plus.circle")
                        .font(.subheadline.weight(.semibold))
                }
                .tint(Tone.brand)
            }
        }
    }
}

// MARK: - Navigation

/// Pushes a route onto the one stack.
///
/// A screen used to own a `navigationDestination` and a piece of @State per
/// destination. With a single stack it only has to say where it wants to go.
struct NavigateAction {
    let push: (Route) -> Void
    func callAsFunction(_ route: Route) { push(route) }
}

private struct NavigateKey: EnvironmentKey {
    static let defaultValue = NavigateAction { _ in }
}

extension EnvironmentValues {
    var navigate: NavigateAction {
        get { self[NavigateKey.self] }
        set { self[NavigateKey.self] = newValue }
    }
}

// MARK: - Sheets

/// Everything the root can present.
///
/// A `.sheet` attached to the button that triggers it dies with that button.
/// The child pill and the search island both live inside a top bar that
/// SwiftUI rebuilds on every layout shift, so their state was gone before the
/// sheet could open — which is why both needed two taps.
enum AppSheet: String, Identifiable {
    case childPicker
    case search

    var id: String { rawValue }
}

struct PresentSheetAction {
    let show: (AppSheet) -> Void
    func callAsFunction(_ sheet: AppSheet) { show(sheet) }
}

private struct PresentSheetKey: EnvironmentKey {
    static let defaultValue = PresentSheetAction { _ in }
}

extension EnvironmentValues {
    var presentSheet: PresentSheetAction {
        get { self[PresentSheetKey.self] }
        set { self[PresentSheetKey.self] = newValue }
    }
}
