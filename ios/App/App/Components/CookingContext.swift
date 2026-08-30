//  CookingContext.swift
//
//  WHO YOU ARE COOKING FOR, ON EVERY SCREEN.
//
//  This was a tab. A tab you had to visit to learn which child the app was
//  filtering for — and in a family with two children on different allergen
//  profiles, a screen that does not say who it is filtering for is a screen
//  that can lie. Cooking for the wrong child is the worst failure this app can
//  have, and it was one forgotten tap away.
//
//  So it becomes a header: name, age, what is avoided, always in view. Tapping
//  it opens the picker as a sheet, and you come back exactly where you were.

import SwiftUI

// MARK: - The header

/// Sits above the content on every screen that depends on a profile.
struct CookingContextHeader: View {
    @Environment(AppState.self) private var etat
    @State private var showPicker = false

    var body: some View {
        Button {
            showPicker = true
        } label: {
            HStack(spacing: 10) {
                ProfileAvatar(profile: etat.activeProfile, familyMode: etat.familyMode)

                VStack(alignment: .leading, spacing: 1) {
                    /* Built as a String first. A ternary inside Text() leaves
                     * the compiler choosing between Text(String) and
                     * Text(LocalizedStringKey), and that ambiguity produces an
                     * error that names the expression rather than the line. */
                    Text(titleLine)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.primary)

                    Text(contextLine)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(titleLine + ". " + contextLine))
        .sheet(isPresented: $showPicker) { ChildPickerSheet() }
    }

    private var titleLine: String {
        if etat.familyMode { return String(localized: "Cooking for everyone") }
        return String(format: String(localized: "Cooking for %@"), etat.activeProfile.firstName)
    }

    private var contextLine: String {
        let profile = etat.activeProfile
        let noms = etat.allergenNames(profile.allergens)
        if noms.isEmpty {
            return String(format: String(localized: "%@ — no allergen avoided"),
                          Format.age(profile.ageMonths))
        }
        return String(format: String(localized: "%@ — no %@"),
                      Format.age(profile.ageMonths), Format.liste(noms))
    }
}

/// The initial, or a pair of figures in family mode.
struct ProfileAvatar: View {
    let profile: ChildProfile
    var familyMode: Bool = false
    var size: CGFloat = 32

    var body: some View {
        ZStack {
            Circle().fill(familyMode ? Tone.swap : Tone.brand)
            if familyMode {
                Image(systemName: "person.2.fill")
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(.white)
            } else {
                Text(initiale)
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
    }

    private var initiale: String {
        String(profile.firstName.prefix(1)).uppercased()
    }
}

// MARK: - The picker

/// Opens from the header. Every child carries their own numbers, because that
/// is what a parent wants to know looking at a profile: how many recipes it
/// leaves them.
struct ChildPickerSheet: View {
    @Environment(AppState.self) private var etat
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(etat.profiles) { p in
                        Button {
                            etat.select(p.id)
                            dismiss()
                        } label: {
                            ChildPickerRow(profile: p,
                                           noms: etat.allergenNames(p.allergens),
                                           tally: etat.tally(for: p),
                                           isOn: !etat.familyMode && p.id == etat.activeProfileID)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if etat.profiles.count > 1 {
                    Section {
                        Button {
                            etat.toggleFamilyMode(true)
                            dismiss()
                        } label: {
                            FamilyModeRow(tally: etat.tally(for: etat.familyProfile),
                                          age: etat.familyProfile.ageMonths,
                                          isOn: etat.familyMode)
                        }
                        .buttonStyle(.plain)
                    } header: {
                        Text("All at once")
                    }
                }
            }
            .navigationTitle("Who are you cooking for?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct ChildPickerRow: View {
    let profile: ChildProfile
    let noms: [String]
    let tally: AppState.ProfileTally
    let isOn: Bool

    private var sousTitre: String {
        if noms.isEmpty {
            return String(format: String(localized: "%@ — no allergen avoided"),
                          Format.age(profile.ageMonths))
        }
        return String(format: String(localized: "%@ — no %@"),
                      Format.age(profile.ageMonths), Format.liste(noms))
    }

    var body: some View {
        HStack(spacing: 12) {
            ProfileAvatar(profile: profile, size: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text(profile.firstName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(sousTitre)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                TallyLine(tally: tally)
            }

            Spacer(minLength: 4)

            if isOn {
                Image(systemName: "checkmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Tone.brand)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

private struct FamilyModeRow: View {
    let tally: AppState.ProfileTally
    let age: Int
    let isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Tone.swap)
                Image(systemName: "person.2.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text("Family mode")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                /* Named and explained. This is the hard case in a real family,
                 * and it has to be strict by construction: the youngest age and
                 * the union of every allergen. */
                Text(String(format: String(localized: "The youngest age (%@) and everything any of them avoids"),
                            Format.age(age)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                TallyLine(tally: tally)
            }

            Spacer(minLength: 4)

            if isOn {
                Image(systemName: "checkmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Tone.brand)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

/// Reassuring, and true: whatever the profile, the engine finds a way.
struct TallyLine: View {
    let tally: AppState.ProfileTally

    var body: some View {
        if tally.total > 0 {
            HStack(spacing: 4) {
                Text("\(tally.asIs)").font(.caption2.weight(.bold)).foregroundStyle(Tone.yes)
                Text("ready").font(.caption2).foregroundStyle(.secondary)
                Text("·").font(.caption2).foregroundStyle(.tertiary)
                Text("\(tally.adapted)").font(.caption2.weight(.bold)).foregroundStyle(Tone.swap)
                Text("with swaps").font(.caption2).foregroundStyle(.secondary)
                if tally.blocked > 0 {
                    Text("·").font(.caption2).foregroundStyle(.tertiary)
                    Text("\(tally.blocked)").font(.caption2.weight(.bold)).foregroundStyle(Tone.no)
                    Text("blocked").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(.top, 2)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(tally.asIs) ready, \(tally.adapted) with swaps, \(tally.blocked) blocked")
        }
    }
}

// MARK: - Counted segments

/// "15 ready" is information. "Ready" is not.
///
/// The counts recompute whenever the profile changes, which is what makes the
/// engine's promise visible: a parent who just entered three allergens expects
/// a shortened list and finds out nothing was lost.
struct CountedSegments: View {
    @Binding var selection: RecipeFilter
    let tally: AppState.ProfileTally
    let savedCount: Int

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                segment(.all, count: tally.total, label: "All")
                segment(.ready, count: tally.asIs, label: "Ready")
                segment(.swaps, count: tally.adapted, label: "Swaps")
                if savedCount > 0 {
                    segment(.saved, count: savedCount, label: "Saved")
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func segment(_ f: RecipeFilter, count: Int, label: LocalizedStringKey) -> some View {
        let on = selection == f
        return Button {
            selection = f
        } label: {
            VStack(spacing: 1) {
                Text("\(count)")
                    .font(.subheadline.weight(.bold))
                Text(label)
                    .font(.caption2.weight(.medium))
            }
            .frame(minWidth: 62)
            .padding(.vertical, 7)
            /* Both branches of each ternary are the same concrete type.
             * `on ? Color(.systemBackground) : .secondary` asks the compiler to
             * unify a Color with a HierarchicalShapeStyle, which it will not
             * do — and the error it emits points at the whole expression
             * rather than the line. */
            .background(on ? Color.primary : Color(.secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .foregroundStyle(on ? Color(.systemBackground) : Color.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }
}

/// The filters a parent actually uses. Saved and top rated stop being tabs and
/// become two more ways to narrow one list.
enum RecipeFilter: String, CaseIterable, Sendable {
    case all, ready, swaps, saved
}

// MARK: - Floating tab bar

/// The iOS 26 tab bar: a glass capsule, inset from the edges, with content
/// scrolling underneath. Two to five destinations; three here.
///
/// The search island to the right is part of the same pattern — Apple moved
/// search to the bottom precisely because the top of a phone is hard to reach
/// one-handed, and this app is used one-handed by definition.
struct FloatingTabBar: View {
    @Binding var selection: Int
    @State private var searching = false

    private static let items: [(icon: String, label: LocalizedStringKey)] = [
        ("fork.knife", "Cook"),
        ("barcode.viewfinder", "Scan"),
        ("gearshape", "Settings")
    ]

    var body: some View {
        HStack(spacing: 9) {
            HStack(spacing: 0) {
                ForEach(Array(Self.items.enumerated()), id: \.offset) { i, item in
                    Button {
                        selection = i
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: item.icon)
                                .font(.system(size: 18, weight: selection == i ? .semibold : .regular))
                            Text(item.label)
                                .font(Type.label.weight(selection == i ? .semibold : .medium))
                        }
                        .foregroundStyle(selection == i ? Tone.brand : Tone.textTertiary)
                        .frame(maxWidth: .infinity)
                        .frame(height: Layout.tapTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == i ? [.isSelected] : [])
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 5)
            .glassCapsule()

            Button {
                searching = true
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Tone.textTertiary)
                    .glassCircle()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Search")
        }
        .sheet(isPresented: $searching) { SearchSheet() }
    }
}

/// Search opens as its own screen, per the platform pattern.
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
            List {
                ForEach(hits, id: \.recipe.id) { p in
                    RecipeRow(recipe: p.recipe, result: p.result)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Tone.canvas)
                }
            }
            .listStyle(.plain)
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
