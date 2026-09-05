// BoucheesApp.swift Entry point and navigation.

import SwiftUI
import UIKit

@main
@MainActor
struct BoucheesApp: App {
    @Environment(\.scenePhase) private var scenePhase
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
                /* Midnight and the return from background: the day marker and
                 * the hero were the ones from the last launch until the app
                 * was killed. A meal app has to follow the calendar. */
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { app.refreshPlan() }
                }
                .onReceive(NotificationCenter.default.publisher(
                    for: UIApplication.significantTimeChangeNotification)) { _ in
                    app.refreshPlan()
                }
        }
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
                /* Held only for the local part of start(): bundled files and
                 * the engine, a few milliseconds. The network never holds it. */
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
        }
    }
}


/// Everything the stack can push: one enum, so the destinations live in one
/// place rather than being re-declared on each screen.
enum Route: Hashable {
    case recipe(String)
    case saved
    case topRated
}

/// With no engine the app can assert nothing. Better to say so plainly than to
/// show recipes that were never verified.
struct FatalErrorScreen: View {
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .scaledFont(Type.display)
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

    /// The stage this age falls in, for the line under the counter.
    private var stage: (name: String, texte: String) {
        let i = Self.stages.lastIndex { ageMonths >= $0.min } ?? 0
        let s = Self.stages[i]
        return (name: s.name, texte: s.texte)
    }

    /* One control for one value: the counter sets the months, the stage is
     * read off it. */
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { ageMonths = max(6, ageMonths - 1) } label: {
                    Image(systemName: "minus")
                        .scaledFont(Type.heading, weight: .semibold)
                        .foregroundStyle(Tone.brand)
                        .frame(width: 40, height: 40)
                        .background(Tone.brand.opacity(0.10), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("One month younger")

                Spacer(minLength: 0)
                VStack(spacing: 0) {
                    Text("\(ageMonths)")
                        .scaledFont(Type.title, weight: .bold, design: .rounded)
                        .foregroundStyle(Tone.text)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("months").scaledFont(Type.micro).foregroundStyle(Tone.text3)
                }
                Spacer(minLength: 0)

                Button { ageMonths = min(72, ageMonths + 1) } label: {
                    Image(systemName: "plus")
                        .scaledFont(Type.heading, weight: .semibold)
                        .foregroundStyle(Tone.brand)
                        .frame(width: 40, height: 40)
                        .background(Tone.brand.opacity(0.10), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("One month older")
            }
            .animation(.soft(0.2), value: ageMonths)

            Divider().overlay(Tone.hairline).padding(.top, 10)

            (Text(LocalizedStringKey(stage.name)).foregroundStyle(Tone.text).fontWeight(.semibold)
             + Text(" · ").foregroundStyle(Tone.text3)
             + Text(LocalizedStringKey(stage.texte)).foregroundStyle(Tone.text2))
                .scaledFont(Type.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 10)
        }
        .padding(13)
        .background(Tone.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1.5)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Age: \(ageMonths) months, \(stage.name)")
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
