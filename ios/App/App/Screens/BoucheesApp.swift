// BoucheesApp.swift Entry point and navigation.

import SwiftUI

@main
@MainActor
struct BoucheesApp: App {
    @State private var app = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                                /* nil hands the decision back to iOS, which is the default:
                 * the parent already chose light or dark once, at the system
                 * level, and an app that ignores that is an app that. */
                /* Not preferredColorScheme: it cannot return to Auto once
                 * set, and sheets do not inherit it. See ThemeWindow.swift. */
                .appTheme(app.theme)
                .tint(Tone.brand)
                .task { await app.start() }
        }
    }
}

/// Clears the cached launch snapshot: that image is gone from the bundle, but
/// iOS keeps a SNAPSHOT of it under Library/SplashBoard/Snapshots and draws it
/// on every launch.
enum LaunchCache {
    static func clear() {
        let folder = NSHomeDirectory() + "/Library/SplashBoard"
        guard FileManager.default.fileExists(atPath: folder) else { return }
        try? FileManager.default.removeItem(atPath: folder)
    }
}

struct RootView: View {
    @Environment(AppState.self) private var app
    @State private var tab = 0
        /* No path and no sheet here: a sheet at the root never appeared at all —
     * a TabView on iOS 26 owns the system bar, and a sheet it presents
     * competes with it. */

    /// True until the launch animation has had time to play.
    @State private var launchPlayed = false

    private var showLaunch: Bool { !launchPlayed || app.isLoading }

    var body: some View {
        Group {
            if let error = app.fatalError {
                FatalErrorScreen(message: error)
            } else if showLaunch {
                                /* The recipes are BUNDLED, decoded synchronously from local
                 * files, so they are never empty — and the whole of start()
                 * takes a few milliseconds. */
                LaunchView()
            } else if app.needsOnboarding {
                OnboardingFlow()
            } else {
                onglets
            }
        }
        .animation(.soft(0.25), value: app.needsOnboarding)
        .animation(.soft(0.32), value: showLaunch)
        .task {
            /* Long enough for the mark to rise and the bite to settle, short
             * enough that nobody waits on it. Measured against the animation
             * in Mark.swift, not guessed. */
            /* Before the sleep, not after: the parent should not wait on a
             * file operation, and the cache only matters at the NEXT launch
             * anyway. */
            LaunchCache.clear()
            try? await Task.sleep(for: .milliseconds(1100))
            launchPlayed = true
        }
    }

    /// Three tabs, not five: "Best" was a permanent tab showing "come back
    /// later" until five people had rated something — expensive in trust for a
    /// screen that is empty at launch.
    @ViewBuilder
    private var onglets: some View {
        if #available(iOS 26, *) {
            ongletsModernes
        } else {
            ongletsClassiques
        }
    }

    @available(iOS 26, *)
    private var ongletsModernes: some View {
        TabView(selection: $tab) {
            Tab("Recipes", systemImage: "fork.knife", value: 0) {
                OngletPile { RecipesScreen(tab: $tab) }
            }
            Tab("Shopping", systemImage: "cart", value: 1) {
                OngletPile { ShoppingScreen() }
            }
            Tab("Scan", systemImage: "barcode.viewfinder", value: 2) {
                OngletPile { ScannerScreen(tab: $tab) }
            }
            Tab("Family", systemImage: "person.2", value: 3) {
                OngletPile { SettingsScreen() }
            }
            /* The search role gives the separated island for free, and iOS
             * owns its transition into a field. */
            Tab(value: 4, role: .search) {
                                /* Its own path: `navigate` is injected on the TabView, above
                 * every stack, so a route appended from the search tab landed
                 * in the Recipes stack — which is not on screen. */
                OngletPile { SearchScreen() }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }

    /// iOS 17 and 18. `tabItem` rather than `Tab`, which is iOS 18.
    private var ongletsClassiques: some View {
        TabView(selection: $tab) {
            OngletPile { RecipesScreen(tab: $tab) }
                .tabItem { Label("Recipes", systemImage: "fork.knife") }
                .tag(0)
            OngletPile { ShoppingScreen() }
                .tabItem { Label("Shopping", systemImage: "cart") }
                .tag(1)
            OngletPile { ScannerScreen(tab: $tab) }
                .tabItem { Label("Scan", systemImage: "barcode.viewfinder") }
                .tag(2)
            OngletPile { SettingsScreen() }
                .tabItem { Label("Family", systemImage: "person.2") }
                .tag(3)
            OngletPile { SearchScreen() }
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(4)
        }
    }
}

/// A tab that can push, with the stack it pushes into: each tab owns its path
/// and overrides `navigate` inside itself, so a push goes where the finger is.
private struct OngletPile<Contenu: View>: View {
    @ViewBuilder var contenu: () -> Contenu

    /// This tab's own stack: a single path at the root sent a search result
    /// into the Recipes stack: nothing appeared, and the recipe was waiting in
    /// another tab when the parent switched.
    @State private var path = NavigationPath()

    /// This tab's own sheet: a sheet on a TabView is presented BY the TabView,
    /// which on iOS 26 also owns the system bar — the two compete and neither
    /// wins.
    @State private var sheet: AppSheet?

    var body: some View {
        NavigationStack(path: $path) {
            contenu().destinations()
        }
        .environment(\.navigate, NavigateAction { route in path.append(route) })
        .environment(\.presentSheet, PresentSheetAction(show: { quoi in sheet = quoi }))
        .sheet(item: $sheet) { quoi in
            switch quoi {
            case .childPicker: ChildPickerSheet()
            case .search: SearchSheet()
            }
        }
    }
}

/// Every destination the app can push, applied once.
extension View {
    func destinations() -> some View {
        navigationDestination(for: Route.self) { route in
            RouteDestination(route: route)
        }
    }
}

private struct RouteDestination: View {
    let route: Route
    @Environment(AppState.self) private var app

    var body: some View {
        switch route {
        case .recipe(let id):
            if let pair = app.pairFor(for: id) {
                RecipeDetailScreen(recipe: pair.recipe, result: pair.result,
                                   firstName: app.activeProfile.firstName)
            }
        case .saved: SavedScreen()
        case .topRated: TopRatedScreen()
        case .profiles: ProfilesScreen()
        }
    }
}


/// Everything the stack can push: one enum, so the destinations live in one
/// place rather than being re-declared on each screen.
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
                .scaledFont(44)
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
                    .background(isOn ? Tone.brand.opacity(0.1) : Tone.surface,
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
                        .scaledFont(26, weight: .bold, design: .rounded)
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

/// Pushes a route onto the one stack: with a single stack it only has to say
/// where it wants to go.
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

/// Everything the root can present: a `.sheet` attached to the button that
/// triggers it dies with that button.
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
