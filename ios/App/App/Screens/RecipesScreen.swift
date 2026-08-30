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
                    hero
                    counts
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
                .padding(.bottom, 20)
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

    // MARK: - Hero

    /* THE PHOTO LEADS. It is the essence of a recipe app, and it is also the
     * one thing here nobody else can produce: the image is generated from the
     * ADAPTED ingredient list, so a milk-free recipe shows a milk-free dish.
     *
     * 430pt, fading into the canvas with no seam. The child picker and the
     * verdict float on glass over it — the only two glass elements on this
     * screen, both in the navigation layer where the material belongs. */
    @ViewBuilder
    private var hero: some View {
        if let h = heroPair {
            Button { openRecipeID = h.recipe.id } label: {
                ZStack(alignment: .bottomLeading) {
                    /* WHEN THERE IS NO PHOTO, DO NOT PRETEND.
                     *
                     * Only one recipe in the corpus has a generated image; the
                     * rest fall back to the drawing, which was made for a 60pt
                     * thumbnail. Blown up to 430 it reads as a flat beige
                     * polygon — worse than no picture at all.
                     *
                     * So the drawing gets a shorter frame, centred on a warm
                     * field, at the size it was drawn for. The photo, when
                     * there is one, fills the whole hero. */
                    if etat.hasPhoto(h.recipe) {
                        RecipeVisual(recipe: h.recipe, result: h.result)
                            .frame(height: Layout.heroPhoto)
                            .frame(maxWidth: .infinity)
                            .clipped()
                    } else {
                        ZStack {
                            Tone.heroField
                            RecipeVisual(recipe: h.recipe, result: h.result,
                                         drawingBackground: false)
                                .frame(width: 190, height: 190)
                                .offset(y: -46)
                        }
                        .frame(height: Layout.heroPhoto)
                        .frame(maxWidth: .infinity)
                    }

                    LinearGradient(
                        stops: [.init(color: .black.opacity(0.42), location: 0),
                                .init(color: .clear, location: 0.24),
                                .init(color: .clear, location: 0.40),
                                .init(color: Tone.canvas.opacity(0.72), location: 0.76),
                                .init(color: Tone.canvas, location: 1)],
                        startPoint: .top, endPoint: .bottom)

                    VStack(alignment: .leading, spacing: 0) {
                        Text("Tonight").eyebrow(Tone.heroAccent)
                            .shadow(color: .black.opacity(0.7), radius: 10)
                        Text(h.recipe.name)
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.leading)
                            .shadow(color: .black.opacity(0.62), radius: 22)
                            .padding(.top, 9)
                        Text(h.recipe.subtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.74))
                            .padding(.top, 9)
                        VerdictPill(result: h.result, firstName: profile.firstName)
                            .padding(.top, 14)
                    }
                    .padding(.horizontal, Layout.gutter)
                    .padding(.bottom, 20)

                    VStack {
                        HStack {
                            CookingContextHeader()
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, Layout.gutter)
                        /* Below the status bar, not into it. 60 put the pill
                         * on top of the clock on a notched phone. */
                        .padding(.top, 72)
                        Spacer(minLength: 0)
                    }
                }
                .frame(height: Layout.heroPhoto)
            }
            .buttonStyle(.plain)
        }
    }

    /// One line, not three tiles. "15 ready · 23 with swaps · 0 blocked" — the
    /// zero is the strongest fact in the product and it fits in eleven
    /// characters.
    private var counts: some View {
        HStack(spacing: 9) {
            count(tally.asIs, "ready", Tone.yes)
            Text("·").foregroundStyle(Tone.text3)
            count(tally.adapted, "with swaps", Tone.swap)
            Text("·").foregroundStyle(Tone.text3)
            count(tally.blocked, "blocked",
                  tally.blocked == 0 ? Tone.text3 : Tone.no)
            Spacer(minLength: 0)
        }
        /* Not monospaced. Tabular figures align the numbers without making
         * the words read like code — which is what the whole line did. */
        .font(.system(size: 13.5))
        .monospacedDigit()
        .foregroundStyle(Tone.text2)
        .padding(.horizontal, Layout.gutter)
        .padding(.top, 22)
    }

    private func count(_ n: Int, _ label: LocalizedStringKey, _ tone: Color) -> some View {
        HStack(spacing: 5) {
            Text("\(n)")
                .font(.system(size: 15.5, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(tone)
                .contentTransition(.numericText())
            Text(label)
        }
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
