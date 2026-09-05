// ProfilesAndSettings.swift
// Children's profiles stay on the device, which is what the App Store
// privacy labels declare; nothing here sends them anywhere.

import SwiftUI
import StoreKit
import UIKit

// MARK: - Profiles

struct ProfileEditor: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var fermer
    @State var profile: ChildProfile
    /// False for a child not saved yet: there is nothing to remove.
    var canRemove = false
    @State private var confirmRemove = false

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
                        /* The onboarding's pad, not a second grid: the same
                         * cells, glyphs and brand selection on both screens. */
                        AllergenPad(selected: $profile.allergens, families: app.knownAllergens)
                    }

                    if canRemove {
                        Button(role: .destructive) { confirmRemove = true } label: {
                            Text("Remove this child")
                                .scaledFont(Type.body, weight: .medium)
                                .frame(maxWidth: .infinity)
                                .frame(height: Layout.tapTarget)
                        }
                        .foregroundStyle(Tone.no)
                        .background(Tone.no.opacity(0.08),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding(.top, 8)
                    }
                }
                .padding(20)
            }
            .background(Tone.canvas.ignoresSafeArea())
            .alert("Remove this profile?", isPresented: $confirmRemove) {
                Button("Remove", role: .destructive) { app.remove(profile); fermer() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The week and the shopping list will be rebuilt for the children who remain.")
            }
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
    @State private var showSettings = false
    @State private var showDemo = false
    @State private var editing: ChildProfile?
    @State private var hauteurReglages: CGFloat = 0
    @State private var reminderOn = WeeklyReminder.enabled
    @State private var email = ""
    @State private var accountMessage: String?

    /* A single body holding all five defeats the type checker — "unable to
     * type-check in reasonable time" is what a 200-line ViewBuilder earns. */
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                /* Family, not settings: the core object of the app — who the
                 * cooking is for — was filed as a technical preference. */
                HStack(alignment: .center) {
                    Text("Family")
                        .scaledFont(Type.display)
                        .foregroundStyle(Tone.text)
                    Spacer(minLength: 8)
                    /* Settings behind a gear: the tab is about the children,
                     * and its first section used to be the phone's theme. */
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                            .scaledFont(Type.heading, weight: .semibold)
                            .foregroundStyle(Tone.text)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .glass(Circle())
                    .accessibilityLabel(Text("Settings"))
                }
                .padding(.top, 8)

                childrenSection
                tableSection
            }
            .padding(.horizontal, Layout.gutter)
            .padding(.bottom, 130)
        }
        .background(Tone.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .softTopBar { EmptyView() }
        .sheet(isPresented: $showPaywall) { PaywallScreen() }
        .sheet(isPresented: $showSettings) { settingsSheet }
    }

    /// Appearance, subscription, content, the demo, about — one sheet, sized
    /// to its content like About.
    private var settingsSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    /* Same title, same distance from the handle, as About. */
                    Text("Settings").scaledFont(Type.display).foregroundStyle(Tone.text)
                    appearanceSection
                    subscriptionSection
                    contentSection
                    demoSection
                    footnotes
                }
                .padding(.horizontal, Layout.gutter)
                .padding(.top, 26)
                .padding(.bottom, 24)
                .background {
                    GeometryReader { geo in
                        Color.clear.onAppear { hauteurReglages = geo.size.height }
                            .onChange(of: geo.size.height) { _, h in hauteurReglages = h }
                    }
                }
            }
            .background(Tone.canvas.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        /* Sized to its content, like About. */
        .presentationDetents(hauteurReglages > 0
            ? [.height(min(max(hauteurReglages, 320), UIScreen.main.bounds.height * 0.92)), .large]
            : [.medium, .large])
        .presentationDragIndicator(.visible)
    }

    /// Replay the demo and the week — for a partner, or after skipping it.
    private var demoSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("The demo").eyebrow().padding(.top, 26).padding(.bottom, 9)
            Button { showDemo = true } label: {
                SettingRow(title: "Replay the demo", value: "")
            }
            .buttonStyle(.plain)
            .card()
        }
        .fullScreenCover(isPresented: $showDemo) { ReplayDemo(done: { showDemo = false }) }
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
            Text("Your children").eyebrow().padding(.top, 26).padding(.bottom, 9)
            ForEach(Array(app.profiles.enumerated()), id: \.element.id) { i, p in
                /* Straight to this child's editor: the list in between
                 * repeated the children and offered "add" a second time. */
                Button { editing = p } label: {
                    ChildCard(profile: p, index: i, figures: app.figures(for: p), summary: childSummary(p))
                }
                .buttonStyle(.plain)
                .padding(.bottom, 8)
            }
            Button { editing = .defaut } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus").scaledFont(Type.secondary, weight: .semibold)
                    Text("Add a child").scaledFont(Type.secondary, weight: .semibold)
                }
                .foregroundStyle(Tone.brand)
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
        }
        .sheet(item: $editing) { p in
            ProfileEditor(profile: p, canRemove: app.profiles.contains { $0.id == p.id })
        }
    }

    /// One week that works for everyone: the youngest age, every allergen,
    /// and the real count of recipes that serve all of them.
    @ViewBuilder
    private var tableSection: some View {
        if app.profiles.count > 1 {
            let t = app.tableFigures
            VStack(alignment: .leading, spacing: 0) {
                Text("Everyone at the table").eyebrow().padding(.top, 26).padding(.bottom, 9)
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(isOn: Binding(get: { app.familyMode }, set: { _ in app.toggleFamilyMode() })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(format: String(localized: "Cook for all %lld"), app.profiles.count))
                                .scaledFont(Type.body, weight: .medium).foregroundStyle(Tone.text)
                            Text("One week that works for everyone: the youngest age, every allergen combined.")
                                .scaledFont(Type.caption).foregroundStyle(Tone.text2)
                        }
                    }
                    .tint(Tone.brand)
                    HStack(spacing: 4) {
                        Chip(text: String(format: String(localized: "%lld MONTHS"), t.youngestMonths), tone: Tone.text, tint: Tone.text.opacity(0.08))
                        ForEach(t.allergens, id: \.self) { a in
                            Chip(text: String(localized: "NO ") + app.allergenName(a).uppercased(), tone: Tone.swap, tint: Tone.swap.opacity(0.12))
                        }
                    }
                    .lineLimit(1)
                    HStack(spacing: 6) {
                        Figure(value: t.safeForAll, label: String(localized: "SAFE FOR ALL"), tone: Tone.text)
                        Figure(value: t.needASwap, label: String(localized: "NEED A SWAP"), tone: Tone.swap)
                    }
                }
                .padding(13)
                .card()
            }
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
            /* Pushed inside the settings sheet, not a second sheet on top:
             * one sheet, two pages. The recipe page still opens About as a
             * sheet, where it is the only one. */
            NavigationLink { AboutScreen(pushed: true) } label: {
                SettingRow(title: "About & notices", value: "")
            }
            .buttonStyle(.plain)
            .card()
        }
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

// MARK: - Family cards

/// One child, with the figures the app already knows about them.
private struct ChildCard: View {
    let profile: ChildProfile
    let index: Int
    let figures: AppState.ChildFigures
    let summary: String

    /* Brand, amber, green, in order of adding: told apart at a glance. */
    private var avatar: Color { [Tone.brand, Tone.swap, Tone.yes][index % 3] }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 10) {
                Text(String(profile.firstName.prefix(1)).uppercased())
                    .scaledFont(Type.body, weight: .bold)
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(avatar, in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(profile.firstName).scaledFont(Type.body, weight: .semibold).foregroundStyle(Tone.text)
                    Text(summary).scaledFont(Type.caption).foregroundStyle(Tone.text2)
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right").scaledFont(Type.caption, weight: .semibold).foregroundStyle(Tone.text3)
            }
            HStack(spacing: 6) {
                Figure(value: figures.safeToday, label: String(localized: "SAFE TODAY"), tone: Tone.text)
                Figure(value: figures.asIsThisWeek, label: String(localized: "AS IS"), tone: Tone.yes)
                Figure(value: figures.adaptedThisWeek, label: String(localized: "ADAPTED"), tone: Tone.swap)
            }
            if let m = figures.nextMilestone, figures.unlockedAtMilestone > 0 {
                ligne("arrow.up", Tone.brand,
                      String(format: String(localized: "At %lld months, "), m),
                      String(format: String(localized: "%lld more recipes open up."), figures.unlockedAtMilestone))
            } else if figures.nextMilestone == nil {
                ligne("checkmark", Tone.yes, String(localized: "Every age rule is behind them. "),
                      String(localized: "Nothing left to unlock."))
            }
            if figures.plannedThisWeek > 0 {
                ligne("checkmark", Tone.text3, String(localized: "Cooked this week: "),
                      String(format: String(localized: "%lld of %lld"), figures.cookedThisWeek, figures.plannedThisWeek))
            }
        }
        .padding(13)
        .card()
    }

    private func ligne(_ symbole: String, _ tone: Color, _ fort: String, _ suite: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbole)
                .scaledFont(Type.label)
                .foregroundStyle(tone)
                .frame(width: 24, height: 24)
                .background(tone.opacity(0.10), in: Circle())
            (Text(fort).foregroundStyle(Tone.text) + Text(suite).foregroundStyle(Tone.text2))
                .scaledFont(Type.secondary)
        }
    }
}

/// A big number over a small label, the app's tally style.
private struct Figure: View {
    let value: Int
    let label: String
    let tone: Color

    var body: some View {
        VStack(spacing: 2) {
            Text("\(value)").scaledFont(Type.heading, weight: .bold).foregroundStyle(tone).monospacedDigit()
            Text(label).scaledFont(Type.micro, weight: .semibold).foregroundStyle(Tone.text2).kerning(0.4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Tone.canvas.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct Chip: View {
    let text: String
    let tone: Color
    let tint: Color

    var body: some View {
        Text(text)
            .scaledFont(Type.micro, weight: .bold)
            .foregroundStyle(tone)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(tint, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
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
    /// True when reached by a push, where the page needs its own way back.
    var pushed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    if pushed {
                        Button { dismiss() } label: {
                            Image(systemName: "chevron.left")
                                .scaledFont(Type.secondary, weight: .semibold)
                                .foregroundStyle(Tone.text)
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.plain)
                        .glass(Circle())
                        .accessibilityLabel(Text("Back"))
                    }
                    Text("About").scaledFont(Type.display).foregroundStyle(Tone.text)
                }

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

                HStack(spacing: 22) {
                    Link("Terms", destination: Settings.terms)
                    Link("Privacy", destination: Settings.privacy)
                }
                .scaledFont(Type.body, weight: .semibold)
                .foregroundStyle(Tone.brand)
                .padding(.top, 20)
            }
            .padding(.horizontal, Layout.gutter)
            .padding(.top, 26)
            .padding(.bottom, 34)
            .background {
                GeometryReader { geo in
                    Color.clear.onAppear { hauteur = geo.size.height }
                        .onChange(of: geo.size.height) { _, h in hauteur = h }
                }
            }
        }
        .background(Tone.canvas.ignoresSafeArea())
        /* Sized to its content, like the other sheets. */
        .presentationDetents(hauteur > 0
            ? [.height(min(max(hauteur, 320), UIScreen.main.bounds.height * 0.92)), .large]
            : [.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @State private var hauteur: CGFloat = 0

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
