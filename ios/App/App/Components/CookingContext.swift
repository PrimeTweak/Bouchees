// CookingContext.swift The floating tab bar, the child picker, and the
// counted segments — the three pieces that appear on more than one screen.

import SwiftUI
/* UIApplication, for dropping the keyboard. */
import UIKit

// MARK: - Tab bar

/// A GLASS CAPSULE, INSET 21pt, WITH A SEARCH ISLAND.
///


// MARK: - Context header

/// Who you are cooking for, over the hero photo. In a family with two children
/// on different profiles, cooking for the wrong one is the worst failure this
/// app can have — so it is never more than a glance away.
struct CookingContextHeader: View {
    /// Avatar and first name only: on a screen whose title already occupies
    /// the left of the bar, the full pill would take the whole line and push
    /// the content down.
    var compact: Bool = false

    /// Draw our own glass, or let the toolbar supply it: that is why the pill
    /// needed two taps.
    var ownGlass: Bool = true

    @Environment(AppState.self) private var app
    /* The sheet is not ours to own: so the first tap set the flag, the view
     * was recreated, the fresh state came back false, and the sheet never
     * opened. */
    @Environment(\.presentSheet) private var present

    var body: some View {
        Button { present(.childPicker) } label: {
            HStack(spacing: 9) {
                ProfileAvatar(profile: app.activeProfile,
                              familyMode: app.familyMode, size: 30)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .scaledFont(compact ? 12.5 : 14.5, weight: .semibold)
                        .foregroundStyle(.primary)
                    /* The age and the allergies are the point of this pill —
                     * but only where it owns the line. Beside a title they
                     * would wrap it to two rows. */
                    if !compact {
                        Text(subtitle)
                            .scaledFont(11)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Image(systemName: "chevron.down")
                    .scaledFont(11, weight: .semibold)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, ownGlass ? 13 : 4)
            .padding(.vertical, ownGlass ? 8 : 2)
            .contentShape(Capsule())
        }
        .glassIf(ownGlass)
        .buttonStyle(.plain)
        .accessibilityLabel("\(title). \(subtitle). Tap to switch.")
    }

    private var title: String {
        app.familyMode
            ? String(localized: "Everyone")
            : app.activeProfile.firstName
    }

    private var subtitle: String {
        let p = app.activeProfile
        let names = app.allergenNames(p.allergens)
        if names.isEmpty {
            return String(format: String(localized: "%@ — no allergen avoided"),
                          Format.age(p.ageMonths))
        }
        return String(format: String(localized: "%@ — no %@"),
                      Format.age(p.ageMonths), Format.list(names))
    }
}

struct ProfileAvatar: View {
    let profile: ChildProfile
    var familyMode = false
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            Circle().fill(gradient)
            Circle().strokeBorder(.white.opacity(0.35), lineWidth: 0.75)
            if familyMode {
                Image(systemName: "person.2.fill")
                    .scaledFont(size * 0.38, weight: .semibold)
                    .foregroundStyle(.white)
            } else {
                Text(String(profile.firstName.prefix(1)).uppercased())
                    .scaledFont(size * 0.40, weight: .bold)
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: shadowTone.opacity(0.4), radius: size * 0.14, y: size * 0.09)
    }

    private var gradient: LinearGradient {
        LinearGradient(colors: familyMode
                       ? [Color(red: 0.50, green: 0.64, blue: 0.88),
                          Color(red: 0.23, green: 0.37, blue: 0.66)]
                       : [Tone.brand, Tone.brandDeep],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    private var shadowTone: Color { familyMode ? .blue : Tone.brandDeep }
}

// MARK: - Child picker

/// A sheet over the dimmed screen, not a tab. Every child carries their own
/// numbers, because that is what a parent wants to know looking at a profile.
struct ChildPickerSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    /// One row per child, plus family mode when there are two: "Who are you
    /// cooking for?" asked a question the parent had already answered by
    /// tapping the pill — and it reserved 60pt to do it.
    private var sheetHeight: CGFloat {
        let rows = CGFloat(app.profiles.count) * 92
        let family: CGFloat = app.profiles.count > 1 ? 138 : 0
        return min(76 + rows + family, 620)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                VStack(spacing: 0) {
                    ForEach(Array(app.profiles.enumerated()), id: \.element.id) { i, p in
                        Button {
                            app.select(p.id)
                            dismiss()
                        } label: {
                            PickerRow(profile: p,
                                      names: app.allergenNames(p.allergens),
                                      tally: app.tally(for: p),
                                      isOn: !app.familyMode && p.id == app.activeProfileID)
                        }
                        .buttonStyle(.plain)
                        if i < app.profiles.count - 1 {
                            Divider().overlay(Tone.hairline).padding(.leading, 74)
                        }
                    }
                }
                .card()
                .padding(.top, 18)

                if app.profiles.count > 1 {
                    Text("All at once").eyebrow().padding(.top, 24).padding(.bottom, 9)

                    Button {
                        app.toggleFamilyMode(true)
                        dismiss()
                    } label: {
                        FamilyRow(tally: app.tally(for: app.familyProfile),
                                  age: app.familyProfile.ageMonths,
                                  isOn: app.familyMode)
                    }
                    .buttonStyle(.plain)
                    .card()
                }
            }
            .padding(.horizontal, Layout.gutter)
            .padding(.bottom, 40)
        }
        .background(Tone.canvas)
        /* .medium froze the sheet at half the screen even with one child in
         * it. A height-based detent fits the content. */
        .presentationDetents([.height(sheetHeight), .large])
        .presentationCornerRadius(Layout.sheetRadius)
        .presentationDragIndicator(.visible)
    }
}

private struct PickerRow: View {
    let profile: ChildProfile
    let names: [String]
    let tally: AppState.ProfileTally
    let isOn: Bool

    var body: some View {
        HStack(spacing: 13) {
            ProfileAvatar(profile: profile)
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.firstName)
                    .scaledFont(16, weight: .semibold)
                    .foregroundStyle(Tone.text)
                Text(subtitle)
                    .scaledFont(Type.small)
                    .foregroundStyle(Tone.text2)
                    .lineLimit(2)
                TallyLine(tally: tally)
            }
            Spacer(minLength: 6)
            if isOn {
                Image(systemName: "checkmark")
                    .scaledFont(16, weight: .semibold)
                    .foregroundStyle(Tone.brand)
            }
        }
        .padding(15)
        .background(isOn ? Tone.brand.opacity(0.07) : .clear)
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        names.isEmpty
            ? String(format: String(localized: "%@ — no allergen avoided"), Format.age(profile.ageMonths))
            : String(format: String(localized: "%@ — no %@"), Format.age(profile.ageMonths), Format.list(names))
    }
}

private struct FamilyRow: View {
    let tally: AppState.ProfileTally
    let age: Int
    let isOn: Bool

    var body: some View {
        HStack(spacing: 13) {
            ZStack {
                Circle().fill(LinearGradient(
                    colors: [Color(red: 0.50, green: 0.64, blue: 0.88),
                             Color(red: 0.23, green: 0.37, blue: 0.66)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "person.2.fill")
                    .scaledFont(17, weight: .semibold)
                    .foregroundStyle(.white)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text("Family mode")
                    .scaledFont(16, weight: .semibold)
                    .foregroundStyle(Tone.text)
                /* Named and explained: the youngest age and the union of every
                 * allergen. The hard case in a real family, strict by
                 * construction. */
                Text(String(format: String(localized: "The youngest age (%@) and everything any of them avoids"),
                            Format.age(age)))
                    .scaledFont(Type.small)
                    .foregroundStyle(Tone.text2)
                    .lineLimit(2)
                TallyLine(tally: tally)
            }
            Spacer(minLength: 6)
            if isOn {
                Image(systemName: "checkmark")
                    .scaledFont(16, weight: .semibold)
                    .foregroundStyle(Tone.brand)
            }
        }
        .padding(15)
        .contentShape(Rectangle())
    }
}

/// Reassuring, and true: whatever the profile, the engine finds a way.
struct TallyLine: View {
    let tally: AppState.ProfileTally

    var body: some View {
        if tally.total > 0 {
            /* The distinction was never the parent's concern — what they want
             * to know when picking a child is how many recipes that profile
             * opens up. */
            HStack(spacing: 4) {
                Text("\(tally.total)").scaledFont(11.5, weight: .bold)
                Text("recipes").scaledFont(11.5)
            }
            .foregroundStyle(Tone.yes)
            .padding(.top, 3)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(tally.total) recipes")
        }
    }
}

// MARK: - Search

/// Three things every 2026 reference agrees on: the keyboard rises with the
/// sheet, the zero state is never blank, and five to eight suggestions is the
/// ceiling.
struct SearchSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.navigate) private var navigate

    @State private var query = ""
    @FocusState private var focused: Bool

    /// Tall enough to reach the keyboard, never taller than the screen. With
    /// recipes rather than chips there is enough to fill it — so it opens high
    /// and scrolls.
    private var sheetHeight: CGFloat {
        let entetes = CGFloat(groups.count) * 34
        let lignes = CGFloat(groups.reduce(0) { $0 + $1.dishes.count }) * 58
        return min(96 + entetes + lignes, 560)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            /* The field is the title: "Search" written above a search field
             * is a duplicate — the field already says what it is, and the row
             * it occupied was the height of two recipes. */
            field
                .padding(.horizontal, Layout.gutter)
                .padding(.top, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if query.isEmpty {
                        zeroState
                    } else if results.isEmpty {
                        noResults
                    } else {
                        resultList
                    }
                }
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Tone.canvas.ignoresSafeArea())
        /* Sized to its content, not full screen. */
        .presentationDetents(query.isEmpty ? [.height(sheetHeight)] : [.large])
        .presentationDragIndicator(.visible)
        .task {
            /* The keyboard rises with the sheet. A search that needs a second
             * tap on the field has already lost the gesture. */
            try? await Task.sleep(for: .milliseconds(120))
            focused = true
        }
    }

    private var field: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .scaledFont(12, weight: .medium)
                .foregroundStyle(Tone.text3)
            TextField("Recipes and ingredients", text: $query)
                .scaledFont(14)
                .foregroundStyle(Tone.text)
                .focused($focused)
                .submitLabel(.search)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .scaledFont(13)
                        .foregroundStyle(Tone.text3)
                }
                .buttonStyle(.plain)
            }
            Button("Cancel") { dismiss() }
                .scaledFont(13, weight: .semibold)
                .foregroundStyle(Tone.brand)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        /* Raised, not sunken. A white field on the canvas reads as the thing
         * you type into; a grey well reads as a disabled row. */
        .background(Tone.cardTop,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Tone.hairline, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
    }

    /// Recipes, not counts: "Ready as is · 2" is a number; a parent searching
    /// wants to SEE dishes.
    @ViewBuilder
    private var zeroState: some View {
        ForEach(groups, id: \.heading) { groupe in
            HStack(alignment: .firstTextBaseline) {
                Text(groupe.heading).eyebrow()
                Spacer(minLength: 0)
                Text("\(groupe.dishes.count)")
                    .scaledFont(10)
                    .foregroundStyle(Tone.text3)
            }
            .padding(.horizontal, Layout.gutter)
            .padding(.top, 18)

            ForEach(groupe.dishes, id: \.recipe.id) { pair in
                Button {
                    dismiss()
                    navigate(.recipe(pair.recipe.id))
                } label: {
                    RecipeRow(recipe: pair.recipe, result: pair.result)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// The cuts worth one tap, each carrying its recipes: swiftUI keeps the
    /// first and drops the second, which is why a heading could show a count
    /// with no rows under it.
    private var groups: [(heading: String, dishes: [(recipe: Recipe, result: AdaptedRecipe)])] {
        let weekPairs = app.weekRecipes.compactMap { r in
            app.resultFor(r).map { (recipe: r, result: $0) }
        }
        var out: [(heading: String, dishes: [(recipe: Recipe, result: AdaptedRecipe)])] = []
        var seen = Set<String>()

        func add(_ heading: String, _ dishes: [(recipe: Recipe, result: AdaptedRecipe)]) {
            let fresh = dishes.filter { !seen.contains($0.recipe.id) }
            guard !fresh.isEmpty else { return }
            out.append((heading, fresh))
            seen.formUnion(fresh.map(\.recipe.id))
        }

        /* What is planned for today, which is the question at five o'clock. */
        let todayIDs = Set(app.recipes(on: WeekDay.today).map(\.id))
        add(String(localized: "Tonight"),
               weekPairs.filter { todayIDs.contains($0.recipe.id) })

        /* Named for the child, because the verdict belongs to one profile. */
        add(String(format: String(localized: "Ready for %@"), app.activeProfile.name),
               weekPairs.filter { $0.result.status == .asIs })

        add(String(localized: "Under 20 minutes"),
               weekPairs.filter { ($0.recipe.timeMinutes ?? 99) <= 20 })

        /* Top rated reaches outside the window on purpose — it is the one cut
         * here that can surface a recipe this week does not carry. */
        add(String(localized: "Top rated"),
               app.topRated.compactMap { r in
                   app.resultFor(r).map { (recipe: r, result: $0) }
               })

        return out
    }



    private var results: [(recipe: Recipe, result: AdaptedRecipe)] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard q.count > 1 else { return [] }
        return app.recipes.filter { r in
            r.name.lowercased().contains(q)
                || r.ingredients.contains { $0.id.lowercased().contains(q) }
        }
        .prefix(20)
        .compactMap { r in app.resultFor(r).map { (recipe: r, result: $0) } }
    }

    private var resultList: some View {
        ForEach(results, id: \.recipe.id) { pair in
            Button {
                app.rememberSearch(query)
                dismiss()
                navigate(.recipe(pair.recipe.id))
            } label: {
                RecipeRow(recipe: pair.recipe, result: pair.result)
            }
            .buttonStyle(.plain)
        }
    }

    /// Never a dead end: the query is repeated so the parent sees what was
    /// searched, the closest recipes are offered, and there are terms to try.
    @ViewBuilder
    private var noResults: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(String(format: String(localized: "Nothing for “%@” this week"), query))
                .scaledFont(14, weight: .semibold)
                .foregroundStyle(Tone.text)
            Text("It may arrive in a later week. Meanwhile, these are close.")
                .scaledFont(12)
                .foregroundStyle(Tone.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Layout.gutter)
        .padding(.top, 22)

        Text("Closest").eyebrow()
            .padding(.horizontal, Layout.gutter).padding(.top, 20)

        ForEach(closest, id: \.recipe.id) { pair in
            Button {
                dismiss()
                navigate(.recipe(pair.recipe.id))
            } label: {
                RecipeRow(recipe: pair.recipe, result: pair.result)
            }
            .buttonStyle(.plain)
        }

    /* No "Try instead" chips: they pointed at Snacks, Meals and Breakfast
     * — three places already reachable, offered here only to fill the
     * space under a miss. */
    }

    /// The week's recipes, so a miss still ends on something cookable.
    private var closest: [(recipe: Recipe, result: AdaptedRecipe)] {
        app.weekRecipes.prefix(2).compactMap { r in
            app.resultFor(r).map { (recipe: r, result: $0) }
        }
    }
}

// MARK: - The week strip

/// Seven days, each showing what is planned on it: seven recipes already
/// arrive each week — the strip shows where they landed and lets the parent
/// move one, which is the only decision worth offering.
struct ChildTopBar: View {
    @Environment(AppState.self) private var app
    @State private var expanded = false

    /// The pill never yields its place. A sync message is a one-word chip
    /// beside it; a tap unfolds the full text under the row for a moment.
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                if let message = app.syncMessage {
                    Button {
                        withAnimation(.soft(0.22)) { expanded.toggle() }
                        if expanded {
                            Task {
                                try? await Task.sleep(for: .seconds(5))
                                withAnimation(.soft(0.22)) { expanded = false }
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Circle().fill(Tone.swap).frame(width: 6, height: 6)
                            Text(app.isOffline ? "Offline" : "Notice")
                                .scaledFont(11, weight: .semibold)
                                .foregroundStyle(Tone.swap)
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(Tone.swap.opacity(0.12), in: Capsule())
                        .overlay { Capsule().strokeBorder(Tone.swap.opacity(0.3), lineWidth: 0.5) }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(message))
                }
                CookingContextHeader(compact: true)
            }
            if expanded, let message = app.syncMessage {
                Text(message)
                    .scaledFont(11)
                    .foregroundStyle(Tone.swap)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Tone.swap.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, Layout.gutter)
    }
}

/// Seven days, for Shopping: recipes moved to a week rail, because a day pill
/// answered a question the list now answers by itself.
struct DayStrip: View {
    @Binding var selected: Int
    /// How many recipes sit on each day, for the dots.
    let counts: [Int]

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<7, id: \.self) { day in
                Button {
                    withAnimation(.soft(0.26)) {
                        selected = day
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    DayTile(day: day, selected: day == selected,
                            count: day < counts.count ? counts[day] : 0)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct DayTile: View {
    let day: Int
    let selected: Bool
    let count: Int

    var body: some View {
        VStack(spacing: 0) {
            Text(WeekDay.short[day])
                .scaledFont(8, weight: .bold, design: .monospaced)
                .kerning(0.8)
                .foregroundStyle(selected ? Tone.canvas.opacity(0.6) : Tone.text2)

            /* The day of the MONTH, not the index in the plan. "Mon 1" on a
             * Monday the 31st looked like a date and was not one. */
            Text("\(WeekDay.dayNumber(for: day))")
                .scaledFont(13.5, weight: .bold)
                .kerning(-0.3)
                .foregroundStyle(selected ? Tone.canvas : Tone.text)
                .padding(.top, 2)

            HStack(spacing: 2.5) {
                if count == 0 {
                    Capsule().frame(width: 9, height: 1.5)
                        .foregroundStyle(Tone.text.opacity(0.14))
                } else {
                    ForEach(0..<min(count, 3), id: \.self) { _ in
                        Circle().frame(width: 4, height: 4)
                            .foregroundStyle(selected ? Tone.canvas.opacity(0.85) : Tone.brand)
                    }
                }
            }
            .frame(height: 5)
            .padding(.top, 3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(selected ? AnyShapeStyle(Tone.text)
                               : AnyShapeStyle(Tone.text.opacity(0.042)))
        }
        .contentShape(.rect)
    }
}

/// Three weeks: the one before, this one, the one after: a locked week keeps
/// its count and shows a padlock.
struct WeekRail: View {
    @Binding var selected: Int
    let slots: [WeekSlot]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(slots) { slot in
                Button {
                    withAnimation(.soft(0.3)) {
                        selected = slot.offset
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    WeekTile(slot: slot, selected: slot.offset == selected)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct WeekTile: View {
    let slot: WeekSlot
    let selected: Bool

    private var title: LocalizedStringKey {
        switch slot.offset {
        case -1: return "Last week"
        case 0:  return "This week"
        default: return "Next week"
        }
    }

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .scaledFont(7.5, weight: .bold, design: .monospaced)
                .kerning(0.7)
                .textCase(.uppercase)
                .foregroundStyle(selected ? Tone.canvas.opacity(0.6) : Tone.text2)

            Text(slot.span())
                .scaledFont(12, weight: .bold)
                .kerning(-0.2)
                .foregroundStyle(selected ? Tone.canvas : Tone.text)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            if slot.unlocked {
                Text(String(format: String(localized: "%lld recipes"), slot.count))
                    .scaledFont(8)
                    .foregroundStyle(selected ? Tone.canvas.opacity(0.5) : Tone.text3)
                    .lineLimit(1)
            } else {
                HStack(spacing: 3) {
                    Image(systemName: "lock.fill").scaledFont(7)
                    Text("\(slot.count)").scaledFont(8, weight: .semibold)
                }
                .foregroundStyle(selected ? Tone.canvas.opacity(0.62) : Tone.text3)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(selected ? AnyShapeStyle(Tone.text)
                               : AnyShapeStyle(Tone.text.opacity(0.045)))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(selected ? .clear : Tone.hairline, lineWidth: 1)
        }
        .contentShape(.rect)
    }
}


// MARK: - Search, as a tab

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
         * and animates it; declaring our own would fight that. */
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
                    .scaledFont(10)
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

    /// The cuts worth one tap, each carrying its recipes: swiftUI keeps the
    /// first and drops the second, which is why a heading could show a count
    /// with no rows under it.
    private var groups: [(heading: String, dishes: [(recipe: Recipe, result: AdaptedRecipe)])] {
        let weekPairs = app.weekRecipes.compactMap { r in
            app.resultFor(r).map { (recipe: r, result: $0) }
        }
        var out: [(heading: String, dishes: [(recipe: Recipe, result: AdaptedRecipe)])] = []
        var seen = Set<String>()

        func add(_ heading: String, _ dishes: [(recipe: Recipe, result: AdaptedRecipe)]) {
            let fresh = dishes.filter { !seen.contains($0.recipe.id) }
            guard !fresh.isEmpty else { return }
            out.append((heading, fresh))
            seen.formUnion(fresh.map(\.recipe.id))
        }

        /* What is planned for today, which is the question at five o'clock. */
        let todayIDs = Set(app.recipes(on: WeekDay.today).map(\.id))
        add(String(localized: "Tonight"),
               weekPairs.filter { todayIDs.contains($0.recipe.id) })

        /* Named for the child, because the verdict belongs to one profile. */
        add(String(format: String(localized: "Ready for %@"), app.activeProfile.name),
               weekPairs.filter { $0.result.status == .asIs })

        add(String(localized: "Under 20 minutes"),
               weekPairs.filter { ($0.recipe.timeMinutes ?? 99) <= 20 })

        /* Top rated reaches outside the window on purpose — it is the one cut
         * here that can surface a recipe this week does not carry. */
        add(String(localized: "Top rated"),
               app.topRated.compactMap { r in
                   app.resultFor(r).map { (recipe: r, result: $0) }
               })

        return out
    }

    private var results: [(recipe: Recipe, result: AdaptedRecipe)] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard q.count > 1 else { return [] }
        return app.recipes.filter { r in
            r.name.lowercased().contains(q)
                || r.ingredients.contains { $0.id.lowercased().contains(q) }
        }
        .prefix(20)
        .compactMap { r in app.resultFor(r).map { (recipe: r, result: $0) } }
    }

    @ViewBuilder
    private var noResults: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(String(format: String(localized: "Nothing for “%@” this week"), query))
                .scaledFont(14, weight: .semibold)
                .foregroundStyle(Tone.text)
            Text("It may arrive in a later week. Meanwhile, these are close.")
                .scaledFont(12)
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
