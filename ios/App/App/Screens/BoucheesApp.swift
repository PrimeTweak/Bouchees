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
                .task { await etat.start() }
        }
    }
}

struct RootView: View {
    @Environment(AppState.self) private var etat
    @State private var tab = 0

    var body: some View {
        Group {
            if let error = etat.fatalError {
                FatalErrorScreen(message: error)
            } else if etat.isLoading && etat.recipes.isEmpty {
                ProgressView("Getting ready…").controlSize(.large)
            } else if etat.needsOnboarding {
                OnboardingScreen()
            } else {
                onglets
            }
        }
        .animation(.easeInOut(duration: 0.25), value: etat.needsOnboarding)
    }

    private var onglets: some View {
        TabView(selection: $tab) {
            RecipesScreen()
                .tabItem { Label("Recipes", systemImage: "fork.knife") }
                .tag(0)

            TopRatedScreen()
                .tabItem { Label("Best", systemImage: "star") }
                .tag(1)

            ScannerScreen()
                .tabItem { Label("Scan", systemImage: "barcode.viewfinder") }
                .tag(2)

            ProfilesScreen()
                .tabItem { Label("Children", systemImage: "person.2") }
                .tag(3)

            SettingsScreen()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(4)
        }
        .tint(Tint.betterave)
    }
}

/// With no engine the app can assert nothing. Better to say so plainly than to
/// show recipes that were never verified.
struct FatalErrorScreen: View {
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(Tint.canneberge)
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

struct OnboardingScreen: View {
    @Environment(AppState.self) private var etat
    @State private var step = 0
    @State private var draft = ChildProfile(name: "", ageMonths: 9, allergens: [])
    @State private var showAllAllergens = false
    @FocusState private var champNomActif: Bool

    private var firstName: String {
        let n = draft.name.trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? "votre enfant" : n
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                progressBar.padding(.bottom, 28)

                switch step {
                case 0: etapePrenom
                case 1: etapeAge
                default: etapeAllergenes
                }
            }
            .padding(22)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(Tint.background.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.2), value: step)
    }

    private var progressBar: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { i in
                Capsule()
                    .frame(height: 4)
                    .foregroundStyle(i <= step ? Tint.betterave : Color.primary.opacity(0.12))
            }
        }
        .accessibilityLabel("Step \(step + 1) of 3")
    }

    // Step 1 — the first name

    private var etapePrenom: some View {
        VStack(alignment: .leading, spacing: 0) {
            (Text("Bouchées") + Text(".").foregroundColor(Tint.betterave))
                .font(.system(size: 34, weight: .heavy, design: .rounded))

            Text("The everyday question: “can he eat this?” We answer it — and we show you exactly what we change.")
                .font(.body)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
                .padding(.bottom, 32)

            Text("Who are we cooking for?")
                .font(.title2.weight(.bold))
            Text("Just a first name. It personalises every answer.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
                .padding(.bottom, 20)

            TextField("First name", text: $draft.name)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .font(.title3.weight(.semibold))
                .padding(15)
                .background(Color(.secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .focused($champNomActif)
                .submitLabel(.next)
                .onSubmit { step = 1 }

            HStack(spacing: 14) {
                Button("Continue") { step = 1 }
                    .buttonStyle(.borderedProminent)
                    .tint(Tint.betterave)
                    .controlSize(.large)
                Button("Skip for now") {
                    draft.name = String(localized: "My child")
                    step = 1
                }
                .foregroundStyle(.secondary)
            }
            .padding(.top, 28)
        }
        .onAppear { champNomActif = true }
    }

    // Step 2 — the age

    private var etapeAge: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("How old is \(firstName)?")
                .font(.title2.weight(.bold))
            Text("This determines textures and safety guidance.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
                .padding(.bottom, 20)

            AgePicker(ageMonths: $draft.ageMonths)

            HStack(spacing: 14) {
                Button("Continue") { step = 2 }
                    .buttonStyle(.borderedProminent)
                    .tint(Tint.betterave)
                    .controlSize(.large)
                Button("Back") { step = 0 }.foregroundStyle(.secondary)
            }
            .padding(.top, 28)
        }
    }

    // Step 3 — the allergens

    private var etapeAllergenes: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("What are we avoiding for \(firstName)?")
                .font(.title2.weight(.bold))
            Text("We remove these ingredients from every recipe and suggest a replacement.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
                .padding(.bottom, 20)

            AllergenGrid(selection: $draft.allergens,
                             showAllAllergens: $showAllAllergens,
                             allergens: etat.knownAllergens)

            if draft.allergens.isEmpty {
                Text("None for now — that’s fine, you can change it any time.")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 14)
            }

            HStack(spacing: 14) {
                Button("See the recipes") { finish() }
                    .buttonStyle(.borderedProminent)
                    .tint(Tint.betterave)
                    .controlSize(.large)
                Button("Back") { step = 1 }.foregroundStyle(.secondary)
            }
            .padding(.top, 28)
        }
    }

    private func finish() {
        if draft.name.trimmingCharacters(in: .whitespaces).isEmpty {
            draft.name = String(localized: "My child")
        }
        etat.save(draft)
    }
}

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
                            .foregroundStyle(isOn ? Tint.betterave : .secondary)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 15)
                    .padding(.vertical, 13)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(isOn ? Tint.betterave.opacity(0.1) : Color(.secondarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(isOn ? Tint.betterave : Color.primary.opacity(0.1),
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
                .tint(Tint.betterave)
            }
        }
    }
}
