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
    /* The stack lives at the root now; a screen pushes a Route rather than
     * owning a destination. */
    @Environment(\.navigate) private var navigate
    @State private var showPaywall = false

    private var profile: ChildProfile { etat.activeProfile }
    private var tally: AppState.ProfileTally { etat.tally(for: profile) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                /* The photo runs to the top of the screen, so the pill
                 * floats over it. Everything after it is ordinary content
                 * and must clear the status bar on its own. */
                hero
                /* THE SHELVES SIT ABOVE THE WEEK.
                 *
                 * They used to fall between the subscription block and the
                 * week rail, which put them under the "This week" heading —
                 * inside a section they have nothing to do with. Saved and
                 * top rated hold recipes from ANY week, so they belong before
                 * the week starts, not in the middle of it. */
                shelves
                weekHeader
                /* ONE ASK PER SCREEN.
                 *
                 * A locked week puts its own offer where the parent just
                 * tapped, so this banner would be the second pitch on one
                 * screen, saying the same thing less precisely. */
                if etat.currentSlot.unlocked { upsell }
                weekStrip
                list
                disclaimer
            }
            .padding(.bottom, 16)
        }
        .background(Tone.canvas.ignoresSafeArea())
        /* NO `ignoresSafeArea` HERE ANY MORE.
         *
         * Apple: "All scroll views underneath navigation or toolbars
         * automatically apply a visual treatment. This ensures legibility
         * of overlapping content in the bars." That is the scroll edge
         * effect, and it is free — but only for a scroll view that sits
         * UNDER a bar. Extending past the bar switched it off, which is
         * why the clock and the battery were unreadable over the list.
         *
         * The hero photo still reaches the top: it is inside the scroll
         * view and simply drawn tall. */
        .toolbar(.hidden, for: .navigationBar)
        /* WHO YOU ARE COOKING FOR STAYS PUT.
         *
         * It rode on the photo and scrolled away with it. In a family with two
         * children on different profiles, cooking for the wrong one is the
         * worst failure this app has — so it is pinned, and the content passes
         * under it. */
        /* A FADE, NOT A BAND.
         *
         * The bar used to end on a line and the photo began underneath it —
         * two surfaces touching instead of one becoming the other. Now the
         * bar falls off downward and the photo lightens upward over the same
         * distance; where they overlap there is no edge. */
        .softTopBar { ChildTopBar() }
        .sheet(isPresented: $showPaywall) { PaywallScreen() }
        .refreshable { await etat.sync() }
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
            Button { navigate(.recipe(h.recipe.id)) } label: {
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
                        /* NINE STOPS, NOT FIVE.
                         *
                         * Five left a visible edge where the dark ended and
                         * the page began. Three of these sit in the last
                         * quarter, which is where the eye catches banding,
                         * and the final stop is the CANVAS — cream in light,
                         * near-black in dark — so the photo dissolves into
                         * the page instead of stopping against it. */
                        /* The TOP now lightens to the canvas instead of
                         * darkening. It used to go black under a cream bar,
                         * which is exactly the hard line reported from the app — the
                         * photo has to meet the bar, not fight it. */
                        stops: [.init(color: Tone.canvas, location: 0),
                                .init(color: Tone.canvas.opacity(0.9), location: 0.06),
                                .init(color: Tone.canvas.opacity(0.5), location: 0.14),
                                .init(color: Tone.canvas.opacity(0.16), location: 0.22),
                                .init(color: .clear, location: 0.30),
                                .init(color: .clear, location: 0.42),
                                .init(color: .black.opacity(0.24), location: 0.56),
                                .init(color: .black.opacity(0.52), location: 0.70),
                                .init(color: .black.opacity(0.74), location: 0.82),
                                .init(color: Tone.canvas.opacity(0.55), location: 0.93),
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
    /// THE HEADING FOLLOWS THE RAIL.
    ///
    /// It was the literal "This week" with the count of the CURRENT week, so
    /// selecting another one left a section title describing something else:
    /// "This week · 7 recipes" sat over next week's days, and over a locked
    /// week it announced seven recipes above seven empty cards.
    ///
    /// The rail underneath carries the dates, so the name only has to say
    /// which of the three is open.
    private var weekHeader: some View {
        let slot = etat.currentSlot
        return HStack(alignment: .firstTextBaseline) {
            Text(slot.offset == 0 ? "This week"
                 : slot.offset < 0 ? "Last week" : "Next week")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(Tone.text)
            Spacer(minLength: 8)
            Text(String(format: String(localized: "%lld recipes"), slot.count))
                .font(.system(size: 12))
                .foregroundStyle(Tone.text2)
        }
        .padding(.horizontal, Layout.gutter)
        .padding(.top, 20)
    }

    /* THE BOOKMARK LED NOWHERE.
     *
     * SavedRecipes has persisted to disk since the first build and the
     * bookmark on the detail page has always written to it. Nothing ever read
     * it back — tapping it saved into a void. */
    @ViewBuilder
    /// THE TWO SIDE DOORS, ALWAYS OPEN.
    ///
    /// The saved row used to render only when something was saved, and it was
    /// the single caller of `navigate(.saved)` in the app — so with an empty
    /// shortlist the screen behind it could not be reached at all. Top rated
    /// had no caller anywhere.
    ///
    /// Both are permanent now and say what they hold when they hold nothing,
    /// which is also where a parent learns the bookmark exists.
    ///
    /// Side by side rather than stacked full width: these are doors, not
    /// content, and a door should not take as much room as the week it sits
    /// above. Two tiles cost one row of height instead of two.
    private var shelves: some View {
        let n = etat.saved.recipes.count
        let votes = etat.topRated.count
        return HStack(spacing: 8) {
            shelf(icon: "bookmark.fill",
                  title: "Saved",
                  detail: n > 0
                     ? String(format: String(localized: "%lld kept"), n)
                     : String(localized: "Nothing yet"),
                  route: .saved)

            shelf(icon: "star.fill",
                  title: "Top rated",
                  detail: votes > 0
                     ? String(format: String(localized: "%lld ranked"), votes)
                     : String(localized: "Building up"),
                  route: .topRated)
        }
        .padding(.horizontal, Layout.gutter)
        .padding(.top, 14)
    }

    /// One tile.
    ///
    /// About 130pt of text width at half the screen, so both lines are held to
    /// one line each and the subtitles are written at three words or fewer.
    private func shelf(icon: String,
                       title: LocalizedStringKey,
                       detail: String,
                       route: Route) -> some View {
        Button { navigate(route) } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Tone.brandGradient,
                                in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Tone.text)
                        .lineLimit(1)
                    Text(detail)
                        .font(.system(size: 9.5))
                        .foregroundStyle(Tone.text2)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Tone.text.opacity(0.04),
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(Tone.hairline, lineWidth: 1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
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
    /// Seven days, and what is planned on each.
    ///
    /// This replaces the meal chips. "All / Snack / Breakfast / Meal" answered
    /// a question nobody asks standing in a kitchen at five o'clock; "what is
    /// Wednesday" is the real one.
    @ViewBuilder
    private var weekStrip: some View {
        @Bindable var e = etat
        WeekRail(selected: $e.selectedWeek, slots: etat.weekSlots)
            .padding(.horizontal, Layout.gutter)
            .padding(.top, 16)
    }

    /// The seven days of the selected week.
    ///
    /// It used to show ONE day, the one the strip had selected. Seven pills to
    /// answer "what is on Thursday" — and to see Thursday you had to tap
    /// Thursday. Now every day is there and the page scrolls, which is what
    /// was missing: five of seven days hold a single recipe, so one day at a
    /// time ended above the fold.
    @ViewBuilder
    private var list: some View {
        let slot = etat.currentSlot
        if slot.unlocked {
            LazyVStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { jour in
                    daySection(jour, slot: slot)
                }
            }
        } else {
            /* A LOCKED WEEK IS ONE PANEL, NOT SEVEN EMPTY CARDS.
             *
             * The server answers 402 for a week that has not been paid for
             * and sends nothing at all, so every day fell through to the
             * "Nothing planned" placeholder. Seven of those say the week is
             * EMPTY, which is the opposite of what is true.
             *
             * The count, the span and the child's name come from the
             * manifest rather than from the recipes, which is why this panel
             * names no dish: there is nothing to name until the server
             * learns to serve a reduced form. */
            lockedPanel(slot)
        }
    }

    /// TODAY IS MARKED AS A BLOCK, NOT AS A WORD.
    ///
    /// The marker was the word "today" in brand ink, at the same size and
    /// letterspacing as the six other headings above and below it. Colour
    /// alone in a nine-point eyebrow does not survive a column of seven.
    ///
    /// A rule down the side and a wash behind the whole day answer the
    /// question the parent is actually asking — where am I — and keep
    /// answering it after the header has scrolled past the recipes.
    ///
    /// The wash is INK, not brand. A pale red field here would sit on the
    /// same screen as the subscription card, which is already a pale warm
    /// field, and the two would read as the same kind of thing. The rule
    /// carries the colour; the wash only separates.
    @ViewBuilder
    private func daySection(_ jour: Int, slot: WeekSlot) -> some View {
        let plats = etat.recipesOfSelectedWeek(on: jour).compactMap { r in
            etat.resultFor(r).map { (recipe: r, result: $0) }
        }
        let cestAujourdhui = slot.offset == 0 && jour == WeekDay.today

        if cestAujourdhui {
            HStack(alignment: .top, spacing: 0) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Tone.brand)
                    .frame(width: 3)
                    .padding(.vertical, 9)
                    .padding(.leading, 6)
                VStack(alignment: .leading, spacing: 0) {
                    dayHeader(jour, slot: slot, count: plats.count, today: true)
                    dayBody(jour, plats: plats, slot: slot)
                }
            }
            .background(Tone.text.opacity(0.04),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            /* Eight rather than the gutter's fifteen: the block reaches
             * further out than the days around it, which is what makes it
             * read as a block instead of a heavier line. */
            .padding(.horizontal, 8)
            .padding(.top, 10)
        } else {
            dayHeader(jour, slot: slot, count: plats.count, today: false)
            dayBody(jour, plats: plats, slot: slot)
        }
    }

    /// The date line. Inside the block it loses the outer gutter, since the
    /// block supplies its own.
    private func dayHeader(_ jour: Int, slot: WeekSlot,
                           count: Int, today: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            /* One string rather than two Texts: the eyebrow kerns what it is
             * given, and a separator living outside the run it separates
             * spaced unevenly against it. */
            Text(today
                 ? dayTitle(jour, slot: slot) + " \u{00B7} " + String(localized: "today")
                 : dayTitle(jour, slot: slot))
                .eyebrow(today ? Tone.text : Tone.text3)
            Spacer(minLength: 0)
            Text("\(count)")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Tone.text3)
        }
        .padding(.horizontal, today ? 13 : Layout.gutter)
        .padding(.top, today ? 11 : 19)
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private func dayBody(_ jour: Int,
                         plats: [(recipe: Recipe, result: AdaptedRecipe)],
                         slot: WeekSlot) -> some View {
        if plats.isEmpty {
            EmptyDay(day: jour)
                .padding(.horizontal, Layout.gutter)
                .padding(.top, 6)
        } else {
            ForEach(plats, id: \.recipe.id) { pair in
                row(pair, slot: slot)
                if pair.recipe.id != plats.last?.recipe.id {
                    Divider().overlay(Tone.hairline)
                        .padding(.leading, Layout.gutter + Layout.thumb + 15)
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ pair: (recipe: Recipe, result: AdaptedRecipe),
                     slot: WeekSlot) -> some View {
        if slot.unlocked {
            Button { navigate(.recipe(pair.recipe.id)) } label: {
                RecipeRow(recipe: pair.recipe, result: pair.result)
            }
            .buttonStyle(.plain)
            /* Only the current week can be rearranged. A parent does not
             * reorder a week they cannot open, and a past week is history. */
            .modifier(DraggableIf(active: slot.offset == 0,
                                  recipe: pair.recipe, result: pair.result))
        } else {
            Button { showPaywall = true } label: {
                RecipeRow(recipe: pair.recipe, result: pair.result, locked: true)
            }
            .buttonStyle(.plain)
        }
    }

    /// The date under a day header: "Monday 31", and the month when it turns.
    private func dayTitle(_ jour: Int, slot: WeekSlot) -> String {
        let nom = String(localized: WeekDay.fullValues[jour])
        guard let d = slot.date(day: jour) else { return nom }
        let cal = Calendar.current
        let f = DateFormatter()
        f.locale = .current
        /* The month appears on the first of a month and on the first day of
         * the week — enough to place the week without repeating it seven
         * times. */
        let premierDuMois = cal.component(.day, from: d) == 1
        f.setLocalizedDateFormatFromTemplate(premierDuMois || jour == 0 ? "dMMM" : "d")
        return nom + " " + f.string(from: d)
    }

    /// What a locked week offers, in place of its list.
    ///
    /// The old copy promised the names and the verdict, which the parent
    /// could not see: the server sends nothing for a week that is not paid
    /// for. This says only what the manifest actually knows — how many, when,
    /// and for whom.
    private func lockedPanel(_ slot: WeekSlot) -> some View {
        VStack(spacing: 0) {
            Image(systemName: "lock.fill")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Tone.brand)
                .frame(width: 34, height: 34)
                .background(Tone.brand.opacity(0.12), in: Circle())

            Text(String(format: String(localized: "%lld recipes waiting"), slot.count))
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(Tone.upsellText)
                .padding(.top, 12)

            Text(String(format: String(localized: "%@, already adapted to %@"),
                        slot.span(), etat.activeProfile.name))
                .font(.system(size: 12.5))
                .foregroundStyle(Tone.upsellText2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 5)

            Button { showPaywall = true } label: {
                Text("Try 7 days free")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 26)
                    .frame(height: Layout.tapTarget)
            }
            .buttonStyle(PrimaryButton())
            .padding(.top, 17)

            /* The same literal the subscription card uses, so the two never
             * quote different prices on the same product. */
            Text("Then $4.99/month. Cancel any time.")
                .font(.system(size: 11))
                .foregroundStyle(Tone.upsellText2)
                .padding(.top, 9)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .padding(.horizontal, 20)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Tone.upsellField)
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Tone.brand.opacity(0.18), lineWidth: 1)
                }
        }
        .padding(.horizontal, Layout.gutter)
        .padding(.top, 18)
    }


    // (EmptyDay follows the screen, at file scope)
}

/// What an unplanned day says.
///
/// Seven recipes do not make seven suppers. Rather than spread them thin to
/// look complete, the empty day says so and offers the only useful action.
private struct EmptyDay: View {
    let day: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Nothing planned")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Tone.text)
            Text("Drag a recipe here from another day, or cook something you already know.")
                .font(.system(size: 12.5))
                .foregroundStyle(Tone.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Tone.text.opacity(0.03),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Tone.hairline, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
    }
}

extension RecipesScreen {

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

    /* THE SUBSCRIPTION IS THE POINT OF THE APP.
     *
     * It used to sit after six recipes and the medical notice — you had to
     * scroll to find the thing the product is for. It now comes right under
     * the week, as the only DARK block on a light page, so the eye lands on
     * it. Four lines: how many, how often, the price, the trial. */
    @ViewBuilder
    private var upsell: some View {
        let batches = etat.lockedBatches
        if !batches.isEmpty && !etat.subscribed {
            Button { showPaywall = true } label: {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Weeks ahead").eyebrow(Tone.brand)

                    Text(String(format: String(localized: "%lld more recipes"),
                                batches.reduce(0) { $0 + $1.count }))
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(Tone.upsellText)
                        .padding(.top, 7)

                    Text(String(format: String(localized: "7 new ones every week, adapted to %@"),
                                profile.firstName))
                        .font(.system(size: 12))
                        .foregroundStyle(Tone.upsellText2)
                        .padding(.top, 5)

                    Text("7 days free, then $4.99/month")
                        .font(.system(size: 12))
                        .foregroundStyle(Tone.upsellText2)
                        .padding(.top, 2)

                    /* Solid, in the action colour. On the dark card a light
                     * button was right; on this one the reverse reads
                     * better. */
                    Text("Try 7 days free")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 8)
                        .background(Tone.brandGradient, in: Capsule())
                        .shadow(color: Tone.brandDeep.opacity(0.3), radius: 8, y: 4)
                        .padding(.top, 13)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(17)
                /* WARM PEACH, NOT BLACK.
                 *
                 * A near-black card on a cream page reads as a hole rather
                 * than an offer, and it crushed the meal chips right below
                 * it. This stays distinct without shouting, and it belongs to
                 * the same family as the action colour. */
                .background {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Tone.upsellField)
                        .overlay {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(Tone.brand.opacity(0.18), lineWidth: 1)
                        }
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Layout.gutter)
            .padding(.top, 16)
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
                /* The system picks the vibrant tone. The verdict DOT keeps
                 * its own colour just below — that one is semantic and must
                 * not adapt. */
                .foregroundStyle(.primary)
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
/// Draggable only on the week the parent can rearrange.
///
/// `.draggable` cannot be applied conditionally inside a ViewBuilder without
/// changing the view's type, which breaks the list's identity and makes rows
/// animate as if they were replaced. A modifier keeps one type.
private struct DraggableIf: ViewModifier {
    let active: Bool
    let recipe: Recipe
    let result: AdaptedRecipe

    @ViewBuilder
    func body(content: Content) -> some View {
        if active {
            content.draggable(recipe.id) {
                RecipeRow(recipe: recipe, result: result)
                    .frame(width: 260)
                    .background(Tone.cardTop,
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        } else {
            content
        }
    }
}

struct RecipeRow: View {
    let recipe: Recipe
    let result: AdaptedRecipe

    /// A week the parent has not paid for.
    ///
    /// The name, the time and the verdict stay — they are what the row is FOR,
    /// and hiding them leaves nothing to subscribe for. The picture goes: a
    /// photo of the dish is content.
    var locked: Bool = false

    var body: some View {
        HStack(spacing: 15) {
            Group {
                if locked {
                    RoundedRectangle(cornerRadius: Layout.thumbRadius, style: .continuous)
                        .fill(Tone.text.opacity(0.05))
                        .overlay {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Tone.text3)
                        }
                } else {
                    RecipeVisual(recipe: recipe, result: result)
                        .clipShape(RoundedRectangle(cornerRadius: Layout.thumbRadius,
                                                    style: .continuous))
                }
            }
            .frame(width: Layout.thumb, height: Layout.thumb)
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
