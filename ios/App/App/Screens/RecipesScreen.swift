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

    @State private var meal: String?
    @State private var openRecipeID: String?
    @State private var showPaywall = false

    private var profile: ChildProfile { etat.activeProfile }
    private var tally: AppState.ProfileTally { etat.tally(for: profile) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    hero
                    weekHeader
                    mealChips
                    if let message = etat.syncMessage {
                        MessageBanner(texte: message)
                            .padding(.horizontal, Layout.gutter)
                            .padding(.top, 18)
                    }
                    list
                    locked
                    disclaimer
                }
                .padding(.bottom, 20)
            }
            .background(Tone.canvas.ignoresSafeArea())
            .ignoresSafeArea(.container, edges: .top)
            .toolbar(.hidden, for: .navigationBar)
            /* WHO YOU ARE COOKING FOR STAYS PUT.
             *
             * It rode on the photo and scrolled away with it. In a family
             * with two children on different profiles, cooking for the wrong
             * one is the worst failure this app has — so it is pinned, and
             * the content passes under it. */
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack {
                    CookingContextHeader()
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Layout.gutter)
                .padding(.top, 6)
                .padding(.bottom, 8)
            }
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
                    /* THE HERO IS DARK, WHATEVER THE THEME.
                     *
                     * White text over a photo needs a dark field under it. In
                     * light mode my gradient faded to pale canvas and the
                     * title landed white on beige — unreadable.
                     *
                     * Apple Music, Spotify, Airbnb all do this: the image area
                     * never switches to light. What switches is everything
                     * BELOW it. */
                    ZStack {
                        Tone.heroField
                        if etat.hasPhoto(h.recipe) {
                            RecipeVisual(recipe: h.recipe, result: h.result)
                                .frame(height: Layout.heroPhoto)
                                .frame(maxWidth: .infinity)
                        } else {
                            /* The drawing was made for a 66pt thumbnail. At
                             * its own size on the dark field it reads as
                             * deliberate; blown up to 430 it was a beige
                             * polygon. */
                            RecipeVisual(recipe: h.recipe, result: h.result,
                                         drawingBackground: false)
                                .frame(width: 190, height: 190)
                                .offset(y: -42)
                        }
                    }
                    .frame(height: Layout.heroPhoto)
                    .frame(maxWidth: .infinity)
                    /* Without this the transparent drawing paints over the
                     * whole page — the beige smears behind the list. */
                    .clipped()

                    LinearGradient(
                        /* Dark to the bottom of the photo. Fading to the
                         * canvas meant fading to pale in light mode, which put
                         * the title on beige. */
                        stops: [.init(color: .black.opacity(0.45), location: 0),
                                .init(color: .clear, location: 0.26),
                                .init(color: .clear, location: 0.42),
                                .init(color: .black.opacity(0.58), location: 0.78),
                                .init(color: .black.opacity(0.74), location: 1)],
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

                }
                .frame(height: Layout.heroPhoto)
            }
            .buttonStyle(.plain)
        }
    }

    /* THE WEEK, NOT THE VERDICT.
     *
     * The old segments — All / Ready / Swaps — invented a hierarchy that does
     * not exist. A recipe with two swaps is not lesser; it has two different
     * lines on the shopping list. Sorting by it told the parent that twelve of
     * their fifteen recipes were second choice.
     *
     * What a parent actually filters by is the meal. And the batches were
     * always weekly — seven recipes each, which is exactly the subscription
     * promise. Nothing in the UI ever showed it.
     */
    private var weekHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("This week")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(Tone.text)
            Spacer(minLength: 8)
            Text(String(format: String(localized: "%lld recipes"), week.count))
                .font(.system(size: 12))
                .foregroundStyle(Tone.text2)
        }
        .padding(.horizontal, Layout.gutter)
        .padding(.top, 20)
    }

    /// Breakfast, meals, snacks — how a parent thinks about a day.
    private var mealChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                chip(nil, "All", week.count)
                ForEach(mealTypes, id: \.self) { m in
                    chip(m, LocalizedStringKey(m), week.filter { $0.category == m }.count)
                }
            }
            .padding(.horizontal, Layout.gutter)
        }
        .padding(.top, 16)
    }

    private func chip(_ value: String?, _ label: LocalizedStringKey, _ n: Int) -> some View {
        let on = meal == value
        return Button {
            withAnimation(.smooth(duration: 0.2)) { meal = value }
        } label: {
            HStack(spacing: 6) {
                Text(label)
                Text("\(n)").foregroundStyle(on ? Tone.canvas.opacity(0.6) : Tone.text3)
            }
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(on ? Tone.canvas : Tone.text2)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(on ? AnyShapeStyle(Tone.text) : AnyShapeStyle(Tone.text.opacity(0.05)),
                        in: Capsule())
            .overlay { Capsule().strokeBorder(on ? .clear : Tone.hairline, lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }

    private var mealTypes: [String] {
        var seen: [String] = []
        for r in week where !seen.contains(r.category) { seen.append(r.category) }
        return seen
    }

    // MARK: - List

    /// Grouped by meal, in the order of a day. Mixing breakfast into the meals
    /// made the list feel like a pile; grouping makes it a week.
    private var list: some View {
        LazyVStack(spacing: 0) {
            ForEach(groups, id: \.meal) { group in
                Text(LocalizedStringKey(group.meal))
                    .eyebrow()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Layout.gutter)
                    .padding(.top, 24)
                    .padding(.bottom, 2)

                ForEach(group.items, id: \.recipe.id) { pair in
                    Button { openRecipeID = pair.recipe.id } label: {
                        RecipeRow(recipe: pair.recipe, result: pair.result)
                    }
                    .buttonStyle(.plain)

                    if pair.recipe.id != group.items.last?.recipe.id {
                        Divider().overlay(Tone.hairline)
                            .padding(.leading, Layout.gutter + Layout.thumb + 15)
                    }
                }
            }

            if groups.isEmpty {
                EmptyState(symbol: "fork.knife",
                           title: "Nothing here",
                           message: "Try another meal.")
                    .padding(.top, 44)
            }
        }
    }

    // MARK: - Data

    private var pairs: [(recipe: Recipe, result: AdaptedRecipe)] { etat.pairs }

    private var week: [Recipe] { etat.weekRecipes }

    private var heroPair: (recipe: Recipe, result: AdaptedRecipe)? {
        let inWeek = pairs.filter { p in week.contains { $0.id == p.recipe.id } }
        let pool = inWeek.isEmpty ? pairs : inWeek
        return pool.first { $0.result.status == .asIs && ($0.recipe.timeMinutes ?? 99) <= 40 }
            ?? pool.first { $0.result.status == .asIs }
            ?? pool.first
    }

    private var groups: [(meal: String, items: [(recipe: Recipe, result: AdaptedRecipe)])] {
        let ids = Set(week.map(\.id))
        var rows = pairs.filter { ids.contains($0.recipe.id) }
        if rows.isEmpty { rows = pairs }
        if let m = meal { rows = rows.filter { $0.recipe.category == m } }
        if let h = heroPair { rows = rows.filter { $0.recipe.id != h.recipe.id } }

        var order: [String] = []
        for r in rows where !order.contains(r.recipe.category) { order.append(r.recipe.category) }
        return order.map { m in (m, rows.filter { $0.recipe.category == m }) }
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
