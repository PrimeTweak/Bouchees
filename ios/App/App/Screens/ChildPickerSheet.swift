// ChildPickerSheet.swift
// The child picker behind the pill: one row per child, family mode when there are two.

import SwiftUI

/// A sheet over the dimmed screen, not a tab. Every child carries their own
/// numbers, because that is what a parent wants to know looking at a profile.
struct ChildPickerSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    /// One row per child, plus family mode when there are two. No heading:
    /// the pill just tapped already asks the question.
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
                    .scaledFont(Type.body, weight: .semibold)
                    .foregroundStyle(Tone.text)
                Text(subtitle)
                    .scaledFont(Type.caption)
                    .foregroundStyle(Tone.text2)
                    .lineLimit(2)
                TallyLine(tally: tally)
            }
            Spacer(minLength: 6)
            if isOn {
                Image(systemName: "checkmark")
                    .scaledFont(Type.body, weight: .semibold)
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
                    .scaledFont(Type.heading, weight: .semibold)
                    .foregroundStyle(.white)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text("Family mode")
                    .scaledFont(Type.body, weight: .semibold)
                    .foregroundStyle(Tone.text)
                /* Named and explained: the youngest age and the union of every
                 * allergen. The hard case in a real family, strict by
                 * construction. */
                Text(String(format: String(localized: "The youngest age (%@) and everything any of them avoids"),
                            Format.age(age)))
                    .scaledFont(Type.caption)
                    .foregroundStyle(Tone.text2)
                    .lineLimit(2)
                TallyLine(tally: tally)
            }
            Spacer(minLength: 6)
            if isOn {
                Image(systemName: "checkmark")
                    .scaledFont(Type.body, weight: .semibold)
                    .foregroundStyle(Tone.brand)
            }
        }
        .padding(15)
        .contentShape(Rectangle())
    }
}
