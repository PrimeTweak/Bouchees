// No milk on the list — fortified soy beverage instead, with an amber note
// saying what it replaces, so that standing in front of the shelf they know
// why.

import SwiftUI
/* UIImpactFeedbackGenerator. */
import UIKit

struct ShoppingScreen: View {
    @Environment(AppState.self) private var app
    @State private var checked: Set<String> = []

    /// Aisles the shopper has opened or closed by hand: only what was TOUCHED
    /// is stored.
    @State private var aisleOpened: [String: Bool] = [:]
    @State private var loaded = false

    /// The whole week, or one day when the strip is narrowed.
    private var items: [ShoppingItem] {
        dayFilter ? app.shoppingList(on: app.selectedDay) : app.shoppingList
    }

    /// Off by default: the week is the normal shopping trip, and a day is the
    /// exception asked for.
    @State private var dayFilter = false

    /// The staples — salt, oil, baking powder — sit in their own group at
    /// the end, "Check the pantry", rather than among the things to buy.
    private var byAisle: [(aisle: String, items: [ShoppingItem])] {
        let groups = Dictionary(grouping: items) { $0.staple == true ? "staples" : $0.aisle }
        return Self.aisleOrder.compactMap { a in
            guard let list = groups[a], !list.isEmpty else { return nil }
            return (a, list)
        }
    }

    private static let aisleOrder = ["produce", "protein", "refrigerated",
                                     "pantry", "frozen", "other", "staples"]

    /// What is actually bought: everything but the staples.
    private var toBuy: [ShoppingItem] { items.filter { $0.staple != true } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header

                /* The space the pill left behind: twelve go to the picker,
                 * ten to the gap above it, eight below — and the rest stays
                 * empty. */
                scopePicker
                    .padding(.horizontal, Layout.gutter)
                    .padding(.top, 24)

                /* Shown only in day mode. */
                if dayFilter {
                    weekStrip
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                progress
                ForEach(byAisle, id: \.aisle) { group in
                    /* A count per aisle, and a way to shut it: "1/6" tells a
                     * parent when they can leave the aisle, which is the only
                     * question being asked while standing in one. */
                    let open = isOpen(group)
                    Button {
                        withAnimation(.soft(0.28)) {
                            aisleOpened[group.aisle] = !open
                        }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: Self.aisleSymbol(group.aisle))
                                .scaledFont(Type.micro, weight: .medium)
                                .foregroundStyle(Tone.text2)
                                .frame(width: 20, height: 20)
                                .background(Tone.text.opacity(0.055),
                                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            Text(Self.aisleLabel(group.aisle)).eyebrow()
                            Spacer(minLength: 0)
                            Text("\(group.items.filter { checked.contains($0.id) }.count)/\(group.items.count)")
                                .scaledFont(Type.micro, weight: .semibold)
                                .foregroundStyle(Tone.text3)
                            Image(systemName: "chevron.right")
                                .scaledFont(Type.micro, weight: .semibold)
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
        /* The same bar as recipes: that is what lets the title sit at
         * `padding(.top, 8)` and land at the same height as Settings, while
         * the pill still shows top-trailing and stays there through the */
        .softTopBar { ChildTopBar() }
        .onAppear {
            guard !loaded else { return }
            checked = app.checkedItems
            loaded = true
        }
    }

    // MARK: - Pieces


    /// Pinned, it held the bar for a screen whose whole purpose is the list
    /// below it. The pill now rides in the floating top bar, which is an
    /// overlay: it does not push.
    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Shopping")
                .scaledFont(Type.display)
                .foregroundStyle(Tone.text)
            Text(subtitle)
                .scaledFont(Type.label)
                .foregroundStyle(Tone.text2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Layout.gutter)
        .padding(.top, 8)
    }

    /// The scale of the job, which is what this screen was missing.
    private var subtitle: String {
        String(format: String(localized: "%lld recipes · %lld items"),
               dayFilter ? app.recipes(on: app.selectedDay).count
                         : app.weekRecipes.count,
               toBuy.count)
    }

    /// Touching a day narrows the list to what that day needs.
    @ViewBuilder
    private var weekStrip: some View {
        @Bindable var e = app
        /* 20, the same gap the progress card takes under the picker in week
         * mode. It ran at 4, then at 12; both made the strip read as glued to
         * the control above rather than as the next row on the screen. */
        DayStrip(selected: $e.selectedDay,
                 counts: (0..<7).map { app.recipes(on: $0).count })
            .padding(.horizontal, Layout.gutter)
            .padding(.top, 20)
    }

    /// Scope first, then which day: two segments rather than one toggle: a
    /// button that changes its own label never says what the next tap will do.
    private var scopePicker: some View {
        HStack(spacing: 3) {
            ForEach([false, true], id: \.self) { byDay in
                Button {
                    withAnimation(.soft(0.26)) {
                        dayFilter = byDay
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Text(byDay ? "By day" : "Whole week")
                        .scaledFont(Type.secondary, weight: .semibold)
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

    /// What is LEFT, not what is done: standing at the door of a shop, the
    /// question is how much is left to find — the number already in the basket
    /// is the one visible by looking down.
    private var progress: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("\(toBuy.filter { !checked.contains($0.id) }.count)")
                    .scaledFont(Type.display)
                    .kerning(-0.6)
                    .foregroundStyle(Tone.text)
                    .contentTransition(.numericText())
                Text("left to buy")
                    .scaledFont(Type.caption, weight: .semibold)
                    .foregroundStyle(Tone.text)
                Spacer(minLength: 0)
                Text(String(format: String(localized: "%lld in the cart"),
                            toBuy.filter { checked.contains($0.id) }.count))
                    .scaledFont(Type.micro)
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
        .animation(.soft(0.3), value: checked.count)
    }

    private var ratio: CGFloat {
        toBuy.isEmpty ? 0 : CGFloat(toBuy.filter { checked.contains($0.id) }.count) / CGFloat(toBuy.count)
    }

    /// Whether an aisle shows its rows: a hand-set answer wins, in both
    /// directions — that is what makes a finished aisle re-openable.
    private func isOpen(_ group: (aisle: String, items: [ShoppingItem])) -> Bool {
        if let choix = aisleOpened[group.aisle] { return choix }
        return !group.items.allSatisfy { checked.contains($0.id) }
    }

    private func toggle(_ item: ShoppingItem) {
        withAnimation(.soft(0.2)) {
            if checked.contains(item.id) { checked.remove(item.id) }
            else { checked.insert(item.id) }
        }
        app.saveCheckedItems(checked)
    }

    /// One symbol per aisle, mirroring `aisleLabel`: a shop is navigated by
    /// section, and a glyph is read faster than a word while walking.
    private static func aisleSymbol(_ a: String) -> String {
        switch a {
        case "produce": return "carrot.fill"
        case "protein": return "fish.fill"
        case "refrigerated": return "thermometer.snowflake"
        case "pantry": return "cabinet.fill"
        case "staples": return "checkmark.seal"
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
        case "staples": return "Check the pantry"
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
        Button {
            /* Confirms without looking: the light tap the scanner uses. */
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            tap()
        } label: {
            HStack(alignment: .top, spacing: 13) {
                checkbox

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .scaledFont(Type.body)
                        .foregroundStyle(done ? Tone.text3 : Tone.text)
                        .strikethrough(done, color: Tone.text3)
                        .multilineTextAlignment(.leading)

                    if !item.quantityLabel.isEmpty {
                        Text(item.quantityLabel)
                            .scaledFont(Type.caption, design: .monospaced)
                            .foregroundStyle(Tone.text2)
                    }

                    /* The reason, where the parent needs it: in front of the
                     * shelf, not back in the recipe. */
                    if let replaces = item.replaces {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.triangle.swap")
                                .scaledFont(Type.micro, weight: .bold)
                            Text(String(format: String(localized: "replaces %@"), replaces))
                                .scaledFont(Type.micro, weight: .semibold)
                        }
                        .foregroundStyle(Tone.swap)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(Tone.swap.opacity(0.10), in: Capsule())
                        .padding(.top, 2)
                    }

                    /* Why there is so much of it, and what is lost by
                     * skipping it. */
                    if item.recipes.count > 1 {
                        Text(item.recipes.joined(separator: " · "))
                            .scaledFont(Type.label)
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

    /// 24pt, drawn in text2 so the outline clears AA; the whole row is the
    /// target, and a tick fills in the verdict green.
    private var checkbox: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(done ? .clear : Tone.text2, lineWidth: 1.8)
            if done {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Tone.yes)
                Image(systemName: "checkmark")
                    .scaledFont(Type.label, weight: .bold)
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 24, height: 24)
        .animation(.soft(0.18), value: done)
    }
}
