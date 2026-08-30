//  CookingContext.swift
//
//  The floating tab bar, the child picker, and the counted segments — the
//  three pieces that appear on more than one screen.

import SwiftUI

// MARK: - Tab bar

/// A GLASS CAPSULE, INSET 21pt, WITH A SEARCH ISLAND.
///
/// iOS 26 detached the tab bar from the screen edges: a pill floating over the
/// content, which scrolls beneath it and fades out at the bottom. Search sits
/// in its own circle to the right — Apple moved it to the bottom precisely
/// because the top of a phone is hard to reach one-handed, and this app is
/// used one-handed by definition.
struct FloatingTabBar: View {
    @Binding var selection: Int
    @State private var searching = false
    @Namespace private var glassSpace

    private static let items: [(icon: String, label: LocalizedStringKey)] = [
        ("fork.knife", "Recipes"),
        ("barcode.viewfinder", "Scan"),
        ("gearshape", "Settings")
    ]

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 0) {
                ForEach(Array(Self.items.enumerated()), id: \.offset) { i, item in
                    TabItem(icon: item.icon, label: item.label,
                            selected: selection == i) {
                        withAnimation(.smooth(duration: 0.22)) { selection = i }
                    }
                }
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 8)
            .glass(Capsule())

            Button { searching = true } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(Tone.text2)
                    .frame(width: 54, height: 54)
                    .glass(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Search")
        }
        .padding(.horizontal, Layout.tabInset)
        .padding(.bottom, Layout.tabBottom)
        .sheet(isPresented: $searching) { SearchSheet() }
    }
}

private struct TabItem: View {
    let icon: String
    let label: LocalizedStringKey
    let selected: Bool
    let tap: () -> Void

    var body: some View {
        Button(action: tap) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 21, weight: selected ? .semibold : .regular))
                Text(label)
                    .font(.system(size: 10.5, weight: selected ? .bold : .medium))
            }
            .foregroundStyle(selected ? Tone.brand : Tone.text2)
            .frame(maxWidth: .infinity)
            .frame(height: Layout.tap)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

// MARK: - Counted segments

/// "15" is information. "Ready" is not. The counts recompute whenever the
/// profile changes, which is what makes the engine's promise visible.
struct CountedSegments: View {
    @Binding var selection: RecipeFilter
    let tally: AppState.ProfileTally
    let savedCount: Int

    var body: some View {
        HStack(spacing: 7) {
            seg(.all, tally.total, "All")
            seg(.ready, tally.asIs, "Ready")
            seg(.swaps, tally.adapted, "Swaps")
            if savedCount > 0 { seg(.saved, savedCount, "Saved") }
        }
        .padding(.horizontal, Layout.gutter)
    }

    private func seg(_ f: RecipeFilter, _ n: Int, _ label: LocalizedStringKey) -> some View {
        let on = selection == f
        return Button {
            withAnimation(.smooth(duration: 0.2)) { selection = f }
        } label: {
            VStack(spacing: 1) {
                Text("\(n)")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(on ? Tone.canvas : Tone.text)
                    .contentTransition(.numericText())
                Text(label)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(on ? Tone.canvas.opacity(0.7) : Tone.text2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(on ? AnyShapeStyle(Tone.text) : AnyShapeStyle(Tone.text.opacity(0.05)))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(on ? .clear : Tone.hairline, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }
}

enum RecipeFilter: String, CaseIterable {
    case all, ready, swaps, saved
}

// MARK: - Context header

/// Who you are cooking for, over the hero photo. In a family with two children
/// on different profiles, cooking for the wrong one is the worst failure this
/// app can have — so it is never more than a glance away.
struct CookingContextHeader: View {
    @Environment(AppState.self) private var etat
    @State private var picking = false
    var onDark: Bool = true

    var body: some View {
        Button { picking = true } label: {
            HStack(spacing: 9) {
                ProfileAvatar(profile: etat.activeProfile,
                              familyMode: etat.familyMode, size: 30)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(onDark ? .white : Tone.text)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(onDark ? .white.opacity(0.7) : Tone.text2)
                        .lineLimit(1)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(onDark ? .white.opacity(0.6) : Tone.text3)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .glass(Capsule())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $picking) { ChildPickerSheet() }
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Who are you cooking for?")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Tone.text)
                    .padding(.top, 4)

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
        .presentationDetents([.medium, .large])
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
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Text("\(tally.asIs)").font(.system(size: 11.5, weight: .bold))
                    Text("ready").font(.system(size: 11.5))
                }
                .foregroundStyle(Tone.yes)

                Text("·").font(.system(size: 11.5)).foregroundStyle(Tone.text3)

                HStack(spacing: 4) {
                    Text("\(tally.adapted)").font(.system(size: 11.5, weight: .bold))
                    Text("swaps").font(.system(size: 11.5))
                }
                .foregroundStyle(Tone.swap)
            }
            .padding(.top, 3)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(tally.asIs) ready, \(tally.adapted) with swaps")
        }
    }
}

// MARK: - Search

struct SearchSheet: View {
    @Environment(AppState.self) private var etat
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var hits: [(recipe: Recipe, result: AdaptedRecipe)] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        return etat.pairs.filter { p in
            p.recipe.name.lowercased().contains(q)
                || p.recipe.category.lowercased().contains(q)
                || p.recipe.ingredients.contains { u in
                    (etat.definition(u.id)?.name ?? "").lowercased().contains(q)
                }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(hits, id: \.recipe.id) { p in
                        RecipeRow(recipe: p.recipe, result: p.result)
                        Divider().overlay(Tone.hairline)
                            .padding(.leading, Layout.gutter + Layout.thumb + 15)
                    }
                }
            }
            .background(Tone.canvas)
            .searchable(text: $query, prompt: Text("A recipe or an ingredient"))
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
