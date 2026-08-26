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
                            .tint(Tint.betterave)
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
                            .tint(Tint.betterave)
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
        let teintes: [Color] = [Tint.betterave, Tint.pois, Tint.courge, Tint.canneberge]
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
                Image(systemName: "checkmark").foregroundStyle(Tint.betterave).font(.headline)
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
                TallyItem(count: t.asIs, label: "as is", color: Tint.pois)
                TallyItem(count: t.adapted, label: "adapted", color: Tint.courge)
                if t.blocked > 0 {
                    TallyItem(count: t.blocked, label: "blocked", color: Tint.canneberge)
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
            .background(Tint.background.ignoresSafeArea())
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

    var body: some View {
        NavigationStack {
            List {
                Section("Subscription") {
                    HStack {
                        Text(etat.subscribed ? "Active" : "No subscription")
                        Spacer()
                        Button(etat.subscribed ? "Manage" : "Subscribe") { showPaywall = true }
                            .tint(Tint.betterave)
                    }
                    Button("Restore purchases") {
                        Task { await etat.subscription.restore() }
                    }
                }

                Section {
                    if let c = etat.subscription.email {
                        HStack {
                            Text("Signed in")
                            Spacer()
                            Text(c).foregroundStyle(.secondary).font(.footnote)
                        }
                        Button("Sign out", role: .destructive) {
                            Task { await etat.signOut() }
                        }
                    } else {
                        TextField("you@example.com", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Sign in") {
                            Task {
                                do {
                                    try await etat.signIn(email: email)
                                    accountMessage = nil
                                } catch {
                                    accountMessage = "Couldn’t sign in. Check the address and your connection."
                                }
                            }
                        }
                        .disabled(!email.contains("@"))
                    }
                    if let m = accountMessage {
                        Text(m).font(.footnote).foregroundStyle(Tint.canneberge)
                    }
                } header: {
                    Text("Account")
                } footer: {
                    Text("The account is only used to find your subscription across devices. Your children’s profiles stay on this device and are never sent anywhere.")
                }

                Section("Content") {
                    HStack {
                        Text("Last updated")
                        Spacer()
                        Text(etat.lastSync.map {
                            $0.formatted(date: .abbreviated, time: .shortened)
                        } ?? "never")
                            .foregroundStyle(.secondary)
                            .font(.footnote)
                    }
                    Button("Refresh now") {
                        Task { await etat.sync() }
                    }
                    HStack {
                        Text("Recipes available")
                        Spacer()
                        Text("\(etat.recipes.count)").foregroundStyle(.secondary).monospacedDigit()
                    }
                }

                Section {
                    Link("Terms of Use", destination: Settings.terms)
                    Link("Privacy", destination: Settings.privacy)
                } footer: {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(Settings.medicalDisclaimer)
                        Text("Product data: Open Food Facts, under the ODbL license.")
                    }
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showPaywall) { PaywallScreen() }
        }
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
                            .background(Tint.courge.opacity(0.12),
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
                    .tint(Tint.betterave)

                    if let m = etat.subscription.message {
                        Text(m).font(.footnote).foregroundStyle(Tint.courge)
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
            .background(Tint.background.ignoresSafeArea())
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
            ComparisonBlock(title: "Always free", accent: Tint.pois, lines: [
                "Ingredient swaps for every allergen",
                "Age and texture guidance",
                "The product scanner",
                "Your children’s profiles",
                "The starter recipes"
            ])
            ComparisonBlock(title: "With the subscription", accent: Tint.betterave, lines: [
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
        .tint(Tint.betterave)
        .disabled(isWorking)
    }
}
