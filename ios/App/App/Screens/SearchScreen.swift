// SearchScreen.swift
// Search across the whole catalogue, from the magnifier on every tab.

import SwiftUI

/// The search destination behind `Tab(role: .search)`: iOS owns the transition
/// from the floating island into a search field — that is what the role is
/// for.
struct SearchScreen: View {
    @Environment(AppState.self) private var app
    @Environment(\.navigate) private var navigate

    @State private var query = ""

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if query.isEmpty {
                    zeroState
                } else if results.isEmpty {
                    noResults
                } else {
                    ForEach(results, id: \.recipe.id) { pair in
                        Button {
                            app.rememberSearch(query)
                            navigate(.recipe(pair.recipe.id))
                        } label: {
                            RecipeRow(recipe: pair.recipe, result: pair.result)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .background(Tone.canvas.ignoresSafeArea())
        /* Applied to the scroll view rather than outside the toolbar
         * modifiers, so the navigation stack still reads the title, the
         * search field and the clear button from the modifiers below. */
        .softTopBar { EmptyView() }
        /* The system field, not one of ours. `Tab(role: .search)` places it
         * and animates it; declaring another would fight that. */
        /* A way out: `Tab(role: .search)` places the field and animates it,
         * but it does not give the parent a way back — the only exit was
         * another tab, and that is not an exit, it is a detour. */
        .searchable(text: $query, prompt: Text("Recipes and ingredients"))
        .toolbar {
            if !query.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear") {
                        query = ""
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil, from: nil, for: nil)
                    }
                }
            }
        }
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
        /* The hard band under the title, removed: hiding only the background
         * leaves all three floating over the fade, which is how the pill sits
         * on Recipes and Shopping. */
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    @ViewBuilder
    private var zeroState: some View {
        ForEach(groups, id: \.heading) { groupe in
            HStack(alignment: .firstTextBaseline) {
                Text(groupe.heading).eyebrow()
                Spacer(minLength: 0)
                Text("\(groupe.dishes.count)")
                    .scaledFont(Type.micro)
                    .foregroundStyle(Tone.text3)
            }
            .padding(.horizontal, Layout.gutter)
            .padding(.top, 18)

            ForEach(groupe.dishes, id: \.recipe.id) { pair in
                Button { navigate(.recipe(pair.recipe.id)) } label: {
                    RecipeRow(recipe: pair.recipe, result: pair.result)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// The cuts, shared by the sheet and the tab.
    private var groups: [(heading: String, dishes: [(recipe: Recipe, result: AdaptedRecipe)])] {
        app.searchGroups()
    }

    private var results: [(recipe: Recipe, result: AdaptedRecipe)] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard q.count > 1 else { return [] }
        /* Only what the subscription gives: this week, the week before, what
         * is saved, and the top fifteen. Searching the whole pool would let
         * a name advertise a recipe the account cannot open. */
        let portee = Set(app.searchScope.map(\.id))
        return app.recipes.filter { r in
            portee.contains(r.id) &&
            r.hasBody && (r.name.lowercased().contains(q)
                || r.ingredients.contains { $0.id.lowercased().contains(q) })
        }
        .prefix(20)
        .compactMap { r in app.resultFor(r).map { (recipe: r, result: $0) } }
    }

    @ViewBuilder
    private var noResults: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(String(format: String(localized: "Nothing for “%@” this week"), query))
                .scaledFont(Type.secondary, weight: .semibold)
                .foregroundStyle(Tone.text)
            Text("It may arrive in a later week. Meanwhile, these are close.")
                .scaledFont(Type.caption)
                .foregroundStyle(Tone.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Layout.gutter)
        .padding(.top, 22)

        ForEach(app.weekRecipes.prefix(2).compactMap { r in
            app.resultFor(r).map { (recipe: r, result: $0) }
        }, id: \.recipe.id) { pair in
            Button { navigate(.recipe(pair.recipe.id)) } label: {
                RecipeRow(recipe: pair.recipe, result: pair.result)
            }
            .buttonStyle(.plain)
        }
    }
}
