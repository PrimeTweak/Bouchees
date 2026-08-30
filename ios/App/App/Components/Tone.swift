//  Tone.swift
//
//  THE VALUES FROM THE MOCKUP, IN ONE PLACE.
//
//  Every number here was measured off the HTML comp rather than guessed, so a
//  screen that reads "336pt of photo, faded over 290" in the design is 336 and
//  290 here too. Nothing in a view file carries a hex value or a magic number.
//
//  Three appearances: light, dark, and system. System is the default — the
//  parent already made that choice once at the OS level.
//
//  Colour rules that hold in both:
//    Backgrounds SHIFT, they do not invert. A lighter surface stays lighter in
//    dark; light comes from the sky and depth cues depend on it.
//    Text DOES invert.
//    Accents gain luminosity in dark: brighter, less saturated.

import SwiftUI

// MARK: - Appearance

enum AppTheme: String, CaseIterable, Codable {
    case system, light, dark

    var label: LocalizedStringKey {
        switch self {
        case .system: return "Auto"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    /// nil hands the decision back to iOS.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

// MARK: - Colour

enum Tone {

    // ---- surfaces ----

    /// The page. Warm near-black in dark: food photography glows against it
    /// instead of drowning in white.
    static let canvas = dyn(light: 0xFAF8F5, dark: 0x0A0908)

    /// Cards and rows, as a gradient — flat fills read as cheap at this size.
    static let cardTop = dyn(light: 0xFFFFFF, dark: 0x1A1715)
    static let cardBottom = dyn(light: 0xFBF9F6, dark: 0x131110)

    /// Hairlines. Barely there, and that is the point.
    static let hairline = dyn(light: 0xE9E3DB, dark: 0x2A2624, darkAlpha: 0.55)

    // ---- text ----

    static let text = dyn(light: 0x16130F, dark: 0xF2EFEA)
    static let text2 = dyn(light: 0x6E665F, dark: 0x9A928A)
    static let text3 = dyn(light: 0x9A928A, dark: 0x6E665F)

    // ---- verdicts ----
    // One meaning each. Nothing else touches them.

    static let yes = dyn(light: 0x1E9B4E, dark: 0x4EE07E)
    static let swap = dyn(light: 0xC77A0E, dark: 0xFFB84D)
    static let no = dyn(light: 0xD92B20, dark: 0xFF5B4F)

    // ---- brand ----
    // Actions, selection, the active tab. NEVER a verdict.

    static let brand = dyn(light: 0xE8593A, dark: 0xFF7A5C)
    /// Behind a drawing in the hero, where a photograph would otherwise be.
    /// Warm and deep enough that white text sits on it without a scrim doing
    /// all the work.
    static var heroField: LinearGradient {
        LinearGradient(colors: [dyn(light: 0xE8DCC8, dark: 0x2A211A),
                                dyn(light: 0xD4C4AA, dark: 0x15100C)],
                       startPoint: .top, endPoint: .bottom)
    }

    /// The label over a photo. Brighter than brand so it survives the veil.
    static let heroAccent = Color(red: 1, green: 0.66, blue: 0.56)
    static let brandDeep = dyn(light: 0xC0421F, dark: 0xD8452C)

    /// The gradient on a primary button. Two stops, top-lit.
    static var brandGradient: LinearGradient {
        LinearGradient(colors: [brand, brandDeep],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static var cardGradient: LinearGradient {
        LinearGradient(colors: [cardTop, cardBottom],
                       startPoint: .top, endPoint: .bottom)
    }

    // ---- names the rest of the app already uses ----
    // Kept as aliases rather than renamed everywhere: a rename that touches
    // twenty call sites is twenty chances to miss one, and I missed six.

    static var surface: Color { cardTop }
    static var raised: Color { cardTop }
    static var textSecondary: Color { text2 }
    static var textTertiary: Color { text3 }

    /// Verdict washes, for banners and cards that carry a status.
    static let yesWash = dyn(light: 0xEFF6F1, dark: 0x0F2214)
    static let swapWash = dyn(light: 0xFDF5E9, dark: 0x2A1E0A)
    static let noWash = dyn(light: 0xFDF0EF, dark: 0x2A0F0D)
    static let brandWash = dyn(light: 0xFAEEF2, dark: 0x2A1119)

    private static func dyn(light: UInt32, dark: UInt32, darkAlpha: Double = 1) -> Color {
        Color(UIColor { t in
            t.userInterfaceStyle == .dark
                ? UIColor(hex: dark, alpha: darkAlpha)
                : UIColor(hex: light)
        })
    }
}

private extension UIColor {
    convenience init(hex: UInt32, alpha: Double = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}

// MARK: - Type

/// iOS styles text by WEIGHT and COLOUR, not by size. These are the sizes from
/// the comp, and they map onto the platform's own scale: 34 for a large title,
/// 17 for body, 11 as the floor.
enum Type {
    static let display = Font.system(size: 34, weight: .bold)
    static let displayTight = Font.system(size: 31, weight: .bold)
    static let figure = Font.system(size: 29, weight: .bold)
    static let title = Font.system(size: 16.5, weight: .semibold)
    static let body = Font.system(size: 17)
    static let secondary = Font.system(size: 15)
    static let caption = Font.system(size: 13)
    static let small = Font.system(size: 12)
    static let label = Font.system(size: 11, weight: .bold)
}

extension View {
    /// The tracked, uppercase label used above every section.
    func eyebrow(_ tone: Color = Tone.text3) -> some View {
        self.font(Type.label)
            .textCase(.uppercase)
            .kerning(1.9)
            .foregroundStyle(tone)
    }
}

// MARK: - Layout

enum Layout {
    /// iOS 26 insets the tab bar 21pt from the edges.
    static let tabInset: CGFloat = 21
    static let tabBottom: CGFloat = 26
    static let gutter: CGFloat = 22
    static let tap: CGFloat = 44
    /// The name the rest of the app uses.
    static var tapTarget: CGFloat { tap }

    /// Photo heights, measured off the comp.
    static let heroPhoto: CGFloat = 430
    static let detailPhoto: CGFloat = 430
    /// How far the photo fades into the canvas.
    static let photoFade: CGFloat = 290
    /// The veil that keeps the status bar legible over an image.
    static let topVeil: CGFloat = 150

    static let cardRadius: CGFloat = 20
    /// The 2026 bento exaggerates the radius: tiles read as tactile rather
    /// than rectangular.
    static let tileRadius: CGFloat = 30
    static let sheetRadius: CGFloat = 30
    static let thumb: CGFloat = 66
    static let thumbRadius: CGFloat = 20
}

// MARK: - Liquid Glass

/// GLASS BELONGS TO THE NAVIGATION LAYER, AND NOWHERE ELSE.
///
/// Apple's guidance is explicit and most redesigns miss it: glass is not
/// applied to content layers like lists. Applied to every row the result is
/// translucent mush. It is for what FLOATS above content — the tab bar, a
/// button over a photo, the verdict pill.
///
/// On iOS 26 the material is native: `.glassEffect` carries the highlight, the
/// shadow, the illumination AND the real refraction from Apple's renderer.
/// What follows is the fallback for iOS 17-25, built the same way the comp is:
/// a specular line on the top edge, two drop shadows for separation, a diagonal
/// inner gradient for illumination.
struct Glass: ViewModifier {
    var shape: AnyShape = AnyShape(Capsule())
    var tinted: Bool = false

    /* NO `glassEffect` HERE, DELIBERATELY.
     *
     * The runner builds with Xcode 16.4, whose SDK is iOS 18.5. That API
     * ships with Xcode 26, so the symbol does not exist at compile time —
     * and `if #available(iOS 26, *)` guards RUNTIME, not compilation. The
     * compiler still has to find it.
     *
     * So the material is drawn by hand, the way the comp is. When the build
     * moves to Xcode 26, this whole body becomes one line.
     */
    @ViewBuilder
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        /* Xcode 26 and later: the real material. It carries the highlight,
         * the shadow, the illumination and Apple's own refraction — and, from
         * iOS 27, the user's transparency slider and the system's consistent
         * corner radius, both applied automatically to apps built against the
         * framework.
         *
         * The compiler check, not #available: the symbol has to EXIST at
         * compile time, and it does not in the iOS 18.5 SDK. */
        if #available(iOS 26, *) {
            content.glassEffect(tinted ? .regular.tint(Tone.brand.opacity(0.14))
                                       : .regular,
                                in: shape)
        } else {
            handDrawn(content)
        }
        #else
        handDrawn(content)
        #endif
    }

    /// The fallback for the iOS 18.5 SDK, built the way the comp is.
    private func handDrawn(_ content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: shape)
            .overlay {
                shape
                    .fill(LinearGradient(
                        colors: [.white.opacity(0.20), .white.opacity(0.05),
                                 .white.opacity(0.11)],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    .blendMode(.plusLighter)
            }
            .overlay {
                /* The specular line on the top edge. Without it the material
                 * reads as frosted plastic rather than glass.
                 *
                 * `stroke`, not `strokeBorder`: AnyShape erases the
                 * InsettableShape conformance that strokeBorder needs. The
                 * line straddles the edge instead of sitting inside it, which
                 * at 0.75pt is the same pixel. */
                shape.stroke(
                    LinearGradient(colors: [.white.opacity(0.55),
                                            .white.opacity(0.14),
                                            .white.opacity(0.30)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 0.75)
            }
            .overlay {
                if tinted { shape.fill(Tone.brand.opacity(0.10)) }
            }
            .shadow(color: .black.opacity(0.42), radius: 17, y: 10)
            .shadow(color: .black.opacity(0.28), radius: 4, y: 2)
    }
}

extension View {
    func glass(_ shape: some Shape = Capsule(), tinted: Bool = false) -> some View {
        modifier(Glass(shape: AnyShape(shape), tinted: tinted))
    }

    /// A card: not glass. Content layers get a gradient fill and a hairline.
    /// A bento tile: the card treatment at the larger radius.
    func tile() -> some View { card(Layout.tileRadius) }

    func card(_ radius: CGFloat = Layout.cardRadius) -> some View {
        self
            .background(Tone.cardGradient,
                        in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Tone.hairline, lineWidth: 1)
            }
    }
}

// MARK: - Photo treatment

/// The gradient that fades a photo into the canvas, and the veil that keeps the
/// status bar legible over it. Both are in the comp; both have a job.
struct PhotoScrim: View {
    var fade: CGFloat = Layout.photoFade

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                LinearGradient(colors: [.black.opacity(0.52), .clear],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: Layout.topVeil)
                Spacer(minLength: 0)
            }
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                LinearGradient(
                    stops: [.init(color: .clear, location: 0),
                            .init(color: Tone.canvas.opacity(0.55), location: 0.42),
                            .init(color: Tone.canvas, location: 0.88)],
                    startPoint: .top, endPoint: .bottom)
                    .frame(height: fade)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Verdict

/// Shape before colour. A filled dot for yes, a ring for a swap — readable for
/// the 8% of men with colour vision deficiency, and in direct sunlight.
struct VerdictMark: View {
    let status: RecipeStatus
    var size: CGFloat = 10

    var body: some View {
        Group {
            switch status {
            case .asIs:
                Circle().fill(Tone.yes)
                    .shadow(color: Tone.yes.opacity(0.7), radius: 7)
            case .adapted:
                Circle().strokeBorder(Tone.swap, lineWidth: size * 0.26)
                    .shadow(color: Tone.swap.opacity(0.45), radius: 6)
            case .notAdaptable:
                Circle().fill(Tone.no)
            case .unknown:
                Circle().strokeBorder(Tone.text3, lineWidth: size * 0.26)
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
        case .unknown: return Tone.text3
        }
    }
}

// MARK: - Buttons

/// The primary action: a two-stop gradient, a specular top edge, and a shadow
/// in the brand's own colour. A flat fill reads as cheap at this size.
struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background {
                RoundedRectangle(cornerRadius: 19, style: .continuous)
                    .fill(Tone.brandGradient)
                    .overlay {
                        RoundedRectangle(cornerRadius: 19, style: .continuous)
                            .strokeBorder(.white.opacity(0.32), lineWidth: 0.75)
                    }
            }
            .shadow(color: Tone.brandDeep.opacity(0.42), radius: 16, y: 10)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.smooth(duration: 0.16), value: configuration.isPressed)
    }
}
