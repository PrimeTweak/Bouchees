// ProfilesAndSettings.swift
// Children's profiles stay on the device, which is what the App Store
// privacy labels declare; nothing here sends them anywhere.

import SwiftUI
import StoreKit

// MARK: - Profiles

struct ProfilesScreen: View {
    @Environment(AppState.self) private var app
    @State private var editing: ChildProfile?
    @State private var pendingDeletion: ChildProfile?

    var body: some View {
        List {
            Section {
                ForEach(app.profiles) { p in
                    Button {
                        app.select(p.id)
                    } label: {
                        ProfileRow(profile: p,
                                    isOn: !app.familyMode && p.id == app.activeProfileID,
                                    names: app.allergenNames(p.allergens),
                                    tally: app.tally(for: p))
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            pendingDeletion = p
                        } label: { Label("Remove", systemImage: "trash") }

                        Button {
                            editing = p
                        } label: { Label("Edit", systemImage: "pencil") }
                        .tint(Tone.brand)
                    }
                }
            } header: {
                Text("Your children")
            } footer: {
                Text("Age determines textures and safety guidance. Allergens are removed from every recipe, with a replacement suggested.")
            }

            if app.profiles.count > 1 {
                Section {
                    Toggle(isOn: Binding(
                        get: { app.familyMode },
                        set: { _ in app.toggleFamilyMode() })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Everyone at the table").font(.body)
                                Text("Youngest child’s age, and everything each one avoids")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .tint(Tone.brand)
                }
            }

            Section {
                Button {
                    editing = ChildProfile(name: "", ageMonths: 9, allergens: [])
                } label: {
                    Label("Add a child", systemImage: "plus.circle.fill")
                }
            }
        }
        .navigationTitle("Children")
        .sheet(item: $editing) { p in
            ProfileEditor(profile: p)
        }
        .alert("Remove this profile?",
               isPresented: Binding(get: { pendingDeletion != nil },
                                    set: { if !$0 { pendingDeletion = nil } }),
               presenting: pendingDeletion) { p in
            Button("Remove", role: .destructive) { app.remove(p) }
            Button("Cancel", role: .cancel) { }
        } message: { p in
            Text("\(p.name)'s profile and their allergens will be erased from this device.")
        }
    }
}

struct ProfileRow: View {
    let profile: ChildProfile
    let isOn: Bool
    let names: [String]
    var tally: AppState.ProfileTally? = nil

    private var avatarColor: Color {
        let teintes: [Color] = [Tone.brand, Tone.yes, Tone.swap, Tone.no]
        var somme = 0
        for octet in profile.name.utf8 { somme = (somme &* 31 &+ Int(octet)) % 9973 }
        return teintes[somme % teintes.count]
    }

    var body: some View {
        HStack(spacing: 13) {
            Text(String(profile.name.prefix(1)).uppercased())
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(avatarColor, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name).font(.headline).foregroundStyle(.primary)
                Text(names.isEmpty
                     ? "\(Format.age(profile.ageMonths)) — no allergen avoided"
                     : "\(Format.age(profile.ageMonths)) — no \(Format.list(names))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            if isOn {
                Image(systemName: "checkmark").foregroundStyle(Tone.brand).font(.headline)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])

        /* What a parent wants to know first: the children, then the rest. */
        if let t = tally, t.total > 0 {
            HStack(spacing: 16) {
                TallyItem(count: t.asIs, label: "as is", color: Tone.yes)
                TallyItem(count: t.adapted, label: "adapted", color: Tone.swap)
                if t.blocked > 0 {
                    TallyItem(count: t.blocked, label: "blocked", color: Tone.no)
                }
                Spacer()
            }
            .padding(.top, 2)
            .padding(.bottom, 4)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(t.asIs) recipes as is, \(t.adapted) adapted, \(t.blocked) blocked")
        }
    }
}

/// One figure with its label. Small, quiet, and the number carries the weight.
private struct TallyItem: View {
    let count: Int
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Text("\(count)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

struct ProfileEditor: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var fermer
    @State var profile: ChildProfile
    @State private var showAllAllergens = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 9) {
                        FieldLabel("First name")
                        TextField("First name", text: $profile.name)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .font(.title3.weight(.semibold))
                            .padding(14)
                            .background(Tone.surface,
                                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 9) {
                        FieldLabel("Age")
                        AgePicker(ageMonths: $profile.ageMonths)
                    }

                    VStack(alignment: .leading, spacing: 9) {
                        FieldLabel("Allergens avoided")
                        AllergenGrid(selection: $profile.allergens,
                                         showAllAllergens: $showAllAllergens,
                                         allergens: app.knownAllergens)
                    }
                }
                .padding(20)
            }
            .background(Tone.canvas.ignoresSafeArea())
            .navigationTitle(profile.name.isEmpty ? "New child" : profile.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if profile.name.trimmingCharacters(in: .whitespaces).isEmpty {
                            profile.name = String(localized: "My child")
                        }
                        app.save(profile)
                        fermer()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { fermer() }
                }
            }
        }
    }
}

struct FieldLabel: View {
    let texte: String
    init(_ texte: String) { self.texte = texte }

    var body: some View {
        Text(texte)
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .kerning(1.2)
            .foregroundStyle(.tertiary)
    }
}

// MARK: - Settings

struct SettingsScreen: View {
    @Environment(AppState.self) private var app
    @State private var showPaywall = false
    @State private var reminderOn = WeeklyReminder.enabled
    @State private var showAbout = false
    @State private var email = ""
    @State private var accountMessage: String?

    /* A single body holding all five defeats the type checker — "unable to
     * type-check in reasonable time" is what a 200-line ViewBuilder earns. */
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                /* Family, not settings: the core object of the app — who the
                 * cooking is for — was filed as a technical preference. */
                Text("Family")
                    .scaledFont(Type.display)
                    .foregroundStyle(Tone.text)
                    .padding(.top, 8)

                childrenSection
                subscriptionSection
                appearanceSection
                contentSection
                footnotes
            }
            .padding(.horizontal, Layout.gutter)
            .padding(.bottom, 130)
        }
        .background(Tone.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        /* The field is the same modifier Recipes and Shopping use; it carries
         * no pill here because this screen names the children in a section of
         * its own. */
        .softTopBar { EmptyView() }
        .sheet(isPresented: $showPaywall) { PaywallScreen() }
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Appearance").eyebrow().padding(.top, 26).padding(.bottom, 9)
            HStack {
                Text("Theme")
                    .scaledFont(Type.secondary)
                    .foregroundStyle(Tone.text)
                Spacer(minLength: 10)
                ThemeSegments(theme: Binding(get: { app.theme },
                                             set: { app.theme = $0 }))
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 14)
            .card()

            Text("Auto follows your iPhone, including the switch at sunset.")
                .scaledFont(Type.label)
                .foregroundStyle(Tone.text3)
                .padding(.horizontal, 5)
                .padding(.top, 9)
        }
    }

    private var childrenSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Children").eyebrow().padding(.top, 26).padding(.bottom, 9)
            VStack(spacing: 0) {
                ForEach(app.profiles) { p in
                    NavigationLink { ProfilesScreen() } label: {
                        SettingRow(title: p.firstName, value: childSummary(p))
                    }
                    .buttonStyle(.plain)
                    Divider().overlay(Tone.hairline).padding(.leading, 15)
                }
                NavigationLink { ProfilesScreen() } label: {
                    SettingRow(title: "Add a child", value: "+", accent: true)
                }
                .buttonStyle(.plain)
            }
            .card()
        }
    }

    private var subscriptionSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Subscription").eyebrow().padding(.top, 26).padding(.bottom, 9)
            Button { showPaywall = true } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(app.subscribed ? "Active" : "Weeks ahead")
                            .scaledFont(Type.body)
                            .foregroundStyle(Tone.text)
                        Text("7 new recipes every week")
                            .scaledFont(Type.caption)
                            .foregroundStyle(Tone.text2)
                    }
                    Spacer(minLength: 10)
                    Text(app.subscribed ? "Manage" : "Subscribe")
                        .scaledFont(Type.secondary, weight: .semibold)
                        .foregroundStyle(Tone.brand)
                }
                .padding(15)
            }
            .buttonStyle(.plain)
            .card()
        }
    }

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Content").eyebrow().padding(.top, 26).padding(.bottom, 9)
            VStack(spacing: 0) {
                SettingRow(title: "Recipes available", value: "\(app.recipes.count)")
                Divider().overlay(Tone.hairline).padding(.leading, 15)
                Button { Task { await app.sync() } } label: {
                    SettingRow(title: "Refresh", value: app.lastSyncLabel, accent: true)
                }
                .buttonStyle(.plain)
                Divider().overlay(Tone.hairline).padding(.leading, 15)
                /* One local notification, Monday morning. Off until asked. */
                Toggle(isOn: Binding(
                    get: { reminderOn },
                    set: { on in
                        Task {
                            if on {
                                reminderOn = await WeeklyReminder.enable(firstName: app.activeProfile.firstName)
                            } else {
                                WeeklyReminder.disable(); reminderOn = false
                            }
                        }
                    })) {
                    SettingRow(title: "Monday reminder", value: "")
                }
                .tint(Tone.brand)
                .padding(.trailing, 15)
            }
            .card()
        }
    }

    /// One row instead of two paragraphs. The notices live in About, where
    /// the App Store ones will go too.
    private var footnotes: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { showAbout = true } label: {
                SettingRow(title: "About & notices", value: "")
            }
            .buttonStyle(.plain)
            .card()
            Text("Your children's profiles stay on this device and are never sent anywhere.")
                .scaledFont(Type.label)
                .foregroundStyle(Tone.text3)
                .lineSpacing(2)
                .padding(.horizontal, 5)
                .padding(.top, 16)
        }
        .padding(.top, 20)
        .sheet(isPresented: $showAbout) { AboutScreen() }
    }

    private func childSummary(_ p: ChildProfile) -> String {
        let n = p.allergens.count
        if n == 0 { return Format.age(p.ageMonths) }
        return Format.age(p.ageMonths) + " · " +
            String(format: String(localized: "%lld allergens"), n)
    }
}

// MARK: - Paywall

struct PaywallScreen: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var fermer

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(app.subscribed ? "Your subscription is active" : "Weeks ahead")
                            .scaledFont(Type.display, weight: .heavy, design: .rounded)
                        Text(app.subscribed
                             ? "Every week is open. The next one arrives Monday."
                             : "Seven new recipes every Monday, adapted to your children.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    comparison

                    if !app.subscribed {
                        if app.subscription.products.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Subscriptions aren’t available here.")
                                    .font(.subheadline.weight(.semibold))
                                Text("That’s expected on a build installed outside the App Store: in-app purchase requires a profile signed by Apple.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(15)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Tone.swap.opacity(0.12),
                                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        } else {
                            ForEach(app.subscription.products, id: \.id) { product in
                                ProductButton(product: product) {
                                    if let jws = await app.subscription.purchase(product) {
                                        await app.linkPurchase(jws)
                                    }
                                }
                            }
                        }
                    }

                    Button("Restore purchases") {
                        Task { await app.subscription.restore() }
                    }
                    .font(.footnote)
                    .tint(Tone.brand)

                    if let m = app.subscription.message {
                        Text(m).font(.footnote).foregroundStyle(Tone.swap)
                    }

                    Text("""
                    The subscription renews automatically unless cancelled at least 24 hours before the period ends. \
                    Payment is charged to your Apple account on confirmation. Manage or cancel it in your Apple account settings.
                    """)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    HStack(spacing: 18) {
                        Link("Terms", destination: Settings.terms)
                        Link("Privacy", destination: Settings.privacy)
                    }
                    .font(.caption)
                }
                .padding(20)
            }
            .background(Tone.canvas.ignoresSafeArea())
            .navigationTitle("Subscription")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { fermer() }
                }
            }
        }
        .task { await app.subscription.load() }
    }

    /// Two columns: what is free, what the subscription adds. Weekly, since
    /// the rolling window; the old copy still said monthly.
    private var comparison: some View {
        HStack(alignment: .top, spacing: 10) {
            ComparisonBlock(title: "Free", figure: "15", figureLabel: "recipes, forever",
                            accent: Tone.yes, lines: [
                "Swaps for every allergen",
                "Age and texture guidance",
                "The product scanner",
                "Shopping list",
                "Last week's recipes"
            ])
            ComparisonBlock(title: "Weeks ahead", figure: "+7", figureLabel: "every Monday",
                            accent: Tone.brand, lines: [
                "Everything free has",
                "New recipes every week",
                "Adapted to your children",
                "Three weeks open at once",
                "Next week, before it starts"
            ])
        }
    }
}

struct ComparisonBlock: View {
    let title: String
    let figure: String
    let figureLabel: String
    let accent: Color
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).eyebrow(accent)
            Text(figure)
                .scaledFont(Type.title, weight: .bold)
                .foregroundStyle(Tone.text)
                .padding(.top, 2)
            Text(figureLabel)
                .scaledFont(Type.label)
                .foregroundStyle(Tone.text2)
            VStack(alignment: .leading, spacing: 5) {
                ForEach(lines, id: \.self) { l in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "checkmark")
                            .scaledFont(Type.micro, weight: .bold)
                            .foregroundStyle(accent)
                            .padding(.top, 3)
                        Text(l)
                            .scaledFont(Type.label)
                            .foregroundStyle(Tone.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.top, 8)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(accent.opacity(0.25), lineWidth: 1)
        }
    }
}

struct ProductButton: View {
    let product: Product
    let action: () async -> Void
    @State private var isWorking = false

    var body: some View {
        Button {
            Task {
                isWorking = true
                await action()
                isWorking = false
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(product.displayName).font(.headline)
                    Text(product.description).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                if isWorking {
                    ProgressView()
                } else {
                    Text(product.displayPrice).font(.headline)
                }
            }
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .tint(Tone.brand)
        .disabled(isWorking)
    }
}

// MARK: - Settings pieces

/// Three states in one control. A Picker with .segmented brings the system's
/// own chrome, which does not match the rest of the app.
struct ThemeSegments: View {
    @Binding var theme: AppTheme

    var body: some View {
        HStack(spacing: 5) {
            ForEach(AppTheme.allCases, id: \.self) { t in
                Segment(theme: t, selected: theme == t) {
                    withAnimation(.soft(0.22)) { theme = t }
                }
            }
        }
        .padding(4)
        .background(Tone.text.opacity(0.05),
                    in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

private struct Segment: View {
    let theme: AppTheme
    let selected: Bool
    let tap: () -> Void

    var body: some View {
        Button(action: tap) {
            Text(theme.label)
                .scaledFont(Type.caption, weight: .semibold)
                .foregroundStyle(selected ? Tone.canvas : Tone.text2)
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Tone.text)
                            .shadow(color: .black.opacity(0.3), radius: 5, y: 2)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

struct SettingRow: View {
    let title: String
    let value: String
    var accent = false

    var body: some View {
        HStack {
            Text(title)
                .scaledFont(Type.body)
                .foregroundStyle(accent ? Tone.brand : Tone.text)
            Spacer(minLength: 10)
            Text(value)
                .scaledFont(Type.secondary)
                .foregroundStyle(Tone.text2)
        }
        .padding(15)
        .contentShape(Rectangle())
    }
}

/// The notices, in one place: safety, photos, data, licences.
struct AboutScreen: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("About").scaledFont(Type.display).foregroundStyle(Tone.text)

                section("Safety", Settings.medicalDisclaimer)
                section("Photos", String(localized: """
                    Recipe photos are illustrations and may be improved by AI. \
                    They can differ from what you make.

                    The ingredients, the quantities and the allergen verdict never \
                    come from a photo — they come from the recipe itself.
                    """))
                section("Your data", String(localized:
                    "Your children's profiles stay on this device and are never sent anywhere."))
                section("Licences", String(localized: """
                    Product data: Open Food Facts (ODbL) and USDA FoodData Central (CC0).
                    """))

                Link("Terms", destination: Settings.terms)
                    .scaledFont(Type.caption, weight: .semibold)
                    .foregroundStyle(Tone.brand)
                    .padding(.top, 18)
                Link("Privacy", destination: Settings.privacy)
                    .scaledFont(Type.caption, weight: .semibold)
                    .foregroundStyle(Tone.brand)
                    .padding(.top, 8)
            }
            .padding(.horizontal, Layout.gutter)
            .padding(.top, 26)
            .padding(.bottom, 40)
        }
        .background(Tone.canvas.ignoresSafeArea())
        .presentationDragIndicator(.visible)
    }

    private func section(_ heading: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(heading).eyebrow()
            Text(body)
                .scaledFont(Type.caption)
                .foregroundStyle(Tone.text2)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .background(Tone.text.opacity(0.04),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.top, 18)
    }
}
