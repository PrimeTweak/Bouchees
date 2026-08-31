//  ShoppingScreen.swift
//
//  THE WEEK'S SHOPPING LIST, ALREADY ADAPTED.
//
//  Everything a parent buys for one batch. No milk on the list — fortified soy
//  beverage instead, with an amber note saying what it replaces, so that
//  standing in front of the shelf they know why.
//
//  Ordered by aisle, because a parent walks a store by section and a list
//  ordered any other way costs them laps. Quantities add only within the same
//  unit: the corpus mixes "125 ml" with "1 unit", and a total across those
//  would be a lie on a shopping list.

import SwiftUI
/* UIImpactFeedbackGenerator. */
import UIKit

struct ShoppingScreen: View {
    @Environment(AppState.self) private var etat
    @State private var checked: Set<String> = []

    /// Aisles the shopper has opened or closed by hand.
    ///
    /// Only what was TOUCHED is stored. An untouched aisle follows the rule —
    /// open while it still owes something, shut once everything in it is in
    /// the cart, which is the moment a shopper wants it out of the way. A tap
    /// records an answer here and that answer then wins, in both directions,
    /// so a finished aisle can always be opened again.
    ///
    /// Screen state, not disk: every aisle comes back open next launch.
    @State private var aisleOpened: [String: Bool] = [:]
    @State private var loaded = false

    /// The whole week, or one day when the strip is narrowed.
    private var items: [ShoppingItem] {
        dayFilter ? etat.shoppingList(on: etat.selectedDay) : etat.shoppingList
    }

    /// Off by default: the week is the normal shopping trip, and a day is the
    /// exception you ask for.
    @State private var dayFilter = false

    private var byAisle: [(aisle: String, items: [ShoppingItem])] {
        let groups = Dictionary(grouping: items, by: \.aisle)
        return Self.aisleOrder.compactMap { a in
            guard let list = groups[a], !list.isEmpty else { return nil }
            return (a, list)
        }
    }

    private static let aisleOrder = ["produce", "protein", "refrigerated",
                                     "pantry", "frozen", "other"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header

                /* THE SPACE THE PILL LEFT BEHIND.
                 *
                 * Moving it into the floating bar freed about 46pt. Twelve go
                 * to the picker, ten to the gap above it, eight below — and
                 * the rest stays empty. Filling a screen because there is room
                 * is how a screen gets heavy, and the real problem here is
                 * that seventeen of thirty items are cupboard staples. */
                scopePicker
                    .padding(.horizontal, Layout.gutter)
                    .padding(.top, 24)

                /* SHOWN ONLY IN DAY MODE.
                 *
                 * It used to sit at 42% opacity with hit testing off — seven
                 * dead tiles at full height, in a list whose whole job is to
                 * be short. */
                if dayFilter {
                    weekStrip
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                progress
                ForEach(byAisle, id: \.aisle) { group in
                    /* A COUNT PER AISLE, AND A WAY TO SHUT IT.
                     *
                     * "1/6" tells a parent when they can leave the aisle,
                     * which is the only question being asked while standing
                     * in one. The overall figure does not answer it.
                     *
                     * The whole header is the button. It carried 20pt of
                     * height and no action; it now runs the full tap target
                     * and folds its rows away. The count stays visible when
                     * shut, because the count is the reason to shut it. */
                    let open = isOpen(group)
                    Button {
                        withAnimation(.smooth(duration: 0.28)) {
                            aisleOpened[group.aisle] = !open
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: Self.aisleSymbol(group.aisle))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Tone.text2)
                                .frame(width: 20, height: 20)
                                .background(Tone.text.opacity(0.055),
                                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            Text(Self.aisleLabel(group.aisle)).eyebrow()
                            Spacer(minLength: 0)
                            Text("\(group.items.filter { checked.contains($0.id) }.count)/\(group.items.count)")
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(Tone.text3)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Tone.text3)
                                .rotationEffect(.degrees(open ? 90 : 0))
                        }
                        .frame(height: Layout.tapTarget)
                        .padding(.horizontal, Layout.gutter)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)

                    if open {
                        ForEach(group.items) { item in
                            ShoppingRow(item: item,
                                        done: checked.contains(item.id)) {
                                toggle(item)
                            }
                            if item.id != group.items.last?.id {
                                Divider().overlay(Tone.hairline)
                                    .padding(.leading, Layout.gutter + 35)
                            }
                        }
                        .transition(.opacity)
                    }
                }

                if items.isEmpty {
                    EmptyState(symbol: "cart",
                               title: "Nothing to buy yet",
                               message: "This week's recipes will fill the list.")
                        .padding(.top, 60)
                }
            }
            .padding(.bottom, 24)
        }
        .background(Tone.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        /* THE SAME BAR AS RECIPES.
         *
         * An overlay, not a safeAreaInset: it floats and the content scrolls
         * beneath it. That is what lets the title sit at `padding(.top, 8)`
         * and land at the same height as Settings, while the pill still shows
         * top-trailing and stays there through the scroll.
         *
         * The same 112 as Recipes. It ran at 88, which ended the fade above
         * the bottom of the pill: the two screens carried the same bar over
         * fields of different lengths, and the seam showed on this one. The
         * field is canvas over canvas, so the extra distance costs nothing
         * where there is nothing to cover. */
        .softTopBar { ChildTopBar() }
        .onAppear {
            guard !loaded else { return }
            checked = etat.checkedItems
            loaded = true
        }
    }

    // MARK: - Pieces


    /// The title, in the content, at the same size and place as Settings.
    ///
    /// It scrolls away like Settings' does. Pinned, it held the bar for a
    /// screen whose whole purpose is the list below it.
    /// The title, and nothing above it.
    ///
    /// The pill used to be the FIRST element of this stack, with the title
    /// underneath — so the title started about 50pt lower than Settings, and
    /// no padding value could fix that because the cause was the order.
    ///
    /// The pill now rides in the floating top bar, which is an overlay: it
    /// does not push. So the title is the first thing in the scroll, at
    /// `padding(.top, 8)`, exactly like Settings.
    ///
    /// "Shopping", not "Shopping list" — the tab says Shopping, and a screen
    /// that renames itself between the tab and the title is two names for one
    /// place.
    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Shopping")
                .font(Type.display)
                .foregroundStyle(Tone.text)
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(Tone.text2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Layout.gutter)
        .padding(.top, 8)
    }

    /// The scale of the job, which is what this screen was missing.
    ///
    /// It used to name the child — but the pill above already does, and the
    /// property was computed and never displayed. What a parent wants here is
    /// how big the list is before they walk into a shop.
    private var subtitle: String {
        String(format: String(localized: "%lld recipes · %lld items"),
               dayFilter ? etat.recipes(on: etat.selectedDay).count
                         : etat.weekRecipes.count,
               items.count)
    }

    /// Touching a day narrows the list to what that day needs.
    ///
    /// "What do I buy for Wednesday" is a real question in an aisle, and it
    /// was unanswerable — the list was the whole week or nothing.
    @ViewBuilder
    private var weekStrip: some View {
        @Bindable var e = etat
        /* 20, the same gap the progress card takes under the picker in week
         * mode. It ran at 4, then at 12; both made the strip read as glued to
         * the control above rather than as the next row on the screen. */
        DayStrip(selected: $e.selectedDay,
                 counts: (0..<7).map { etat.recipes(on: $0).count })
            .padding(.horizontal, Layout.gutter)
            .padding(.top, 20)
    }

    /// Scope first, then which day.
    ///
    /// Two segments rather than one toggle: a button that changes its own
    /// label never says what the next tap will do. Two segments show both
    /// states and which one is live.
    ///
    /// Above the days, because that is the order of the decision — whole week
    /// or one day, and only then which day. Underneath, it asked for the
    /// consequence before the cause.
    /// Full width, at the full tap target.
    ///
    /// It was 32, then `Layout.tapTarget - 6`. `Layout.tap` is 44, so the
    /// second value was 38 — still under Apple's minimum, while the comment
    /// beside it claimed 44. The height is now the constant itself, and the
    /// only arithmetic left is the 3pt trough the capsule sits in.
    ///
    /// `contentShape` because the unselected segment fills with a clear style:
    /// the day tiles beside it declare their shape and this did not, so half
    /// the control took taps only where the text was.
    private var scopePicker: some View {
        HStack(spacing: 3) {
            ForEach([false, true], id: \.self) { byDay in
                Button {
                    withAnimation(.smooth(duration: 0.26, extraBounce: 0.1)) {
                        dayFilter = byDay
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Text(byDay ? "By day" : "Whole week")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(dayFilter == byDay ? Tone.canvas : Tone.text2)
                        .frame(maxWidth: .infinity)
                        .frame(height: Layout.tapTarget)
                        .background(dayFilter == byDay ? AnyShapeStyle(Tone.text)
                                                       : AnyShapeStyle(Color.clear),
                                    in: Capsule())
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Tone.text.opacity(0.05), in: Capsule())
    }

    /// What is LEFT, not what is done.
    ///
    /// It read "4 of 30 in the cart". Standing at the door of a shop, the
    /// question is how much is left to find — the number already in the basket
    /// is the one you can see by looking down.
    private var progress: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("\(items.count - checked.count)")
                    .font(.system(size: 22, weight: .bold))
                    .kerning(-0.6)
                    .foregroundStyle(Tone.text)
                    .contentTransition(.numericText())
                Text("left to buy")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Tone.text)
                Spacer(minLength: 0)
                Text(String(format: String(localized: "%lld in the cart"), checked.count))
                    .font(.system(size: 10.5))
                    .foregroundStyle(Tone.text2)
                    .contentTransition(.numericText())
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Tone.text.opacity(0.08))
                    Capsule()
                        .fill(Tone.brandGradient)
                        .frame(width: geo.size.width * ratio)
                }
            }
            .frame(height: 5)
            .padding(.top, 9)
        }
        .padding(13)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Tone.text.opacity(0.035))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Tone.hairline, lineWidth: 1)
                }
        }
        .padding(.horizontal, Layout.gutter)
        .padding(.top, 20)
        .animation(.smooth(duration: 0.3), value: checked.count)
    }

    private var ratio: CGFloat {
        items.isEmpty ? 0 : CGFloat(checked.count) / CGFloat(items.count)
    }

    /// Whether an aisle shows its rows.
    ///
    /// A hand-set answer wins, in both directions — that is what makes a
    /// finished aisle re-openable. Untouched, an aisle stays open until every
    /// item in it is in the cart.
    private func isOpen(_ group: (aisle: String, items: [ShoppingItem])) -> Bool {
        if let choix = aisleOpened[group.aisle] { return choix }
        return !group.items.allSatisfy { checked.contains($0.id) }
    }

    private func toggle(_ item: ShoppingItem) {
        withAnimation(.smooth(duration: 0.2)) {
            if checked.contains(item.id) { checked.remove(item.id) }
            else { checked.insert(item.id) }
        }
        etat.saveCheckedItems(checked)
    }

    /// One symbol per aisle, mirroring `aisleLabel`.
    ///
    /// A shop is navigated by section, and a glyph is read faster than a word
    /// while walking. The two switches list the same cases, and the agreement
    /// checker holds them together.
    private static func aisleSymbol(_ a: String) -> String {
        switch a {
        case "produce": return "carrot.fill"
        case "protein": return "fish.fill"
        case "refrigerated": return "thermometer.snowflake"
        case "pantry": return "cabinet.fill"
        case "frozen": return "snowflake"
        default: return "bag.fill"
        }
    }

    private static func aisleLabel(_ a: String) -> LocalizedStringKey {
        switch a {
        case "produce": return "Produce"
        case "protein": return "Meat and fish"
        case "refrigerated": return "Refrigerated"
        case "pantry": return "Pantry"
        case "frozen": return "Frozen"
        default: return "Other"
        }
    }
}

// MARK: - Row

private struct ShoppingRow: View {
    let item: ShoppingItem
    let done: Bool
    let tap: () -> Void

    var body: some View {
        Button(action: tap) {
            HStack(alignment: .top, spacing: 13) {
                checkbox

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.system(size: 15.5))
                        .foregroundStyle(done ? Tone.text3 : Tone.text)
                        .strikethrough(done, color: Tone.text3)
                        .multilineTextAlignment(.leading)

                    if !item.quantityLabel.isEmpty {
                        Text(item.quantityLabel)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Tone.text2)
                    }

                    /* The reason, where the parent needs it: in front of the
                     * shelf, not back in the recipe. */
                    if let replaces = item.replaces {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.triangle.swap")
                                .font(.system(size: 9, weight: .bold))
                            Text(String(format: String(localized: "replaces %@"), replaces))
                                .font(.system(size: 10.5, weight: .semibold))
                        }
                        .foregroundStyle(Tone.swap)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(Tone.swap.opacity(0.10), in: Capsule())
                        .padding(.top, 2)
                    }

                    /* Why there is so much of it, and what you lose by
                     * skipping it. */
                    if item.recipes.count > 1 {
                        Text(item.recipes.joined(separator: " · "))
                            .font(.system(size: 11))
                            .foregroundStyle(Tone.text3)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, Layout.gutter)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(done ? [.isSelected] : [])
    }

    private var checkbox: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(done ? .clear : Tone.text.opacity(0.22), lineWidth: 1.8)
            if done {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Tone.text)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Tone.canvas)
            }
        }
        .frame(width: 22, height: 22)
        .padding(.top, 1)
    }
}
