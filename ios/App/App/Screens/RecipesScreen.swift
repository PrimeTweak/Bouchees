//  RecipesScreen.swift
//
//  The main screen. The parent's question is "can they eat this?", so the
//  sorting follows the answer: what works as is, what needs swaps, what does
//  not pass this time.

import SwiftUI

struct RecipesScreen: View {
    @Environment(AppState.self) private var etat
    @State private var filter: RecipeFilter = .all
    @State private var searchText = ""
    @State private var category = "All"
    @State private var quickOnly = false
    @State private var openRecipeID: String?
    @State private var showPaywall = false

    /// Categories arrive from the data; they are localised at
    /// l'affichage seulement, pour que la comparaison avec recipe.category
    /// others exacte.
    private static let categories = ["All", "Breakfast", "Meal", "Snack", "Dessert"]

    private var profile: ChildProfile { etat.activeProfile }

    private var pairs: [(recipe: Recipe, result: AdaptedRecipe)] {
        etat.pairs.filter { paire in
            if category != "All" && paire.recipe.category != category { return false }
            if quickOnly && !(paire.recipe.timeMinutes.map { $0 <= 30 } ?? false) { return false }
            let q = searchText.trimmingCharacters(in: .whitespaces)
            if !q.isEmpty && !matches(paire.recipe, q) { return false }
            return true
        }
    }

    private func matches(_ r: Recipe, _ request: String) -> Bool {
        let cible = ([r.name, r.category] + r.ingredients.map { etat.definition($0.id)?.name ?? $0.id })
            .joined(separator: " ")
        return cible.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .contains(request.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current))
    }

    private var noFilters: Bool {
        searchText.trimmingCharacters(in: .whitespaces).isEmpty
            && category == "All" && !quickOnly
    }

    /// The suggestion of the day: ready as is, and quick if possible.
    private var hero: (recipe: Recipe, result: AdaptedRecipe)? {
        guard noFilters else { return nil }
        return pairs.first { $0.result.status == .asIs && ($0.recipe.timeMinutes ?? 99) <= 30 }
            ?? pairs.first { $0.result.status == .asIs }
            ?? pairs.first { $0.result.status == .adapted }
    }

    private var others: [(recipe: Recipe, result: AdaptedRecipe)] {
        guard let hero else { return pairs }
        return pairs.filter { $0.recipe.id != hero.recipe.id }
    }

    /// Saved and top rated stopped being tabs; they are two more ways to
    /// narrow this one list.
    private var filtered: [(recipe: Recipe, result: AdaptedRecipe)] {
        switch filter {
        case .all:   return pairs
        case .ready: return pairs.filter { $0.result.status == .asIs }
        case .swaps: return pairs.filter { $0.result.status == .adapted }
        case .saved:
            let ids = Set(etat.saved.recipes.map(\.id))
            return pairs.filter { ids.contains($0.recipe.id) }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                /* Who you are cooking for, above everything, on every scroll
                 * position. It is not part of the scrolling content because a
                 * parent must never have to scroll up to check it. */
                CookingContextHeader()
                    .background(.regularMaterial)

                CountedSegments(selection: $filter,
                                tally: etat.tally(for: profile),
                                savedCount: etat.saved.recipes.count)
                    .padding(.bottom, 10)
                    .background(.regularMaterial)

                Divider()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22, pinnedViews: []) {
                        if let message = etat.syncMessage {
                            MessageBanner(texte: message)
                        }

                        if filter == .all, let hero {
                            FeaturedCard(recipe: hero.recipe, result: hero.result, firstName: profile.firstName)
                                .onTapGesture { openRecipeID = hero.recipe.id }
                        }

                        filters

                        if filtered.isEmpty {
                            EmptyState(symbol: "magnifyingglass",
                                     title: "Nothing matches",
                                     message: "Try another word, or remove a filter.")
                        } else if filter == .all {
                            section(String(localized: "Ready as is"), others.filter { $0.result.status == .asIs })
                            section(String(localized: "With a few swaps"), others.filter { $0.result.status == .adapted })
                            section(String(localized: "Not this time"), others.filter { $0.result.status == .notAdaptable })
                        } else {
                            /* A chosen filter needs no section headers: the
                             * segment already said what this list is. */
                            grid(filtered)
                        }

                        lockedBatches
                        footer
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 32)
                }
            }
            .background(Tint.background.ignoresSafeArea())
            .navigationTitle("Cook")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await etat.sync() }
            .searchable(text: $searchText, prompt: "Search — chicken, muffins, squash…")
            .navigationDestination(item: $openRecipeID) { id in
                if let r = etat.recipe(pour: id), let res = etat.result(pour: id) {
                    RecipeDetailScreen(recipe: r, result: res, firstName: profile.firstName)
                }
            }
            .sheet(isPresented: $showPaywall) { PaywallScreen() }
        }
    }

    // MARK: - Morceaux

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Today")
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .kerning(1.4)
                .foregroundStyle(.tertiary)

            (Text("Cooking for ")
             + Text(etat.familyMode && etat.profiles.count > 1
                    ? Format.liste(etat.profiles.map(\.name))
                    : profile.name).foregroundColor(Tint.betterave))
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .lineLimit(3)

            Text(descriptionProfil)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
    }

    private var descriptionProfil: String {
        let noms = etat.allergenNames(profile.allergens)
        if etat.familyMode && etat.profiles.count > 1 {
            let base = "We take the youngest age (\(Format.age(profile.ageMonths))) and avoid everything any of them avoids"
            return noms.isEmpty ? base + "." : base + " : \(Format.liste(noms))."
        }
        return noms.isEmpty
            ? "\(Format.age(profile.ageMonths)) — no allergen avoided yet."
            : "\(Format.age(profile.ageMonths)) — no \(Format.liste(noms))."
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Self.categories, id: \.self) { c in
                    FilterPill(title: String(localized: String.LocalizationValue(c)),
                                 isOn: category == c) { category = c }
                }
                FilterPill(title: String(localized: "30 min or less"), isOn: quickOnly) {
                    quickOnly.toggle()
                }
            }
            .padding(.horizontal, 2)
        }
        .scrollClipDisabled()
    }

    /// A grid with no section header: the chosen segment already said what
    /// this list is.
    private func grid(_ items: [(recipe: Recipe, result: AdaptedRecipe)]) -> some View {
        LazyVGrid(columns: Grid.colonnes, spacing: 14) {
            ForEach(items, id: \.recipe.id) { paire in
                Button {
                    openRecipeID = paire.recipe.id
                } label: {
                    RecipeCard(recipe: paire.recipe, result: paire.result)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /* @ViewBuilder, and it has to stay directly above the func: an `if` with
     * no `else` and no `return` only compiles under it. My grid() insertion
     * landed between the attribute and this declaration, which silently moved
     * it onto the wrong function. */
    @ViewBuilder
    private func section(_ title: String,
                         _ items: [(recipe: Recipe, result: AdaptedRecipe)]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: title, compte: items.count)
                LazyVGrid(columns: Grid.colonnes, spacing: 14) {
                    ForEach(items, id: \.recipe.id) { paire in
                        Button {
                            openRecipeID = paire.recipe.id
                        } label: {
                            RecipeCard(recipe: paire.recipe, result: paire.result)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var lockedBatches: some View {
        let verrous = etat.lockedBatches
        if !verrous.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(verrous) { lot in
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: lot.title, compte: lot.count)
                        if let note = lot.note {
                            Text(note).font(.footnote).foregroundStyle(.secondary)
                        }
                        Button {
                            showPaywall = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "lock.fill")
                                    .font(.title3)
                                    .foregroundStyle(Tint.betterave)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(lot.count) locked recipes").font(.subheadline.weight(.semibold))
                                    Text("See what the subscription adds")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                            .padding(15)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Tint.betterave.opacity(0.08),
                                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var footer: some View {
        Text(Settings.medicalDisclaimer)
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .padding(.top, 12)
    }
}

// MARK: - Featured card

struct FeaturedCard: View {
    let recipe: Recipe
    let result: AdaptedRecipe
    let firstName: String

    private var pourquoi: String {
        result.status == .asIs
            ? "Nothing to change: as is, it works for \(firstName)."
            : "\(result.swapCount) swap\(result.swapCount > 1 ? "s" : "") and it is ready for \(firstName)."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RecipeVisual(recipe: recipe, result: result)
                .aspectRatio(16/10, contentMode: .fill)
                .frame(maxWidth: .infinity)
                .clipped()

            VStack(alignment: .leading, spacing: 8) {
                Text("Notre choix · \(recipe.subtitle)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.tertiary)
                Text(recipe.name)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .lineLimit(2)
                Text(pourquoi)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("See the recipe")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Color.primary, in: Capsule())
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

struct FilterPill: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .foregroundStyle(isOn ? Color(.systemBackground) : Color.primary)
                .background(isOn ? Color.primary : Color(.secondarySystemGroupedBackground), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(isOn ? 0 : 0.1), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}
