//  ProfilsEtReglages.swift
//
//  Les profiles vivent sur l'appareil et n'en sortent jamais : aucune route
//  server receives them. That is what the App Store privacy labels declare,
//  and it has to stay true in the code.

import SwiftUI
import StoreKit

// MARK: - Profils

struct ProfilesScreen: View {
    @Environment(AppState.self) private var etat
    @State private var editing: ChildProfile?
    @State private var pendingDeletion: ChildProfile?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(etat.profiles) { p in
                        Button {
                            etat.select(p.id)
                        } label: {
                            ProfileRow(profile: p,
                                        isOn: !etat.familyMode && p.id == etat.activeProfileID,
                                        noms: etat.allergenNames(p.allergens),
                                        tally: etat.tally(for: p))
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

                if etat.profiles.count > 1 {
                    Section {
                        Toggle(isOn: Binding(
                            get: { etat.familyMode },
                            set: { _ in etat.toggleFamilyMode() })) {
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
                Button("Remove", role: .destructive) { etat.remove(p) }
                Button("Cancel", role: .cancel) { }
            } message: { p in
                Text("\(p.name)'s profile and their allergens will be erased from this device.")
            }
        }
    }
}

struct ProfileRow: View {
    let profile: ChildProfile
    let isOn: Bool
    let noms: [String]
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
                Text(noms.isEmpty
                     ? "\(Format.age(profile.ageMonths)) — no allergen avoided"
                     : "\(Format.age(profile.ageMonths)) — no \(Format.liste(noms))")
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

        /* What a parent actually wants to know, on the screen that used to be
         * empty below the first row: how much of the corpus this child can
         * eat, and how much of it needs work. */
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
    @Environment(AppState.self) private var etat
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
                            .background(Color(.secondarySystemGroupedBackground),
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
                                         allergens: etat.knownAllergens)
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
                        etat.save(profile)
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
    @Environment(AppState.self) private var etat
    @State private var showPaywall = false
    @State private var email = ""
    @State private var accountMessage: String?

    /* Dark cards on the canvas rather than a grouped List: a system List
     * brings its own background and its own insets, and neither matches the
     * rest of the app.
     *
     * Split into one property per section. A single body holding all five
     * defeats the type checker — "unable to type-check in reasonable time" is
     * what a 200-line ViewBuilder earns. */
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Settings")
                        .font(Type.display)
                        .foregroundStyle(Tone.text)
                        .padding(.top, 8)

                    appearanceSection
                    childrenSection
                    subscriptionSection
                    contentSection
                    footnotes
                }
                .padding(.horizontal, Layout.gutter)
                .padding(.bottom, 130)
            }
            .background(Tone.canvas.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showPaywall) { PaywallScreen() }
        }
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Appearance").eyebrow().padding(.top, 26).padding(.bottom, 9)
            HStack {
                Text("Theme")
                    .font(.system(size: 14.5))
                    .foregroundStyle(Tone.text)
                Spacer(minLength: 10)
                ThemeSegments(theme: Binding(get: { etat.theme },
                                             set: { etat.theme = $0 }))
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 14)
            .card()

            Text("Auto follows your iPhone, including the switch at sunset.")
                .font(.system(size: 11.5))
                .foregroundStyle(Tone.text3)
                .padding(.horizontal, 5)
                .padding(.top, 9)
        }
    }

    private var childrenSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Children").eyebrow().padding(.top, 26).padding(.bottom, 9)
            VStack(spacing: 0) {
                ForEach(etat.profiles) { p in
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
                        Text(etat.subscribed ? "Active" : "Weeks ahead")
                            .font(.system(size: 15))
                            .foregroundStyle(Tone.text)
                        Text("7 new recipes every week")
                            .font(Type.small)
                            .foregroundStyle(Tone.text2)
                    }
                    Spacer(minLength: 10)
                    Text(etat.subscribed ? "Manage" : "Subscribe")
                        .font(.system(size: 14.5, weight: .semibold))
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
                SettingRow(title: "Recipes available", value: "\(etat.recipes.count)")
                Divider().overlay(Tone.hairline).padding(.leading, 15)
                Button { Task { await etat.sync() } } label: {
                    SettingRow(title: "Refresh", value: etat.lastSyncLabel, accent: true)
                }
                .buttonStyle(.plain)
            }
            .card()
        }
    }

    private var footnotes: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Your children's profiles stay on this device and are never sent anywhere.")
            Text(Settings.medicalDisclaimer)
        }
        .font(.system(size: 11.5))
        .foregroundStyle(Tone.text3)
        .lineSpacing(2)
        .padding(.horizontal, 5)
        .padding(.top, 20)
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
    @Environment(AppState.self) private var etat
    @Environment(\.dismiss) private var fermer

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(etat.subscribed ? "Your subscription is active" : "New recipes every month")
                            .font(.system(size: 28, weight: .heavy, design: .rounded))
                        Text(etat.subscribed
                             ? "Every batch is unlocked. The next one arrives at the start of next month."
                             : "Every month, a batch of recipes chosen where your profile runs short — not at random.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    comparison

                    if !etat.subscribed {
                        if etat.subscription.products.isEmpty {
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
                            ForEach(etat.subscription.products, id: \.id) { product in
                                ProductButton(product: product) {
                                    if let jws = await etat.subscription.purchase(product) {
                                        await etat.linkPurchase(jws)
                                    }
                                }
                            }
                        }
                    }

                    Button("Restore purchases") {
                        Task { await etat.subscription.restore() }
                    }
                    .font(.footnote)
                    .tint(Tone.brand)

                    if let m = etat.subscription.message {
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
        .task { await etat.subscription.load() }
    }

    private var comparison: some View {
        VStack(spacing: 12) {
            ComparisonBlock(title: "Always free", accent: Tone.yes, lines: [
                "Ingredient swaps for every allergen",
                "Age and texture guidance",
                "The product scanner",
                "Your children’s profiles",
                "The starter recipes"
            ])
            ComparisonBlock(title: "With the subscription", accent: Tone.brand, lines: [
                "A new batch of recipes every month",
                "Targeted at the profiles you created",
                "Every previous batch"
            ])
        }
    }
}

struct ComparisonBlock: View {
    let title: String
    let accent: Color
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline).foregroundStyle(accent)
            ForEach(lines, id: \.self) { l in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(accent)
                        .padding(.top, 2)
                    Text(l).font(.footnote)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                    withAnimation(.smooth(duration: 0.22)) { theme = t }
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
                .font(.system(size: 12.5, weight: .semibold))
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
                .font(.system(size: 15))
                .foregroundStyle(accent ? Tone.brand : Tone.text)
            Spacer(minLength: 10)
            Text(value)
                .font(.system(size: 14))
                .foregroundStyle(Tone.text2)
        }
        .padding(15)
        .contentShape(Rectangle())
    }
}
