//  Theme.swift
//
//  ONE SET OF TOKENS, THREE APPEARANCES.
//
//  Not two palettes to keep in sync — a set of names (surface, yes, swap) whose
//  values switch with the appearance. Nothing in the app ever mentions a hex
//  value, so light and dark cannot drift apart.
//
//  Three modes, not two: light, dark, and system. System is the default,
//  because the parent already made that decision once at the OS level.
//
//  Colour rules that hold in both:
//    - Backgrounds SHIFT, they do not invert. A lighter surface stays lighter
//      in dark mode. Light comes from the sky, and depth cues depend on it.
//    - Text DOES invert.
//    - Accents gain luminosity in dark: raise brightness, drop saturation.
//      #2E9E4F on white becomes #4ECB71 on black — same meaning, same contrast.
//
//  And one discipline the old palette broke: brand is for ACTIONS. The three
//  verdict colours are for verdicts. When the accent also means "this child",
//  a parent cannot tell an action from a state.

import SwiftUI

// MARK: - Appearance

enum AppTheme: String, CaseIterable, Codable, Sendable {
    case system, light, dark

    var label: LocalizedStringKey {
        switch self {
        case .system: return "Match iPhone"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    var symbol: String {
        switch self {
        case .system: return "iphone"
        case .light:  return "sun.max"
        case .dark:   return "moon"
        }
    }

    /// nil hands the decision back to the system.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

// MARK: - Tokens

/// Every colour in the app comes from here, named by role.
///
/// The `dynamic` helper resolves per trait collection, so a single token works
/// in light, dark, and in a view that is forced to one of them.
enum Tone {

    // ---- surfaces ----

    /// The page behind everything. Warm near-black in dark: food photography
    /// glows against it instead of drowning in white.
    static let canvas = dynamic(light: 0xF7F4F0, dark: 0x0A0908)

    /// Cards and rows. Shifted, not inverted.
    static let surface = dynamic(light: 0xFFFFFF, dark: 0x141211)

    /// A raised surface, one step above.
    static let raised = dynamic(light: 0xFFFFFF, dark: 0x1E1B19)

    /// Hairlines and dividers.
    static let hairline = dynamic(light: 0xE9E3DB, dark: 0x2A2624)

    // ---- text ----

    static let text = dynamic(light: 0x16130F, dark: 0xFFFFFF)
    static let textSecondary = Color.secondary
    static let textTertiary = Color.secondary.opacity(0.62)

    // ---- verdicts ----
    // These three mean one thing each. Nothing else touches them.

    /// Ready as is. A safe product.
    static let yes = dynamic(light: 0x2E9E4F, dark: 0x4ECB71)

    /// A swap happened. Age guidance.
    static let swap = dynamic(light: 0xC77A0E, dark: 0xF5A623)

    /// The refusal, and only the refusal. Red is earned.
    static let no = dynamic(light: 0xD92B20, dark: 0xFF453A)

    // ---- brand ----

    /// Actions, selection, the active tab. NEVER a verdict.
    static let brand = dynamic(light: 0xC42E56, dark: 0xF0577E)

    /// Behind brand-coloured text or icons.
    static let brandWash = dynamic(light: 0xFAEEF2, dark: 0x2A1119)

    // ---- verdict washes, for banners ----

    static let yesWash = dynamic(light: 0xEFF6F1, dark: 0x0F2214)
    static let swapWash = dynamic(light: 0xFDF5E9, dark: 0x2A1E0A)
    static let noWash = dynamic(light: 0xFDF0EF, dark: 0x2A0F0D)

    /// Resolves per appearance. UIColor is what carries a trait-aware value;
    /// SwiftUI's Color wraps it without losing that.
    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

// MARK: - Verdict

/// The colour and the shape for a status, in one place.
///
/// Shape carries the signal before colour does: a filled dot for yes, a ring
/// for a swap. That reads for the 8% of men with colour vision deficiency, and
/// it reads in direct sunlight in a grocery aisle.
struct VerdictMark: View {
    let status: RecipeStatus
    var size: CGFloat = 9

    var body: some View {
        Group {
            switch status {
            case .asIs:
                Circle().fill(Tone.yes)
            case .adapted:
                Circle().strokeBorder(Tone.swap, lineWidth: size * 0.28)
            case .notAdaptable:
                Circle().fill(Tone.no)
            case .unknown:
                Circle().strokeBorder(Tone.textTertiary, lineWidth: size * 0.28)
            }
        }
        .frame(width: size, height: size)
    }
}

extension RecipeStatus {
    var tone: Color {
        switch self {
        case .asIs: return Tone.yes
        case .adapted: return Tone.swap
        case .notAdaptable: return Tone.no
        case .unknown: return Tone.textTertiary
        }
    }

    var wash: Color {
        switch self {
        case .asIs: return Tone.yesWash
        case .adapted: return Tone.swapWash
        case .notAdaptable: return Tone.noWash
        case .unknown: return Tone.surface
        }
    }
}

// MARK: - Type

/// iOS styles text by WEIGHT and COLOUR, not by size. 17pt does most of the
/// work; the hierarchy comes from what sits around it.
///
/// The old app used eight sizes of the same face, which is why every screen
/// read flat — and several of them were below the 11pt floor, for text a parent
/// reads standing up, worried, sometimes one-handed.
enum Type {
    /// 34pt bold. Screen titles before scrolling.
    static let display = Font.system(size: 34, weight: .bold)
    /// The figure that carries the answer. One per screen.
    static let figure = Font.system(size: 30, weight: .bold)
    /// 17pt semibold. The title once scrolled, recipe names in a list.
    static let title = Font.system(size: 17, weight: .semibold)
    /// 17pt. Body, list rows, input.
    static let body = Font.system(size: 17)
    /// 15pt. Supporting text.
    static let secondary = Font.system(size: 15)
    /// 13pt. Captions, reasons.
    static let caption = Font.system(size: 13)
    /// 11pt. The floor, and only for labels.
    static let label = Font.system(size: 11, weight: .semibold)
}

// MARK: - Glass

/// LIQUID GLASS BELONGS TO THE NAVIGATION LAYER ONLY.
///
/// Apple's guidance is explicit and most redesigns get it wrong: glass is not
/// applied to content layers like lists. Applied to every row, the result is a
/// translucent mush. It is for what FLOATS above content — tab bars, toolbars,
/// floating buttons.
///
/// So in this app glass appears in exactly three places: the tab bar capsule,
/// the round buttons over a photo, and the verdict pill.
struct GlassCapsule: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.22), radius: 14, y: 6)
    }
}

struct GlassCircle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(width: 38, height: 38)
            .background(.ultraThinMaterial, in: Circle())
            .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
    }
}

extension View {
    func glassCapsule() -> some View { modifier(GlassCapsule()) }
    func glassCircle() -> some View { modifier(GlassCircle()) }
}

// MARK: - Layout

enum Layout {
    /// iOS 26 insets the tab bar 21pt from the edges.
    static let tabInset: CGFloat = 21
    /// Every tap target, without exception.
    static let tapTarget: CGFloat = 44
    static let gutter: CGFloat = 20
    static let cardRadius: CGFloat = 16
    static let sheetRadius: CGFloat = 26
}
