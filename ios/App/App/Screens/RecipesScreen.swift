//  RecipesScreen.swift
//
//  THE ANSWER FIRST, THE LIST SECOND.
//
//  420pt of photograph fading into the canvas over 290, the context header and
//  the verdict floating on glass above it, then three figures — one of them a
//  zero — and a list read with one thumb.
//
//  Measured on the corpus: whatever the profile, the engine finds a way. A
//  child avoiding milk, egg, peanut, wheat and soy keeps every recipe. "0
//  blocked" is the strongest fact in the product and nothing used to show it.

import SwiftUI

struct RecipesScreen: View {
    var tab: Binding<Int>?
    @Environment(AppState.self) private var etat

    @State private var filter: RecipeFilter = .all
    @State private var openRecipeID: String?
    @State private var showPaywall = false

    private var profile: ChildProfile { etat.activeProfile }
    private var tally: AppState.ProfileTally { etat.tally(for: profile) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    bento
                    if let message = etat.syncMessage {
                        MessageBanner(texte: message)
                            .padding(.horizontal, Layout.gutter)
                            .padding(.top, 18)
                    }
                    CountedSegments(selection: $filter, tally: tally,
                                    savedCount: etat.saved.recipes.count)
                        .padding(.top, 24)
                    list
                    locked
                    disclaimer
                }
                .padding(.bottom, 130)
            }
            .background(Tone.canvas.ignoresSafeArea())
            .ignoresSafeArea(.container, edges: .top)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $openRecipeID) { id in
                if let pair = etat.pairFor(pour: id) {
                    RecipeDetailScreen(recipe: pair.recipe, result: pair.result,
                                       firstName: profile.firstName)
                }
            }
            .sheet(isPresented: $showPaywall) { PaywallScreen() }
            .refreshable { await etat.sync() }
        }
    }

    // MARK: - Bento

    /* A SINGLE COLUMN FORCES FOUR QUESTIONS INTO A SEQUENCE.
     *
     * Who am I cooking for, how many recipes work, what do I make tonight,
     * can I scan something. A bento answers all four at a glance, with size
     * as the hierarchy — the pattern 2026 settled on, measured at 23% more
     * scroll depth than a uniform grid.
     *
     * And the name is not decoration: a bento is a lunch box with
     * compartments. For an app about children's meals it is the right
     * metaphor before it is the right layout.
     */
    private var bento: some View {
        VStack(spacing: 11) {
            heroTile
            HStack(spacing: 11) {
                countTile
                scanTile
            }
            childStrip
        }
        .padding(.horizontal, 16)
        .padding(.top, 66)
    }

    @ViewBuilder
    private var heroTile: some View {
        if let h = heroPair {
            Button { openRecipeID = h.recipe.id } label: {
                ZStack(alignment: .bottomLeading) {
                    RecipeVisual(recipe: h.recipe, result: h.result)
                        .frame(height: 300)
                        .frame(maxWidth: .infinity)
                        .clipped()

                    LinearGradient(
                        stops: [.init(color: .black.opacity(0.32), location: 0),
                                .init(color: .clear, location: 0.30),
                                .init(color: .clear, location: 0.40),
                                .init(color: Tone.canvas.opacity(0.78), location: 0.82),
                                .init(color: Tone.canvas.opacity(0.96), location: 1)],
                        startPoint: .top, endPoint: .bottom)

                    VStack(alignment: .leading, spacing: 0) {
                        Text("Tonight").eyebrow(Tone.brand)
                        Text(h.recipe.name)
                            .font(.system(size: 29, weight: .bold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.leading)
                            .shadow(color: .black.opacity(0.55), radius: 18)
                            .padding(.top, 8)
                        Text(h.recipe.subtitle)
                            .font(.system(size: 12.5))
                            .foregroundStyle(.white.opacity(0.72))
                            .padding(.top, 7)
                        VerdictPill(result: h.result, firstName: profile.firstName)
                            .padding(.top, 13)
                    }
                    .padding(22)
                }
                .frame(height: 300)
                .clipShape(RoundedRectangle(cornerRadius: Layout.tileRadius, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    /// The 38 and the 0, together. Those two numbers are the whole promise of
    /// the product, and nothing used to show the zero at all.
    private var countTile: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(tally.total)")
                .font(.system(size: 52, weight: .bold))
                .foregroundStyle(Tone.yes)
                .contentTransition(.numericText())

            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("\(tally.blocked)")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(tally.blocked == 0 ? Tone.text3 : Tone.no)
                Text("blocked")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Tone.text3)
            }
            .padding(.top, 11)
            .overlay(alignment: .top) {
                Rectangle().fill(Tone.hairline).frame(height: 1).offset(y: -5)
            }

            Spacer(minLength: 12)

            Text(String(format: String(localized: "recipes for %@ today"), profile.firstName))
                .font(.system(size: 12.5))
                .foregroundStyle(Tone.text2)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 148, alignment: .top)
        .padding(20)
        .tile()
    }

    /// An action, not a statistic — hence the brand gradient. It doubles the
    /// tab because scanning is the gesture you make standing in an aisle, and
    /// it deserves a 148pt target rather than an 11pt label.
    private var scanTile: some View {
        Button { tab?.wrappedValue = 1 } label: {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: "barcode.viewfinder")
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .fill(Tone.brandGradient)
                            .shadow(color: Tone.brandDeep.opacity(0.42), radius: 10, y: 6)
                    }

                Spacer(minLength: 14)

                Text("Scan")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Tone.text)
                Text("A product at the store")
                    .font(.system(size: 12))
                    .foregroundStyle(Tone.text2)
                    .padding(.top, 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 148, alignment: .top)
            .padding(20)
            .background {
                RoundedRectangle(cornerRadius: Layout.tileRadius, style: .continuous)
                    .fill(LinearGradient(colors: [Tone.brand.opacity(0.14), Tone.brand.opacity(0.04)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay {
                        RoundedRectangle(cornerRadius: Layout.tileRadius, style: .continuous)
                            .strokeBorder(Tone.brand.opacity(0.20), lineWidth: 1)
                    }
            }
        }
        .buttonStyle(.plain)
    }

    /// Full width, because who you are cooking for is a state, not one choice
    /// among several.
    private var childStrip: some View {
        CookingContextHeader(onDark: false)
            .frame(maxWidth: .infinity)
            .tile()
    }

    // MARK: - List

    private var list: some View {
        LazyVStack(spacing: 0) {
            if !rows.isEmpty {
                Text("Also today").eyebrow()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Layout.gutter)
                    .padding(.top, 26)
                    .padding(.bottom, 4)
            }

            ForEach(rows, id: \.recipe.id) { pair in
                Button { openRecipeID = pair.recipe.id } label: {
                    RecipeRow(recipe: pair.recipe, result: pair.result)
                }
                .buttonStyle(.plain)

                Divider().overlay(Tone.hairline)
                    .padding(.leading, Layout.gutter + Layout.thumb + 15)
            }

            if rows.isEmpty {
                EmptyState(symbol: "magnifyingglass",
                           title: "Nothing matches",
                           message: "Try another filter.")
                    .padding(.top, 44)
            }
        }
    }

    // MARK: - Data

    private var pairs: [(recipe: Recipe, result: AdaptedRecipe)] { etat.pairs }

    private var heroPair: (recipe: Recipe, result: AdaptedRecipe)? {
        guard filter == .all else { return nil }
        return pairs.first { $0.result.status == .asIs && ($0.recipe.timeMinutes ?? 99) <= 40 }
            ?? pairs.first { $0.result.status == .asIs }
            ?? pairs.first
    }

    private var rows: [(recipe: Recipe, result: AdaptedRecipe)] {
        let base: [(recipe: Recipe, result: AdaptedRecipe)]
        switch filter {
        case .all:   base = pairs
        case .ready: base = pairs.filter { $0.result.status == .asIs }
        case .swaps: base = pairs.filter { $0.result.status == .adapted }
        case .saved:
            let ids = Set(etat.saved.recipes.map(\.id))
            base = pairs.filter { ids.contains($0.recipe.id) }
        }
        guard let h = heroPair else { return base }
        return base.filter { $0.recipe.id != h.recipe.id }
    }

    // MARK: - Tail

    @ViewBuilder
    private var locked: some View {
        let batches = etat.lockedBatches
        if !batches.isEmpty {
            Button { showPaywall = true } label: {
                HStack(spacing: 13) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Tone.brand)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(batches.reduce(0) { $0 + $1.count }) more recipes")
                            .font(.system(size: 15.5, weight: .semibold))
                            .foregroundStyle(Tone.text)
                        Text("7 new ones every week")
                            .font(Type.small)
                            .foregroundStyle(Tone.text2)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Tone.text3)
                }
                .padding(16)
                .card()
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Layout.gutter)
            .padding(.top, 28)
        }
    }

    private var disclaimer: some View {
        Text(Settings.medicalDisclaimer)
            .font(.system(size: 11.5))
            .foregroundStyle(Tone.text3)
            .lineSpacing(2)
            .padding(.horizontal, Layout.gutter)
            .padding(.top, 32)
    }
}

// MARK: - Pieces

/// One figure and its label, in a gradient card. The number carries the weight.
struct Figure: View {
    let value: Int
    let label: LocalizedStringKey
    let tone: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(value)")
                .font(Type.figure)
                .foregroundStyle(tone)
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Tone.text2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 15)
        .padding(.vertical, 14)
        .card(19)
        .accessibilityElement(children: .combine)
    }
}

/// The verdict over a photo. Glass, because it floats above content.
struct VerdictPill: View {
    let result: AdaptedRecipe
    let firstName: String

    var body: some View {
        HStack(spacing: 8) {
            VerdictMark(status: result.status)
            Text(phrase)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(.white)
        }
        .padding(.leading, 13)
        .padding(.trailing, 16)
        .padding(.vertical, 9)
        .glass(Capsule())
    }

    private var phrase: String {
        switch result.status {
        case .asIs: return String(localized: "Ready as is")
        case .adapted:
            let n = result.swapCount
            return String(format: n > 1 ? String(localized: "Yes — %lld swaps")
                                        : String(localized: "Yes — %lld swap"), n)
        case .notAdaptable:
            return String(format: String(localized: "Not this one for %@"), firstName)
        case .unknown: return String(localized: "Needs checking")
        }
    }
}

/// A row, not a card. 62pt thumbnail, name, meta, verdict.
struct RecipeRow: View {
    let recipe: Recipe
    let result: AdaptedRecipe

    var body: some View {
        HStack(spacing: 15) {
            RecipeVisual(recipe: recipe, result: result)
                .frame(width: Layout.thumb, height: Layout.thumb)
                .clipShape(RoundedRectangle(cornerRadius: Layout.thumbRadius, style: .continuous))
                .shadow(color: .black.opacity(0.4), radius: 7, y: 4)
                .saturation(result.status == .notAdaptable ? 0.3 : 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.name)
                    .font(Type.title)
                    .foregroundStyle(Tone.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(recipe.subtitle)
                    .font(Type.small)
                    .foregroundStyle(Tone.text2)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            HStack(spacing: 7) {
                VerdictMark(status: result.status)
                Text(short)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(result.status.tone)
            }
        }
        .padding(.horizontal, Layout.gutter)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// The number says how much work. An adjective says nothing.
    private var short: String {
        switch result.status {
        case .asIs: return String(localized: "Yes")
        case .adapted: return "\(result.swapCount)"
        case .notAdaptable: return String(localized: "No")
        case .unknown: return "?"
        }
    }
}
