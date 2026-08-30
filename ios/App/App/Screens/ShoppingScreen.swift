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

struct ShoppingScreen: View {
    @Environment(AppState.self) private var etat
    @State private var checked: Set<String> = []
    @State private var loaded = false

    private var items: [ShoppingItem] { etat.shoppingList }

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
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    progress
                    ForEach(byAisle, id: \.aisle) { group in
                        Text(Self.aisleLabel(group.aisle))
                            .eyebrow()
                            .padding(.horizontal, Layout.gutter)
                            .padding(.top, 24)
                            .padding(.bottom, 4)

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
            /* Who you are shopping for matters as much as who you are cooking
             * for — the list is adapted to them. */
            .topBar {
                HStack {
                    CookingContextHeader()
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Layout.gutter)
                .padding(.bottom, 6)
            }
            /* Below iOS 26 there is no scroll edge effect, so the last row
             * would read through the floating bar. Harmless where the effect
             * exists. */
            .bottomFade()
            .onAppear {
                guard !loaded else { return }
                checked = etat.checkedItems
                loaded = true
            }
        }
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Shopping list")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(Tone.text)
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(Tone.text2)
        }
        .padding(.horizontal, Layout.gutter)
        .padding(.top, 62)
    }

    private var subtitle: String {
        String(format: String(localized: "This week · %lld recipes · for %@"),
               etat.weekRecipes.count, etat.activeProfile.firstName)
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 9) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Tone.text.opacity(0.07))
                    Capsule()
                        .fill(Tone.brandGradient)
                        .frame(width: geo.size.width * ratio)
                }
            }
            .frame(height: 5)

            Text(String(format: String(localized: "%lld of %lld in the cart"),
                        checked.count, items.count))
                .font(.system(size: 11.5))
                .foregroundStyle(Tone.text2)
        }
        .padding(.horizontal, Layout.gutter)
        .padding(.top, 18)
        .animation(.smooth(duration: 0.3), value: checked.count)
    }

    private var ratio: CGFloat {
        items.isEmpty ? 0 : CGFloat(checked.count) / CGFloat(items.count)
    }

    private func toggle(_ item: ShoppingItem) {
        withAnimation(.smooth(duration: 0.2)) {
            if checked.contains(item.id) { checked.remove(item.id) }
            else { checked.insert(item.id) }
        }
        etat.saveCheckedItems(checked)
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
