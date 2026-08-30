//  RecipesScreen.swift
//
//  THE ANSWER FIRST, THE LIST SECOND.
//
//  A parent opens this app with a question already in their head. The old
//  screen answered with a title bar reading "Recipes" and an undifferentiated
//  grid — the same shape as every recipe app, and silent about the one thing
//  that makes this one different.
//
//  Measured on the corpus: whatever the profile, the engine finds a way. A
//  child avoiding milk, egg, peanut, wheat and soy keeps every recipe. That
//  number goes at the top, before anything else.
//
//  A list rather than a grid. A grid asks you to compare thumbnails; a list is
//  read with one thumb and leaves room for the verdict on the right, which is
//  the information being looked for.

import SwiftUI

struct RecipesScreen: View {
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
                    answer
                    if let message = etat.syncMessage {
                        MessageBanner(texte: message)
                            .padding(.horizontal, Layout.gutter)
                            .padding(.top, 18)
                    }
                    CountedSegments(selection: $filter, tally: tally,
                                    savedCount: etat.saved.recipes.count)
                        .padding(.top, 26)
                    list
                    lockedBatches
                    disclaimer
                }
                .padding(.bottom, 110)
            }
            .background(Tone.canvas.ignoresSafeArea())
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

    /// The photo fills the top of the screen and fades into the canvas. The
    /// generated images are 1408 square; showing them in a 56pt thumbnail was
    /// the most visible waste in the old interface.
    @ViewBuilder
    private var hero: some View {
        if let h = heroPair {
            ZStack(alignment: .bottomLeading) {
                RecipeVisual(recipe: h.recipe, result: h.result)
                    .frame(height: 336)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .overlay(alignment: .bottom) {
                        LinearGradient(
                            colors: [.clear, Tone.canvas.opacity(0.6), Tone.canvas],
                            startPoint: .top, endPoint: .bottom)
                            .frame(height: 200)
                    }
                    .overlay(alignment: .top) {
                        LinearGradient(colors: [.black.opacity(0.32), .clear],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(height: 120)
                    }

                VStack(alignment: .leading, spacing: 0) {
                    Text("Tonight")
                        .font(Type.label)
                        .foregroundStyle(Tone.brand)
                        .textCase(.uppercase)
                        .kerning(1.5)

                    Text(h.recipe.name)
                        .font(Type.display)
                        .foregroundStyle(Tone.text)
                        .padding(.top, 6)

                    Text(h.recipe.subtitle)
                        .font(Type.caption)
                        .foregroundStyle(Tone.textSecondary)
                        .padding(.top, 7)

                    VerdictPill(result: h.result, firstName: profile.firstName)
                        .padding(.top, 13)
                }
                .padding(.horizontal, Layout.gutter)
                .padding(.bottom, 6)
            }
            .contentShape(Rectangle())
            .onTapGesture { openRecipeID = h.recipe.id }
        }
    }

    // MARK: - The answer

    /// Three figures, one of them a zero. "0 blocked" is the strongest fact in
    /// the product and nothing displayed it.
    private var answer: some View {
        HStack(spacing: 9) {
            Figure(value: tally.asIs, label: "ready", tone: Tone.yes)
            Figure(value: tally.adapted, label: "with swaps", tone: Tone.swap)
            Figure(value: tally.blocked, label: "blocked",
                   tone: tally.blocked == 0 ? Tone.textTertiary : Tone.no)
        }
        .padding(.horizontal, Layout.gutter)
        .padding(.top, 22)
    }

    // MARK: - List

    private var list: some View {
        LazyVStack(spacing: 0) {
            ForEach(rows, id: \.recipe.id) { pair in
                Button { openRecipeID = pair.recipe.id } label: {
                    RecipeRow(recipe: pair.recipe, result: pair.result)
                }
                .buttonStyle(.plain)

                Divider()
                    .overlay(Tone.hairline)
                    .padding(.leading, Layout.gutter + 69)
            }

            if rows.isEmpty {
                EmptyState(symbol: "magnifyingglass",
                           title: "Nothing matches",
                           message: "Try another filter.")
                    .padding(.top, 40)
            }
        }
        .padding(.top, 16)
    }

    // MARK: - Data

    private var pairs: [(recipe: Recipe, result: AdaptedRecipe)] { etat.pairs }

    private var heroPair: (recipe: Recipe, result: AdaptedRecipe)? {
        guard filter == .all else { return nil }
        /* Ready as is, and quick. Answers "what do I make tonight" without
         * making anyone scroll. */
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
    private var lockedBatches: some View {
        let locked = etat.lockedBatches
        if !locked.isEmpty {
            Button { showPaywall = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Tone.brand)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(locked.reduce(0) { $0 + $1.count }) more recipes")
                            .font(Type.secondary.weight(.semibold))
                            .foregroundStyle(Tone.text)
                        Text("7 new ones every week")
                            .font(Type.caption)
                            .foregroundStyle(Tone.textSecondary)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Tone.textTertiary)
                }
                .padding(15)
                .background(Tone.surface, in: RoundedRectangle(cornerRadius: Layout.cardRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Layout.cardRadius, style: .continuous)
                    .strokeBorder(Tone.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Layout.gutter)
            .padding(.top, 26)
        }
    }

    private var disclaimer: some View {
        Text(Settings.medicalDisclaimer)
            .font(Type.caption)
            .foregroundStyle(Tone.textTertiary)
            .padding(.horizontal, Layout.gutter)
            .padding(.top, 30)
    }
}

// MARK: - Pieces

/// One figure and its label. The number carries the weight; the word is small.
private struct Figure: View {
    let value: Int
    let label: LocalizedStringKey
    let tone: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(value)")
                .font(Type.figure)
                .foregroundStyle(tone)
                .contentTransition(.numericText())
            Text(label)
                .font(Type.caption)
                .foregroundStyle(Tone.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(Tone.surface, in: RoundedRectangle(cornerRadius: Layout.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Layout.cardRadius, style: .continuous)
            .strokeBorder(Tone.hairline, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

/// The verdict over a photo. Glass, because it floats above content — the one
/// place the material belongs.
struct VerdictPill: View {
    let result: AdaptedRecipe
    let firstName: String

    var body: some View {
        HStack(spacing: 7) {
            VerdictMark(status: result.status, size: 9)
            Text(phrase)
                .font(Type.caption.weight(.semibold))
                .foregroundStyle(Tone.text)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .glassCapsule()
    }

    private var phrase: String {
        switch result.status {
        case .asIs:
            return String(localized: "Ready as is")
        case .adapted:
            let n = result.swapCount
            return String(format: n > 1 ? String(localized: "Yes — %lld swaps")
                                        : String(localized: "Yes — %lld swap"), n)
        case .notAdaptable:
            return String(format: String(localized: "Not this one for %@"), firstName)
        case .unknown:
            return String(localized: "Needs checking")
        }
    }
}

/// A row, not a card. Thumbnail, name, meta, verdict — read with one thumb.
struct RecipeRow: View {
    let recipe: Recipe
    let result: AdaptedRecipe

    var body: some View {
        HStack(spacing: 13) {
            RecipeVisual(recipe: recipe, result: result)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                .saturation(result.status == .notAdaptable ? 0.3 : 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(recipe.name)
                    .font(Type.title)
                    .foregroundStyle(Tone.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(recipe.subtitle)
                    .font(Type.caption)
                    .foregroundStyle(Tone.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                VerdictMark(status: result.status, size: 9)
                Text(shortVerdict)
                    .font(Type.caption.weight(.semibold))
                    .foregroundStyle(result.status.tone)
            }
        }
        .padding(.horizontal, Layout.gutter)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// The number says how much work. An adjective says nothing.
    private var shortVerdict: String {
        switch result.status {
        case .asIs: return String(localized: "Yes")
        case .adapted: return "\(result.swapCount)"
        case .notAdaptable: return String(localized: "No")
        case .unknown: return "?"
        }
    }
}
