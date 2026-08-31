//  CookingContext.swift
//
//  The floating tab bar, the child picker, and the counted segments — the
//  three pieces that appear on more than one screen.

import SwiftUI

// MARK: - Tab bar

/// A GLASS CAPSULE, INSET 21pt, WITH A SEARCH ISLAND.
///


// MARK: - Context header

/// Who you are cooking for, over the hero photo. In a family with two children
/// on different profiles, cooking for the wrong one is the worst failure this
/// app can have — so it is never more than a glance away.
struct CookingContextHeader: View {
    /// Avatar and first name only.
    ///
    /// On a screen whose title already occupies the left of the bar, the full
    /// pill would take the whole line and push the content down.
    var compact: Bool = false

    /// Draw our own glass, or let the toolbar supply it.
    ///
    /// TWO REASONS THIS EXISTS, BOTH MEASURED.
    ///
    /// 1. iOS 26 gives toolbar items the material automatically. Carrying our
    ///    own on top produced two stacked capsules — the double outline.
    ///
    /// 2. A glass container swallows the first touch: `hitTest:` on it
    ///    returns itself (FB18201935, already hit on the detail screen four
    ///    times). That is why the pill needed two taps.
    var ownGlass: Bool = true

    @Environment(AppState.self) private var etat
    /* THE SHEET IS NOT OURS TO OWN.
     *
     * `.sheet` used to hang off this button. The button lives in the top
     * bar's overlay, which SwiftUI rebuilds whenever the layout shifts — and
     * it shifts as soon as content scrolls under it. So the first tap set the
     * flag, the view was recreated, the fresh state came back false, and the
     * sheet never opened. The second tap landed before the rebuild.
     *
     * The screen owns it now. This only asks. */
    @Environment(\.presentSheet) private var present
    var onDark: Bool = true

    var body: some View {
        Button { present(.childPicker) } label: {
            HStack(spacing: 9) {
                ProfileAvatar(profile: etat.activeProfile,
                              familyMode: etat.familyMode, size: 30)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(.system(size: compact ? 12.5 : 14.5, weight: .semibold))
                        .foregroundStyle(.primary)
                    /* The age and the allergies are the point of this pill —
                     * but only where it owns the line. Beside a title they
                     * would wrap it to two rows. */
                    if !compact {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
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
        etat.familyMode
            ? String(localized: "Everyone")
            : etat.activeProfile.firstName
    }

    private var subtitle: String {
        let p = etat.activeProfile
        let noms = etat.allergenNames(p.allergens)
        if noms.isEmpty {
            return String(format: String(localized: "%@ — no allergen avoided"),
                          Format.age(p.ageMonths))
        }
        return String(format: String(localized: "%@ — no %@"),
                      Format.age(p.ageMonths), Format.liste(noms))
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
                    .font(.system(size: size * 0.38, weight: .semibold))
                    .foregroundStyle(.white)
            } else {
                Text(String(profile.firstName.prefix(1)).uppercased())
                    .font(.system(size: size * 0.40, weight: .bold))
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
    @Environment(AppState.self) private var etat
    @Environment(\.dismiss) private var dismiss

    /// One row per child, plus family mode when there are two.
    ///
    /// No title. "Who are you cooking for?" asked a question the parent had
    /// already answered by tapping the pill — and it reserved 60pt to do it.
    private var sheetHeight: CGFloat {
        let rows = CGFloat(etat.profiles.count) * 92
        let family: CGFloat = etat.profiles.count > 1 ? 138 : 0
        return min(76 + rows + family, 620)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                VStack(spacing: 0) {
                    ForEach(Array(etat.profiles.enumerated()), id: \.element.id) { i, p in
                        Button {
                            etat.select(p.id)
                            dismiss()
                        } label: {
                            PickerRow(profile: p,
                                      noms: etat.allergenNames(p.allergens),
                                      tally: etat.tally(for: p),
                                      isOn: !etat.familyMode && p.id == etat.activeProfileID)
                        }
                        .buttonStyle(.plain)
                        if i < etat.profiles.count - 1 {
                            Divider().overlay(Tone.hairline).padding(.leading, 74)
                        }
                    }
                }
                .card()
                .padding(.top, 18)

                if etat.profiles.count > 1 {
                    Text("All at once").eyebrow().padding(.top, 24).padding(.bottom, 9)

                    Button {
                        etat.toggleFamilyMode(true)
                        dismiss()
                    } label: {
                        FamilyRow(tally: etat.tally(for: etat.familyProfile),
                                  age: etat.familyProfile.ageMonths,
                                  isOn: etat.familyMode)
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
    let noms: [String]
    let tally: AppState.ProfileTally
    let isOn: Bool

    var body: some View {
        HStack(spacing: 13) {
            ProfileAvatar(profile: profile)
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.firstName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Tone.text)
                Text(subtitle)
                    .font(Type.small)
                    .foregroundStyle(Tone.text2)
                    .lineLimit(2)
                TallyLine(tally: tally)
            }
            Spacer(minLength: 6)
            if isOn {
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Tone.brand)
            }
        }
        .padding(15)
        .background(isOn ? Tone.brand.opacity(0.07) : .clear)
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        noms.isEmpty
            ? String(format: String(localized: "%@ — no allergen avoided"), Format.age(profile.ageMonths))
            : String(format: String(localized: "%@ — no %@"), Format.age(profile.ageMonths), Format.liste(noms))
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
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text("Family mode")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Tone.text)
                /* Named and explained: the youngest age and the union of every
                 * allergen. The hard case in a real family, strict by
                 * construction. */
                Text(String(format: String(localized: "The youngest age (%@) and everything any of them avoids"),
                            Format.age(age)))
                    .font(Type.small)
                    .foregroundStyle(Tone.text2)
                    .lineLimit(2)
                TallyLine(tally: tally)
            }
            Spacer(minLength: 6)
            if isOn {
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .semibold))
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
            /* "3 ready · 12 swaps" outlived the segments it belonged to. The
             * distinction was never the parent's concern — what they want to
             * know when picking a child is how many recipes that profile
             * opens up. */
            HStack(spacing: 4) {
                Text("\(tally.total)").font(.system(size: 11.5, weight: .bold))
                Text("recipes").font(.system(size: 11.5))
            }
            .foregroundStyle(Tone.yes)
            .padding(.top, 3)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(tally.total) recipes")
        }
    }
}

// MARK: - Search

/// Search, with the keyboard already up and the empty state doing work.
///
/// Three things every 2026 reference agrees on: the keyboard rises with the
/// sheet, the zero state is never blank, and five to eight suggestions is the
/// ceiling. An empty screen with a cursor asks the parent to invent a query.
struct SearchSheet: View {
    @Environment(AppState.self) private var etat
    @Environment(\.dismiss) private var dismiss
    @Environment(\.navigate) private var navigate

    @State private var query = ""
    @FocusState private var focused: Bool

    /// Tall enough to reach the keyboard, never taller than the screen.
    ///
    /// The old sheet sat low and left a hole between the last chip and the
    /// keyboard. With recipes rather than chips there is enough to fill it —
    /// so it opens high and scrolls.
    private var sheetHeight: CGFloat {
        let entetes = CGFloat(groupes.count) * 34
        let lignes = CGFloat(groupes.reduce(0) { $0 + $1.plats.count }) * 58
        return min(96 + entetes + lignes, 560)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            /* THE FIELD IS THE TITLE.
             *
             * "Search" written above a search field is a duplicate — the
             * field already says what it is, and the row it occupied was the
             * height of two recipes. */
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
        /* SIZED TO ITS CONTENT, NOT FULL SCREEN.
         *
         * Without a detent the sheet rises to the top and leaves a hole
         * between the last chip and the keyboard — which is exactly the empty
         * space in the screenshot. It grows to `.large` once there are
         * results to scroll. */
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
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Tone.text3)
            TextField("Recipes and ingredients", text: $query)
                .font(.system(size: 14))
                .foregroundStyle(Tone.text)
                .focused($focused)
                .submitLabel(.search)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Tone.text3)
                }
                .buttonStyle(.plain)
            }
            Button("Cancel") { dismiss() }
                .font(.system(size: 13, weight: .semibold))
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

    /// Recipes, not counts.
    ///
    /// "Ready as is · 2" is a number; a parent searching wants to SEE dishes.
    /// The count becomes a section title and the recipes sit under it, with
    /// their thumbnail and their verdict — the same row used everywhere else.
    ///
    /// There are only seven recipes in a week. Showing them costs less than a
    /// filter you have to assemble.
    @ViewBuilder
    private var zeroState: some View {
        ForEach(groupes, id: \.titre) { groupe in
            HStack(alignment: .firstTextBaseline) {
                Text(groupe.titre).eyebrow()
                Spacer(minLength: 0)
                Text("\(groupe.plats.count)")
                    .font(.system(size: 10))
                    .foregroundStyle(Tone.text3)
            }
            .padding(.horizontal, Layout.gutter)
            .padding(.top, 18)

            ForEach(groupe.plats, id: \.recipe.id) { pair in
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

    /// The cuts worth one tap, each carrying its recipes.
    private var groupes: [(titre: String, plats: [(recipe: Recipe, result: AdaptedRecipe)])] {
        let semaine = etat.weekRecipes.compactMap { r in
            etat.resultFor(r).map { (recipe: r, result: $0) }
        }
        var out: [(titre: String, plats: [(recipe: Recipe, result: AdaptedRecipe)])] = []

        let pretes = semaine.filter { $0.result.status == .asIs }
        if !pretes.isEmpty {
            out.append((String(localized: "Ready as is"), pretes))
        }

        let rapides = semaine.filter { ($0.recipe.timeMinutes ?? 99) <= 20 }
        if !rapides.isEmpty {
            out.append((String(localized: "Under 20 minutes"), rapides))
        }

        /* Everything else, so the sheet never runs out before the keyboard. */
        let vus = Set((pretes + rapides).map(\.recipe.id))
        let reste = semaine.filter { !vus.contains($0.recipe.id) }
        if !reste.isEmpty {
            out.append((String(localized: "This week"), reste))
        }
        return out
    }



    private var results: [(recipe: Recipe, result: AdaptedRecipe)] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard q.count > 1 else { return [] }
        return etat.recipes.filter { r in
            r.name.lowercased().contains(q)
                || r.ingredients.contains { $0.id.lowercased().contains(q) }
        }
        .prefix(20)
        .compactMap { r in etat.resultFor(r).map { (recipe: r, result: $0) } }
    }

    private var resultList: some View {
        ForEach(results, id: \.recipe.id) { pair in
            Button {
                etat.rememberSearch(query)
                dismiss()
                navigate(.recipe(pair.recipe.id))
            } label: {
                RecipeRow(recipe: pair.recipe, result: pair.result)
            }
            .buttonStyle(.plain)
        }
    }

    /// Never a dead end.
    ///
    /// The query is repeated so the parent sees what was searched, the
    /// closest recipes are offered, and there are terms to try. A blank "no
    /// results" is the one thing every reference calls out.
    @ViewBuilder
    private var noResults: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(String(format: String(localized: "Nothing for “%@” this week"), query))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Tone.text)
            Text("It may arrive in a later week. Meanwhile, these are close.")
                .font(.system(size: 12))
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

        /* No "Try instead" chips.
         *
         * They pointed at Snacks, Meals and Breakfast — three places already
         * reachable, offered here only to fill the space under a miss. The
         * closest recipes above are the real answer, and they are cookable
         * tonight. */
    }

    /// The week's recipes, so a miss still ends on something cookable.
    private var closest: [(recipe: Recipe, result: AdaptedRecipe)] {
        etat.weekRecipes.prefix(2).compactMap { r in
            etat.resultFor(r).map { (recipe: r, result: $0) }
        }
    }
}

// MARK: - The week strip

/// Seven days, each showing what is planned on it.
///
/// NOT a planner to fill. Every comparison of meal-planning apps says the same
/// thing: handing someone an empty grid and a drag gesture turns dinner into
/// admin. Seven recipes already arrive each week — the strip shows where they
/// landed and lets the parent move one, which is the only decision worth
/// offering.
///
/// Two days are usually empty, and that stays true. Seven recipes do not make
/// seven suppers, and spreading them to look complete would be a lie about
/// what the app provides.
struct WeekStrip: View {
    @Environment(AppState.self) private var etat

    @Binding var selected: Int
    /// A recipe being dragged onto another day.
    @State private var dragging: String?

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<7, id: \.self) { jour in
                DayCell(day: jour,
                        selected: selected == jour,
                        today: jour == WeekDay.today,
                        recipes: etat.recipes(on: jour))
                    .contentShape(.rect)
                    .onTapGesture {
                        withAnimation(.smooth(duration: 0.24)) { selected = jour }
                    }
                    /* Drop target. Dragging a recipe from one day onto
                     * another is the whole editing model — no long press, no
                     * edit mode, no confirmation. */
                    .dropDestination(for: String.self) { ids, _ in
                        guard let id = ids.first,
                              let r = etat.weekRecipes.first(where: { $0.id == id })
                        else { return false }
                        withAnimation(.smooth(duration: 0.28)) {
                            etat.move(r, to: jour)
                            selected = jour
                        }
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        return true
                    }
            }
        }
    }
}

private struct DayCell: View {
    let day: Int
    let selected: Bool
    let today: Bool
    let recipes: [Recipe]

    var body: some View {
        VStack(spacing: 0) {
            Text(WeekDay.short[day])
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .kerning(0.8)
                .foregroundStyle(labelColour)

            Text("\(day + 1)")
                .font(.system(size: 13.5, weight: .bold))
                .kerning(-0.3)
                .foregroundStyle(selected ? Tone.canvas : Tone.text)
                .padding(.top, 2)

            /* One dot per recipe rather than a thumbnail: at this size a
             * picture is mud, and the count is the fact that matters. */
            HStack(spacing: 2.5) {
                if recipes.isEmpty {
                    Circle()
                        .strokeBorder(Tone.text.opacity(0.14), lineWidth: 1)
                        .frame(width: 5, height: 5)
                } else {
                    ForEach(recipes.prefix(3), id: \.id) { _ in
                        Circle()
                            .fill(selected ? Tone.canvas.opacity(0.8) : Tone.brand)
                            .frame(width: 5, height: 5)
                    }
                }
            }
            .frame(height: 6)
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(selected ? AnyShapeStyle(Tone.text)
                               : AnyShapeStyle(Tone.text.opacity(0.04)))
                .overlay {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(today && !selected ? Tone.brand.opacity(0.4)
                                                         : Tone.hairline,
                                      lineWidth: 1)
                }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(WeekDay.full[day]))
        .accessibilityValue(recipes.isEmpty
            ? Text("nothing planned")
            : Text(recipes.map(\.name).joined(separator: ", ")))
    }

    private var labelColour: Color {
        if selected { return Tone.canvas.opacity(0.6) }
        return today ? Tone.brand : Tone.text3
    }
}

// MARK: - Search, as a tab

/// The search destination behind `Tab(role: .search)`.
///
/// iOS owns the transition from the floating island into a search field —
/// that is what the role is for. This supplies what appears once the field is
/// active, and reuses the same groups the sheet showed: recipes, not counts.
struct SearchScreen: View {
    @Environment(AppState.self) private var etat
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
                            etat.rememberSearch(query)
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
        /* The system field, not one of ours. `Tab(role: .search)` places it
         * and animates it; declaring our own would fight that. */
        .searchable(text: $query, prompt: Text("Recipes and ingredients"))
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var zeroState: some View {
        ForEach(groupes, id: \.titre) { groupe in
            HStack(alignment: .firstTextBaseline) {
                Text(groupe.titre).eyebrow()
                Spacer(minLength: 0)
                Text("\(groupe.plats.count)")
                    .font(.system(size: 10))
                    .foregroundStyle(Tone.text3)
            }
            .padding(.horizontal, Layout.gutter)
            .padding(.top, 18)

            ForEach(groupe.plats, id: \.recipe.id) { pair in
                Button { navigate(.recipe(pair.recipe.id)) } label: {
                    RecipeRow(recipe: pair.recipe, result: pair.result)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var groupes: [(titre: String, plats: [(recipe: Recipe, result: AdaptedRecipe)])] {
        let semaine = etat.weekRecipes.compactMap { r in
            etat.resultFor(r).map { (recipe: r, result: $0) }
        }
        var out: [(titre: String, plats: [(recipe: Recipe, result: AdaptedRecipe)])] = []

        let pretes = semaine.filter { $0.result.status == .asIs }
        if !pretes.isEmpty { out.append((String(localized: "Ready as is"), pretes)) }

        let rapides = semaine.filter { ($0.recipe.timeMinutes ?? 99) <= 20 }
        if !rapides.isEmpty { out.append((String(localized: "Under 20 minutes"), rapides)) }

        let vus = Set((pretes + rapides).map(\.recipe.id))
        let reste = semaine.filter { !vus.contains($0.recipe.id) }
        if !reste.isEmpty { out.append((String(localized: "This week"), reste)) }
        return out
    }

    private var results: [(recipe: Recipe, result: AdaptedRecipe)] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard q.count > 1 else { return [] }
        return etat.recipes.filter { r in
            r.name.lowercased().contains(q)
                || r.ingredients.contains { $0.id.lowercased().contains(q) }
        }
        .prefix(20)
        .compactMap { r in etat.resultFor(r).map { (recipe: r, result: $0) } }
    }

    @ViewBuilder
    private var noResults: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(String(format: String(localized: "Nothing for “%@” this week"), query))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Tone.text)
            Text("It may arrive in a later week. Meanwhile, these are close.")
                .font(.system(size: 12))
                .foregroundStyle(Tone.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Layout.gutter)
        .padding(.top, 22)

        ForEach(etat.weekRecipes.prefix(2).compactMap { r in
            etat.resultFor(r).map { (recipe: r, result: $0) }
        }, id: \.recipe.id) { pair in
            Button { navigate(.recipe(pair.recipe.id)) } label: {
                RecipeRow(recipe: pair.recipe, result: pair.result)
            }
            .buttonStyle(.plain)
        }
    }
}
