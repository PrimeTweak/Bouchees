//  SavedAndTopRated.swift
//
//  TWO WAYS TO FIND A RECIPE THAT LEFT THE WINDOW
//
//  1. SAVED RECIPES. A parent finds a dish they love. Three weeks later it
//     rotates out. If they lose it, they are right to be angry — and the
//     rolling window turns against the product. So saving a recipe keeps a
//     COMPLETE COPY on the device. It survives rotation, the network, and an
//     expired subscription. It is theirs.
//
//  2. THE TOP RATED TAB. Recipes rated by enough people come back on merit.
//     No artificial rotation: a recipe returns because parents liked it, not
//     because a script fished it out.

import SwiftUI
import UIKit
import Observation

// MARK: - SavedRecipes

@MainActor
@Observable
final class SavedRecipes {

    private(set) var recipes: [Recipe] = []

    @ObservationIgnored private let fm = FileManager.default

    private var file: URL {
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Bouchees", isDirectory: true)
        if !fm.fileExists(atPath: base.path) {
            try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        }
        return base.appendingPathComponent("saved.json")
    }

    init() { load() }

    private func load() {
        guard let d = try? Data(contentsOf: file),
              let r = try? JSONDecoder().decode([Recipe].self, from: d) else { return }
        recipes = r
    }

    private func sauver() {
        guard let d = try? JSONEncoder().encode(recipes) else { return }
        try? d.write(to: file, options: .atomic)
    }

    func contains(_ id: String) -> Bool { recipes.contains { $0.id == id } }

    /// The whole recipe is kept, not only its identifier. That is the entire
    /// point: it has to stay readable once the server stops serving it.
    func toggle(_ recipe: Recipe) {
        if let i = recipes.firstIndex(where: { $0.id == recipe.id }) {
            recipes.remove(at: i)
        } else {
            recipes.append(recipe)
        }
        sauver()
    }

    func remove(_ id: String) {
        recipes.removeAll { $0.id == id }
        sauver()
    }
}

// MARK: - Bouton favori

struct SaveButton: View {
    let recipe: Recipe
    @Environment(AppState.self) private var etat

    private var isOn: Bool { etat.saved.contains(recipe.id) }

    var body: some View {
        Button {
            etat.saved.toggle(recipe)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Image(systemName: isOn ? "bookmark.fill" : "bookmark")
                .foregroundStyle(isOn ? Tone.brand : Color.secondary)
        }
        .accessibilityLabel(isOn ? "Remove from saved" : "Save this recipe")
        .accessibilityHint("A saved recipe stays available even after its week.")
    }
}

// MARK: - Onglet Meilleures

struct TopRatedScreen: View {
    @Environment(AppState.self) private var etat
    @Environment(\.navigate) private var navigate
    @State private var section = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Picker("", selection: $section) {
                    Text("Top rated").tag(0)
                    Text("My saved").tag(1)
                }
                .pickerStyle(.segmented)

                if section == 0 { ranking } else { saved }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 32)
        }
        .background(Tone.canvas.ignoresSafeArea())
        .navigationTitle("Best")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await etat.loadTopRated() }
        .task { await etat.loadTopRated() }
    }

    @ViewBuilder
    private var ranking: some View {
        if etat.topRated.isEmpty {
            EmptyState(symbol: "star",
                     title: "The ranking is building up",
                     message: "A recipe lands here once \(etat.ratingThreshold) people have rated it. Rate the ones you try — that is what brings the good ones up.")
        } else {
            VStack(alignment: .leading, spacing: 14) {
                Text("Recipes rated by at least \(etat.ratingThreshold) people. They stay available once their week has passed.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                ForEach(Array(etat.topRated.enumerated()), id: \.element.id) { rank, recipe in
                    if let res = etat.resultFor(recipe) {
                        Button {
                            navigate(.recipe(recipe.id))
                        } label: {
                            RankRow(rank: rank + 1, recipe: recipe, result: res)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var saved: some View {
        if etat.saved.recipes.isEmpty {
            EmptyState(symbol: "bookmark",
                     title: "Nothing saved yet",
                     message: "Save a recipe and it stays here for good — even after its week has passed.")
        } else {
            VStack(alignment: .leading, spacing: 14) {
                Text("Your saved recipes stay on this device, outside the weekly rotation.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: Grid.colonnes, spacing: 14) {
                    ForEach(etat.saved.recipes, id: \.id) { recipe in
                        if let res = etat.resultFor(recipe) {
                            Button {
                                navigate(.recipe(recipe.id))
                            } label: {
                                RecipeCard(recipe: recipe, result: res)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}

struct RankRow: View {
    let rank: Int
    let recipe: Recipe
    let result: AdaptedRecipe

    private var rankColor: Color {
        switch rank {
        case 1: return Tone.swap
        case 2, 3: return Tone.brand
        default: return .secondary
        }
    }

    var body: some View {
        HStack(spacing: 13) {
            Text("\(rank)")
                .font(.system(size: 19, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(rankColor)
                .frame(width: 28)

            RecipeVisual(recipe: recipe, result: result)
                .frame(width: 76, height: 62)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(recipe.name).font(.subheadline.weight(.semibold)).lineLimit(2)
                HStack(spacing: 8) {
                    RatingBadge(votes: recipe.votes ?? 0, average: recipe.average)
                    Text(Verdict.token(result))
                        .font(.caption2)
                        .foregroundStyle(result.status.color)
                }
            }

            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(11)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rang \(rank). \(recipe.name).")
    }
}

// MARK: - Bloc de notation, dans la fiche

struct RatingBlock: View {
    let recipe: Recipe
    @Environment(AppState.self) private var etat
    @State private var isWorking = false

    private var summary: RatingSummary? { etat.ratings[recipe.id] }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("Your rating")
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .kerning(1.2)
                .foregroundStyle(.tertiary)

            HStack {
                StarRating(note: summary?.myRating) { nouvelle in
                    Task {
                        isWorking = true
                        await etat.rate(recipe.id, note: nouvelle)
                        isWorking = false
                    }
                }
                Spacer()
                if isWorking { ProgressView() }
                else if let a = summary, a.votes > 0 {
                    RatingBadge(votes: a.votes, average: a.average)
                }
            }

            if etat.subscription.serverToken == nil {
                Text("Sign in from Settings to rate — without an account, one person could vote a hundred times.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let a = summary, a.votes > 0, a.votes < etat.ratingThreshold {
                Text(String(format: String(localized: "%lld more ratings and this recipe can enter the ranking."),
                            etat.ratingThreshold - a.votes))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

// MARK: - Saved recipes

/// THE SCREEN THAT WAS NEVER REACHABLE.
///
/// `SavedRecipes` has persisted to disk since the first build, and the
/// bookmark on the detail page has always written to it. Nothing ever read it
/// back — the button saved into a void. This is the way in.
struct SavedScreen: View {
    @Environment(AppState.self) private var etat
    @Environment(\.navigate) private var navigate

    private var pairs: [(recipe: Recipe, result: AdaptedRecipe)] {
        etat.saved.recipes.compactMap { etat.pairFor(pour: $0.id) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if pairs.isEmpty {
                    EmptyState(symbol: "bookmark",
                               title: "Nothing saved yet",
                               message: "Tap the bookmark on a recipe to keep it here.")
                        .padding(.top, 80)
                } else {
                    ForEach(pairs, id: \.recipe.id) { pair in
                        Button { navigate(.recipe(pair.recipe.id)) } label: {
                            RecipeRow(recipe: pair.recipe, result: pair.result)
                        }
                        .buttonStyle(.plain)

                        if pair.recipe.id != pairs.last?.recipe.id {
                            Divider().overlay(Tone.hairline)
                                .padding(.leading, Layout.gutter + Layout.thumb + 15)
                        }
                    }
                }
            }
            .padding(.bottom, 16)
        }
        .background(Tone.canvas.ignoresSafeArea())
        .navigationTitle("Saved")
        .navigationBarTitleDisplayMode(.large)
    }
}
