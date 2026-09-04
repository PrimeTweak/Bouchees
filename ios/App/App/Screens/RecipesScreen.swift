// A child avoiding milk, egg, peanut, wheat and soy keeps every recipe.
// RecipesScreen.swift

import SwiftUI
import UIKit

struct RecipesScreen: View {
    var tab: Binding<Int>?
    @Environment(AppState.self) private var app

    @State private var meal: String?
    /// The day a dragged recipe is hovering over, for the highlight.
    @State private var targetedDay: Int?
    /* The stack lives at the root now; a screen pushes a Route rather than
     * owning a destination. */
    @Environment(\.navigate) private var navigate
    @State private var showPaywall = false

    private var profile: ChildProfile { app.activeProfile }
    private var tally: AppState.ProfileTally { app.tally(for: profile) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                /* The photo runs to the top of the screen, so the pill
                 * floats over it. Everything after it is ordinary content
                 * and must clear the status bar on its own. */
                hero
                /* The shelves sit above the week. */
                shelves
                weekHeader
                weekStrip
                list
                /* After the value, not before it: the card sat between the
                 * week heading and the rail: a title, then an offer, then
                 * only what the title announced. */
                if app.currentSlot.unlocked { upsell }
                disclaimer
            }
            .padding(.bottom, 16)
        }
        .background(Tone.canvas.ignoresSafeArea())
        /* No `ignoresSafeArea` here any more: this ensures legibility of
         * overlapping content in the bars." That is the scroll edge effect,
         * and it is free — but only for a scroll view that sits UNDER a bar. */
        .toolbar(.hidden, for: .navigationBar)
        /* In a family with two children on different profiles, cooking for
         * the wrong one is the worst failure this app has — so it is pinned,
         * and the content passes under it. */
        /* A fade, not a band: now the bar falls off downward and the photo
         * lightens upward over the same distance; where they overlap there is
         * no edge. */
        .softTopBar { ChildTopBar() }
        .sheet(isPresented: $showPaywall) { PaywallScreen() }
        .refreshable { await app.sync() }
    }

    // MARK: - Hero

    /* It is the essence of a recipe app, and it is also the one thing here
     * nobody else can produce: the image is generated from the ADAPTED
     * ingredient list, so a milk-free recipe shows a milk-free dish. */
    @ViewBuilder
    private var hero: some View {
        if let h = heroPair {
            Button { navigate(.recipe(h.recipe.id)) } label: {
                ZStack(alignment: .bottomLeading) {
                                        /* When there is no photo, do not pretend: blown up to 430
                     * it reads as a flat beige polygon — worse than no
                     * picture at all. */
                    /* The hero is dark, whatever the theme: apple Music,
                     * Spotify, Airbnb all do this: the image area never
                     * switches to light. */
                    ZStack {
                        Tone.heroField
                        if app.hasPhoto(h.recipe) {
                            RecipeVisual(recipe: h.recipe, result: h.result)
                                .frame(height: Layout.heroPhoto)
                                .frame(maxWidth: .infinity)
                        } else {
                            /* The drawing was made for a 66pt thumbnail. */
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
                                                /* Three of these sit in the last quarter, which is
                         * where the eye catches banding, and the final stop
                         * is the CANVAS — cream in light, near-black in. */
                        /* The TOP now lightens to the canvas instead of
                         * darkening. */
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
                        /* Dated, now that the list below starts tomorrow: the
                         * hero is the only place today's name appears. */
                        Text(String(localized: "Tonight") + " \u{00B7} " + dayTitle(WeekDay.today, slot: app.currentSlot))
                            .eyebrow(Tone.heroAccent)
                            .shadow(color: .black.opacity(0.7), radius: 10)
                        Text(h.recipe.name)
                            .scaledFont(Type.display, weight: .bold)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.leading)
                            .shadow(color: .black.opacity(0.62), radius: 22)
                            .padding(.top, 9)
                        Text(h.recipe.subtitle)
                            .scaledFont(Type.secondary)
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

    /* The week, not the verdict: a recipe with two swaps is not lesser; it
     * has two different lines on the shopping list. */
    /// The heading follows the rail: the rail underneath carries the dates, so
    /// the name only has to say which of the three is open.
    private var weekHeader: some View {
        let slot = app.currentSlot
        return HStack(alignment: .firstTextBaseline) {
            Text(slot.offset == 0 ? "This week"
                 : slot.offset < 0 ? "Last week" : "Next week")
                .scaledFont(Type.heading, weight: .bold)
                .foregroundStyle(Tone.text)
            Spacer(minLength: 8)
            Text(String(format: String(localized: "%lld recipes"), slot.count))
                .scaledFont(Type.caption)
                .foregroundStyle(Tone.text2)
        }
        .padding(.horizontal, Layout.gutter)
        .padding(.top, 20)
    }

    /* The bookmark led nowhere: savedRecipes has persisted to disk since the
     * first build and the bookmark on the detail page has always written to
     * it. */
    /// The two side doors, always open: both are permanent now and say what
    /// they hold when they hold nothing, which is also where a parent learns
    /// the bookmark exists.
    private var shelves: some View {
        let n = app.saved.recipes.count
        let votes = app.topRated.count
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

    /// One tile: about 130pt of text width at half the screen, so both lines
    /// are held to one line each and the subtitles are written at three words
    /// or fewer.
    private func shelf(icon: String,
                       title: LocalizedStringKey,
                       detail: String,
                       route: Route) -> some View {
        Button { navigate(route) } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .scaledFont(Type.label, weight: .medium)
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Tone.brandGradient,
                                in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .scaledFont(Type.caption, weight: .semibold)
                        .foregroundStyle(Tone.text)
                        .lineLimit(1)
                    Text(detail)
                        .scaledFont(Type.micro)
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



    // MARK: - List

    /// Grouped by meal, in the order of a day: seven days, and what is planned
    /// on each.
    @ViewBuilder
    private var weekStrip: some View {
        @Bindable var e = app
        WeekRail(selected: $e.selectedWeek, slots: app.weekSlots)
            .padding(.horizontal, Layout.gutter)
            .padding(.top, 16)
    }

    /// The seven days, always: the red rule marks today, not a truncation.
    private func days(for slot: WeekSlot) -> [Int] { Array(0..<7) }

    /// Every week shows its days; a locked recipe shows its name and its
    /// verdict from the catalogue, and opens the paywall.
    private var list: some View {
        let slot = app.currentSlot
        return LazyVStack(spacing: 0) {
            ForEach(days(for: slot), id: \.self) { dayIndex in
                daySection(dayIndex, slot: slot)
            }
        }
    }

    /// Today is marked as a block, not as a word: the wash is INK, not brand.
    @ViewBuilder
    private func daySection(_ dayIndex: Int, slot: WeekSlot) -> some View {
        let isToday = slot.offset == 0 && dayIndex == WeekDay.today
        /* Today's meal is the hero above; its row would say it twice. */
        let dishes = app.recipesOfSelectedWeek(on: dayIndex)
            .filter { !(isToday && $0.id == app.tonight?.id) }
            .compactMap { r in app.resultFor(r).map { (recipe: r, result: $0) } }

        if isToday {
            HStack(alignment: .top, spacing: 0) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Tone.brand)
                    .frame(width: 3)
                    .padding(.vertical, 9)
                    .padding(.leading, 6)
                VStack(alignment: .leading, spacing: 0) {
                    dayHeader(dayIndex, slot: slot, today: true)
                    dayBody(dayIndex, dishes: dishes, slot: slot)
                }
            }
            .background(Tone.text.opacity(0.04),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            /* Eight rather than the gutter's fifteen: the block reaches
             * further out than the days around it, which is what makes it
             * read as a block instead of a heavier line. */
            .padding(.horizontal, 8)
            .padding(.top, 10)
            .modifier(DropDayIf(active: slot.offset == 0, day: dayIndex,
                                targeted: $targetedDay) { id in
                if let r = app.recipeByID(id) { app.move(r, to: dayIndex) }
            })
        } else {
            VStack(alignment: .leading, spacing: 0) {
                dayHeader(dayIndex, slot: slot, today: false)
                dayBody(dayIndex, dishes: dishes, slot: slot)
            }
            .background(targetedDay == dayIndex ? Tone.brand.opacity(0.06) : .clear,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .modifier(DropDayIf(active: slot.offset == 0, day: dayIndex,
                                targeted: $targetedDay) { id in
                if let r = app.recipeByID(id) { app.move(r, to: dayIndex) }
            })
        }
    }

    /// The date line. Inside the block it loses the outer gutter, since the
    /// block supplies its own.
    private func dayHeader(_ dayIndex: Int, slot: WeekSlot, today: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            /* One string rather than two Texts: the eyebrow kerns what it is
             * given, and a separator living outside the run it separates
             * spaced unevenly against it. */
            Text(today
                 ? dayTitle(dayIndex, slot: slot) + " \u{00B7} " + String(localized: "today")
                 : dayTitle(dayIndex, slot: slot))
                .eyebrow(today ? Tone.text : Tone.text3)
            /* No count: it numbered the rows sitting right below it. */
            Spacer(minLength: 0)
        }
        .padding(.horizontal, today ? 13 : Layout.gutter)
        .padding(.top, today ? 11 : 19)
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private func dayBody(_ dayIndex: Int,
                         dishes: [(recipe: Recipe, result: AdaptedRecipe)],
                         slot: WeekSlot) -> some View {
        if dishes.isEmpty {
            EmptyDay(day: dayIndex)
                .padding(.horizontal, Layout.gutter)
                .padding(.top, 6)
        } else {
            ForEach(dishes, id: \.recipe.id) { pair in
                row(pair, slot: slot)
                if pair.recipe.id != dishes.last?.recipe.id {
                    Divider().overlay(Tone.hairline)
                        .padding(.leading, Layout.gutter + Layout.thumb + 15)
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ pair: (recipe: Recipe, result: AdaptedRecipe),
                     slot: WeekSlot) -> some View {
        if pair.recipe.hasBody {
            CookedSwipe(recipe: pair.recipe,
                        cooked: app.cooked.contains(pair.recipe.id),
                        open: { navigate(.recipe(pair.recipe.id)) }) {
                RecipeRow(recipe: pair.recipe, result: pair.result,
                          cooked: app.cooked.contains(pair.recipe.id))
                    /* Only the current week can be rearranged. A parent does
                     * not reorder a week they cannot open. */
                    .modifier(DraggableIf(active: slot.offset == 0,
                                          recipe: pair.recipe, result: pair.result))
            }
        } else {
            Button { showPaywall = true } label: {
                RecipeRow(recipe: pair.recipe, result: pair.result, locked: true)
            }
            .buttonStyle(.plain)
        }
    }

    /// The date under a day header: "Monday 31", and the month when it turns.
    private func dayTitle(_ dayIndex: Int, slot: WeekSlot) -> String {
        let nom = String(localized: WeekDay.fullValues[dayIndex])
        guard let d = slot.date(day: dayIndex) else { return nom }
        let cal = Calendar.current
        let f = DateFormatter()
        f.locale = .current
        /* The month appears on the first of a month and on the first day of
         * the week — enough to place the week without repeating it seven
         * times. */
        let premierDuMois = cal.component(.day, from: d) == 1
        f.setLocalizedDateFormatFromTemplate(premierDuMois || dayIndex == 0 ? "dMMM" : "d")
        return nom + " " + f.string(from: d)
    }

// (EmptyDay follows the screen, at file scope)
}

/// What an unplanned day says: rather than spread them thin to look complete,
/// the empty day says so and offers the only useful action.
private struct EmptyDay: View {
    let day: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Nothing planned")
                .scaledFont(Type.body, weight: .semibold)
                .foregroundStyle(Tone.text)
            Text("Drag a recipe here from another day, or cook something you already know.")
                .scaledFont(Type.caption)
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

    private var pairs: [(recipe: Recipe, result: AdaptedRecipe)] { app.pairs }

    private var week: [Recipe] { app.weekRecipes }

    /// Today's meal, from the sequence. Falls back on the week when today
    /// holds none.
    private var heroPair: (recipe: Recipe, result: AdaptedRecipe)? {
        if let t = app.tonight, let r = app.resultFor(t) { return (t, r) }
        let inWeek = pairs.filter { p in week.contains { $0.id == p.recipe.id } }
        let pool = inWeek.isEmpty ? pairs : inWeek
        return pool.first { $0.recipe.isMeal } ?? pool.first
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

    /// The App Store's own price, in the user's currency. Falls back to the
    /// trial wording alone when StoreKit has not answered — never to a
    /// number we invented.
    private var priceLine: String {
        guard let price = app.subscription.displayPrice else {
            return String(localized: "7 days free")
        }
        let period = app.subscription.displayPeriod ?? String(localized: "month")
        return String(format: String(localized: "7 days free, then %@/%@"), price, period)
    }

    /* The subscription is the point of the app: it now comes right under the
     * week, as the only DARK block on a light page, so the eye lands on it. */
    @ViewBuilder

    private var upsell: some View {
        let locked = app.recipes.filter { !$0.hasBody }.count
        if locked > 0 && !app.subscribed {
            Button { showPaywall = true } label: {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Weeks ahead").eyebrow(Tone.brand)

                    Text(String(format: String(localized: "%lld more recipes"), locked))
                        .scaledFont(Type.heading, weight: .bold)
                        .foregroundStyle(Tone.upsellText)
                        .padding(.top, 7)

                    Text(String(format: String(localized: "A meal and a snack every day, adapted to %@"),
                                profile.firstName))
                        .scaledFont(Type.caption)
                        .foregroundStyle(Tone.upsellText2)
                        .padding(.top, 5)

                    Text(priceLine)
                        .scaledFont(Type.caption)
                        .foregroundStyle(Tone.upsellText2)
                        .padding(.top, 2)

                    /* Solid, in the action colour. On the dark card a light
                     * button was right; on this one the reverse reads
                     * better. */
                    Text("Try 7 days free")
                        .scaledFont(Type.caption, weight: .semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 8)
                        .background(Tone.brandGradient, in: Capsule())
                        .shadow(color: Tone.brandDeep.opacity(0.3), radius: 8, y: 4)
                        .padding(.top, 13)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(17)
                /* Warm peach, not black: a near-black card on a cream page
                 * reads as a hole rather than an offer, and it crushed the
                 * meal chips right below it. */
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
            .scaledFont(Type.label)
            .foregroundStyle(Tone.text3)
            .lineSpacing(2)
            .padding(.horizontal, Layout.gutter)
            .padding(.top, 32)
    }
}

// MARK: - Pieces

/// The verdict over a photo. Glass, because it floats above content.
struct VerdictPill: View {
    let result: AdaptedRecipe
    let firstName: String

    var body: some View {
        HStack(spacing: 8) {
            VerdictMark(status: result.status)
            Text(phrase)
                .scaledFont(Type.secondary, weight: .semibold)
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
            /* Past tense: the swap is already made, and it is named two lines
             * below. "Yes" answered a question the screen never asked. */
            let n = result.swapCount
            return String(format: n > 1 ? String(localized: "%lld swaps made")
                                        : String(localized: "%lld swap made"), n)
        case .notAdaptable:
            return String(format: String(localized: "Not this one for %@"), firstName)
        case .unknown: return String(localized: "Needs checking")
        }
    }
}

/// A day of the current week receives a dragged recipe; other weeks do not.
private struct DropDayIf: ViewModifier {
    let active: Bool
    let day: Int
    @Binding var targeted: Int?
    let receive: (String) -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if active {
            content.dropDestination(for: String.self) { ids, _ in
                guard let id = ids.first else { return false }
                withAnimation(.soft(0.25)) { receive(id) }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                return true
            } isTargeted: { over in
                targeted = over ? day : (targeted == day ? nil : targeted)
            }
        } else {
            content
        }
    }
}

/// The week row: opening the recipe, and marking it cooked with a swipe.
/// Both live on the SAME view, because in SwiftUI a child's gesture beats a
/// parent's — a Button child won every touch.
private struct CookedSwipe<Content: View>: View {
    @Environment(AppState.self) private var app
    let recipe: Recipe
    let cooked: Bool
    let open: () -> Void
    @ViewBuilder let content: Content

    @State private var offset: CGFloat = 0
    private let seuil: CGFloat = 78

    var body: some View {
        content
            .background(Tone.canvas)
            .offset(x: offset)
            .background(alignment: .trailing) {
                if offset < -4 {
                    Image(systemName: cooked ? "arrow.uturn.backward" : "checkmark")
                        .scaledFont(Type.body, weight: .semibold)
                        .foregroundStyle(.white)
                        .frame(width: seuil + 24)
                        .frame(maxHeight: .infinity)
                        .background(cooked ? Tone.text3 : Tone.yes)
                        .accessibilityLabel(Text(cooked ? "Not cooked" : "Cooked"))
                }
            }
            .contentShape(.rect)
            /* The drag wakes at twenty-eight points, well past the scroll
             * view's own threshold, so a scroll is claimed before this
             * gesture can contend for it. */
            .onTapGesture { open() }
            .gesture(
                DragGesture(minimumDistance: 28, coordinateSpace: .local)
                    .onChanged { g in
                        guard abs(g.translation.width) > abs(g.translation.height) * 2 else { return }
                        /* Measured from where it woke: no jump on frame one. */
                        let depart = g.translation.width < 0 ? 28.0 : -28.0
                        offset = max(-seuil - 24, min(0, g.translation.width + depart))
                    }
                    .onEnded { g in
                        let commit = offset < 0 && g.translation.width < -(seuil + 28)
                        withAnimation(.soft(0.24)) { offset = 0 }
                        guard commit else { return }
                        if cooked { app.unmarkCooked(recipe.id) } else { app.markCooked(recipe.id) }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
            )
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
    }
}

/// A row, not a card: draggable only on the week the parent can rearrange.
private struct DraggableIf: ViewModifier {
    let active: Bool
    let recipe: Recipe
    let result: AdaptedRecipe

    @ViewBuilder
    func body(content: Content) -> some View {
        if active {
            /* Behind a long press: `draggable` claims the touch on contact and
             * wins against any DragGesture above it, which is what swallowed
             * the swipe on the current week. */
            content
                .draggable(recipe.id) {
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

    /// A week the parent has not paid for: the name, the time and the verdict
    /// stay — they are what the row is FOR, and hiding them leaves nothing to
    /// subscribe for.
    var locked: Bool = false
    var cooked: Bool = false

    var body: some View {
        HStack(spacing: 15) {
            Group {
                if locked {
                    RoundedRectangle(cornerRadius: Layout.thumbRadius, style: .continuous)
                        .fill(Tone.text.opacity(0.05))
                        .overlay {
                            Image(systemName: "lock.fill")
                                .scaledFont(Type.body, weight: .medium)
                                .foregroundStyle(Tone.text3)
                        }
                } else {
                    RecipeVisual(recipe: recipe, result: result, compact: true)
                        .clipShape(RoundedRectangle(cornerRadius: Layout.thumbRadius,
                                                    style: .continuous))
                }
            }
            /* One size for every row: two sizes side by side read as a mistake,
             * not as an intention. A snack is told apart by its warm field
             * and its subtitle. */
            .frame(width: Layout.thumb, height: Layout.thumb)
            .background(recipe.isSnack ? Tone.swap.opacity(0.10) : .clear,
                        in: RoundedRectangle(cornerRadius: Layout.thumbRadius, style: .continuous))
                .shadow(color: .black.opacity(recipe.isSnack ? 0.18 : 0.4), radius: 7, y: 4)
                .saturation(result.status == .notAdaptable ? 0.3 : 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.name)
                    .scaledFont(Type.heading)
                    .foregroundStyle(Tone.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(recipe.subtitle)
                    .scaledFont(Type.body)
                    .foregroundStyle(Tone.text2)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            /* Set by "Done" in cooking mode. Ink, not verdict green: the row
             * carries no verdict any more, and a green mark read as one. */
            if cooked {
                Image(systemName: "checkmark")
                    .scaledFont(Type.micro, weight: .semibold)
                    .foregroundStyle(Tone.text3)
                    .accessibilityLabel(Text("Cooked"))
            }
        }
        .padding(.horizontal, Layout.gutter)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        /* The row shows no verdict; VoiceOver still says it. */
        .accessibilityHint(Text(spoken))
    }

    /// What VoiceOver reads: the dot carries no word, so the label does.
    private var spoken: String {
        switch result.status {
        case .asIs: return String(localized: "Ready as is")
        case .adapted: return String(format: String(localized: "Adapted, %lld swaps"), result.swapCount)
        case .notAdaptable: return String(localized: "Not adaptable")
        case .unknown: return String(localized: "Unknown ingredient")
        }
    }
}
