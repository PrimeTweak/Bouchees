// Every number here was measured off the HTML comp rather than guessed, so a
// screen that reads "336pt of photo, faded over 290" in the design is 336 and
// 290 here too.

import SwiftUI
import UIKit

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

}

// MARK: - Colour

enum Tone {

    // ---- surfaces ----

    /// The page. Warm near-black in dark: food photography glows against it
    /// instead of drowning in white.
    static let canvas = dyn(light: 0xFBF9F6, dark: 0x0B0A09)

    /// Cards and rows, as a gradient — flat fills read as cheap at this size.
    static let cardTop = dyn(light: 0xFFFFFF, dark: 0x1A1715)
    static let cardBottom = dyn(light: 0xFBF9F6, dark: 0x131110)

    /// Hairlines. Barely there, and that is the point.
    static let hairline = dyn(light: 0xE9E3DB, dark: 0x2A2624, darkAlpha: 0.55)

    // ---- text ----

    static let text = dyn(light: 0x17140F, dark: 0xF4F1EC)       // 15.8:1
    static let text2 = dyn(light: 0x6B635A, dark: 0x948C83)      // 5.4:1
    /* 2.9:1 — under the body threshold ON PURPOSE. Reserved for quantities
     * beside a name that carries the meaning, never for a word standing
     * alone. */
    /* One shade darker than the comp: 4.6:1 on the canvas, so the smallest
     * text — eyebrows, the disclaimer — clears AA. */
    static let text3 = dyn(light: 0x7A7167, dark: 0x8E867D)

    // ---- verdicts ----
    // One meaning each. Nothing else touches them.

    /* Contrast ratios, measured on the canvas: the amber that shipped was
     * 1.9:1 — the DARK value used in light mode by mistake. */
    static let yes = dyn(light: 0x1E8347, dark: 0x5FD08A)      // 4.8:1 / 8.9:1
    static let swap = dyn(light: 0xA35F00, dark: 0xF0AC46)     // 4.8:1 / 9.4:1
    static let no = dyn(light: 0xC4291C, dark: 0xFF5B4F)       // 5.9:1 / 6.4:1

    // ---- brand ----
    // Actions, selection, the active tab. NEVER a verdict.

    static let brand = dyn(light: 0xC03A20, dark: 0xFF7A5C)      // 4.6:1 / 7.7:1
    /* The subscription card: warm peach rather than near-black: a dark card
     * on a cream page reads as a hole, and it crushed the meal chips
     * underneath. */
    static var upsellField: LinearGradient {
        LinearGradient(colors: [dyn(light: 0xFFF2EC, dark: 0x2A1D14),
                                dyn(light: 0xFFE6DC, dark: 0x171009)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static let upsellText = dyn(light: 0x3A2118, dark: 0xFFFFFF)
    static let upsellText2 = dyn(light: 0x8A6152, dark: 0xA89890)

    /// Behind a drawing in the hero, where a photograph would otherwise be.
    /// Warm and deep enough that white text sits on it without a scrim doing
    /// all the work.
    /* Fixed, not themed: these are constants. */
    static var heroField: LinearGradient {
        LinearGradient(colors: [Color(red: 0.29, green: 0.22, blue: 0.15),
                                Color(red: 0.10, green: 0.07, blue: 0.04)],
                       startPoint: .top, endPoint: .bottom)
    }

    /// The label over a photo. Brighter than brand so it survives the veil.
    static let heroAccent = Color(red: 1, green: 0.66, blue: 0.56)
    static let brandDeep = dyn(light: 0xC0421F, dark: 0xC03A20)

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
    // One helper rather than twenty call sites, so none is missed.

    static var surface: Color { cardTop }
    static var textSecondary: Color { text2 }
    static var textTertiary: Color { text3 }

    /// Verdict washes, for banners and cards that carry a status.
    static let yesWash = dyn(light: 0xEFF6F1, dark: 0x0F2214)
    static let swapWash = dyn(light: 0xFDF5E9, dark: 0x2A1E0A)
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

/// A type size from the comp, scaled with the phone's text size setting.
struct TypeSpec {
    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design
    init(_ size: CGFloat, _ weight: Font.Weight = .regular, _ design: Font.Design = .default) {
        self.size = size; self.weight = weight; self.design = design
    }
    /// The same size at another weight.
    func weight(_ w: Font.Weight) -> TypeSpec { TypeSpec(size, w, design) }
}

/// Eight sizes, by name. Every text in the app uses one of them; the weight
/// is the call site's. Nothing under ten points.
enum Type {
    static let display = TypeSpec(32, .bold)
    static let title = TypeSpec(22, .bold)
    static let heading = TypeSpec(17, .semibold)
    static let body = TypeSpec(15)
    static let secondary = TypeSpec(13)
    static let caption = TypeSpec(12)
    static let label = TypeSpec(11, .bold)
    static let micro = TypeSpec(10)
}

/// Scales a point size with Dynamic Type. Reads the environment so the view
/// re-renders when the setting changes; `Font.system(size:)` alone never scales.
struct ScaledFont: ViewModifier {
    let spec: TypeSpec
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        let metrics = UIFontMetrics(forTextStyle: Self.style(for: spec.size))
        return content.font(.system(size: metrics.scaledValue(for: spec.size),
                                    weight: spec.weight, design: spec.design))
    }

    /// The system text style whose scaling curve fits a point size.
    private static func style(for size: CGFloat) -> UIFont.TextStyle {
        switch size {
        case ..<12: return .caption2
        case ..<13: return .caption1
        case ..<14: return .footnote
        case ..<16: return .subheadline
        case ..<17: return .callout
        case ..<18: return .body
        case ..<21: return .title3
        case ..<23: return .title2
        case ..<29: return .title1
        default: return .largeTitle
        }
    }
}

extension View {
    func scaledFont(_ size: CGFloat, weight: Font.Weight = .regular,
                    design: Font.Design = .default) -> some View {
        modifier(ScaledFont(spec: TypeSpec(size, weight, design)))
    }
    func scaledFont(_ spec: TypeSpec) -> some View {
        modifier(ScaledFont(spec: spec))
    }
    func scaledFont(_ spec: TypeSpec, weight: Font.Weight, design: Font.Design = .default) -> some View {
        modifier(ScaledFont(spec: TypeSpec(spec.size, weight, design)))
    }
}

extension View {
    /// The tracked, uppercase label used above every section.
    func eyebrow(_ tone: Color = Tone.text3) -> some View {
        self.scaledFont(Type.label)
            .textCase(.uppercase)
            .kerning(1.9)
            .foregroundStyle(tone)
    }
}

// MARK: - Layout

enum Layout {
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

/// Glass belongs to the navigation layer, and nowhere else: apple's guidance
/// is explicit and most redesigns miss it: glass is not applied to content
/// layers like lists.
struct Glass: ViewModifier {
    var shape: AnyShape = AnyShape(Capsule())
    var tinted: Bool = false

    /* No `glassEffect` below the compiler check: the runner builds with
     * Xcode 16.4, whose SDK is iOS 18.5. */
    @ViewBuilder
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        /* It carries the highlight, the shadow, the illumination and Apple's
         * own refraction — and, from iOS 27, the user's transparency slider
         * and the system's consistent corner radius, both applied. */
        if #available(iOS 26, *) {
            /* `.interactive()` makes the material illuminate and spring at
             * the touch point. */
            content.glassEffect(tinted ? .regular.tint(Tone.brand.opacity(0.14)).interactive()
                                       : .regular.interactive(),
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
                /* The specular line on the top edge: without it the material
                 * reads as frosted plastic rather than glass. */
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
                /* The fade passes through black before it reaches canvas: it
                 * held only while every photo was a dark drawing. */
                LinearGradient(
                    stops: [.init(color: .clear, location: 0),
                            .init(color: .black.opacity(0.24), location: 0.26),
                            .init(color: .black.opacity(0.52), location: 0.44),
                            .init(color: .black.opacity(0.74), location: 0.62),
                            .init(color: .black.opacity(0.60), location: 0.74),
                            .init(color: Tone.canvas.opacity(0.55), location: 0.90),
                            .init(color: Tone.canvas, location: 1)],
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
            .scaledFont(Type.body, weight: .semibold)
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
            .animation(.soft(0.16), value: configuration.isPressed)
    }
}

// MARK: - Top bar

/// `safeAreaBar` is the iOS 26 modifier for this. Below that it falls back to
/// `safeAreaInset`, which reserves the space but does not carry the edge
/// effect — acceptable, because the effect itself is an iOS 26 feature.
struct TopBar<Bar: View>: ViewModifier {
    /* No `@ViewBuilder` on this stored property: the attribute makes the
     * memberwise initialiser take `() -> Bar` rather than `Bar`, so
     * `TopBar(bar: bar())` passed a value where a closure was expected. */
    let bar: Bar

    @ViewBuilder
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26, *) {
            content.safeAreaBar(edge: .top) { bar }
        } else {
            content.safeAreaInset(edge: .top) { bar }
        }
        #else
        content.safeAreaInset(edge: .top) { bar }
        #endif
    }
}

extension View {
}

// MARK: - The soft top bar

/// A top bar that fades out instead of ending on a line: a plain background
/// stops at a hard edge, and so does an unmasked `backdrop-filter`: blurring a
/// strip and cutting it produces a SECOND line where the blur ends.
struct SoftTopBar<Bar: View>: ViewModifier {
    let bar: Bar
    var height: CGFloat = 112

    /// How much of the extension is drawn, 0 at rest and 1 once scrolled.
    @State private var reveal: CGFloat = 0

    /// The distance over which the extension arrives. A third of a flick:
    /// long enough not to snap, short enough that the first row never meets
    /// the status bar undressed.
    private let travel: CGFloat = 24

    func body(content: Content) -> some View {
        tracked(content).overlay(alignment: .top) {
            ZStack(alignment: .top) {
                /* It spans the safe area and stops there, so it covers the
                 * clock, the signal and the battery and reaches no content: a
                 * scroll view starts BELOW the inset, so a title cannot. */
                field(height: SafeArea.top, cutoff: 0.62)

                /* The extension: only while content passes under it. */
                field(height: height, cutoff: 1)
                    .opacity(reveal)

                /* Applying the modifier to the ZStack gave it to both, so
                 * `padding(.top, 46)` measured from the physical edge — and a
                 * Dynamic Island occupies 59. */
                bar
                    .padding(.top, 4)
            }
        }
    }

    /// One layer of the field. `cutoff` is where the fall-off finishes, as a
    /// fraction of the height — the strip dies early so it clears the title,
    /// the extension runs the full distance.
    private func field(height: CGFloat, cutoff: CGFloat) -> some View {
        LinearGradient(
            stops: [
                .init(color: Tone.canvas.opacity(0.99), location: 0),
                .init(color: Tone.canvas.opacity(0.97), location: 0.30 * cutoff),
                .init(color: Tone.canvas.opacity(0.86), location: 0.52 * cutoff),
                .init(color: Tone.canvas.opacity(0.56), location: 0.70 * cutoff),
                .init(color: Tone.canvas.opacity(0.24), location: 0.85 * cutoff),
                .init(color: Tone.canvas.opacity(0), location: cutoff),
                .init(color: Tone.canvas.opacity(0), location: 1)
            ],
            startPoint: .top, endPoint: .bottom)
            .background(.ultraThinMaterial)
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.48 * cutoff),
                        .init(color: .black.opacity(0.6), location: 0.74 * cutoff),
                        .init(color: .clear, location: cutoff),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top, endPoint: .bottom)
            }
            .frame(height: height)
            /* The FIELD ignores the safe area — filling to the edge is its
             * whole job. */
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
    }

    /// Reads the scroll offset where the system offers it:
    /// `onScrollGeometryChange` is iOS 18 and the deployment target is 17.
    @ViewBuilder
    private func tracked(_ content: Content) -> some View {
        if #available(iOS 18, *) {
            content.onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, offset in
                let next = min(max(offset / travel, 0), 1)
                if abs(next - reveal) > 0.01 { reveal = next }
            }
        } else {
            content.onAppear { reveal = 1 }
        }
    }
}

/// The window's top inset: 59 on a Dynamic Island, 47 on a notch, 24 on an
/// iPad — a constant is wrong on all three.
enum SafeArea {
    static var top: CGFloat {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows where window.isKeyWindow {
                return window.safeAreaInsets.top
            }
        }
        return 47
    }
}

extension View {
    /// Places a bar over a fading field rather than on a hard band.
    func softTopBar<Bar: View>(height: CGFloat = 112,
                               @ViewBuilder _ bar: () -> Bar) -> some View {
        modifier(SoftTopBar(bar: bar(), height: height))
    }

    /// The same field, upside down, behind a pinned footer: the gradient and
    /// the blur fall off together instead, so the button sits on the page
    /// rather than on a plate laid over it.
    func softFooter(reach: CGFloat = 44) -> some View {
        background {
            LinearGradient(
                stops: [
                    .init(color: Tone.canvas.opacity(0), location: 0),
                    .init(color: Tone.canvas.opacity(0.24), location: 0.16),
                    .init(color: Tone.canvas.opacity(0.56), location: 0.31),
                    .init(color: Tone.canvas.opacity(0.86), location: 0.49),
                    .init(color: Tone.canvas.opacity(0.97), location: 0.68),
                    .init(color: Tone.canvas.opacity(0.99), location: 1)
                ],
                startPoint: .top, endPoint: .bottom)
                .background(.ultraThinMaterial)
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black.opacity(0.6), location: 0.27),
                            .init(color: .black, location: 0.53),
                            .init(color: .black, location: 1)
                        ],
                        startPoint: .top, endPoint: .bottom)
                }
                .padding(.top, -reach)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
        }
    }
}

extension View {
    /// Glass, unless something above already supplies it: a toolbar item on
    /// iOS 26 gets the material from the system.
    @ViewBuilder
    func glassIf(_ on: Bool) -> some View {
        if on { self.glass(Capsule()) } else { self }
    }
}

/// Animations that respect the Reduce Motion setting.
extension Animation {
    /// The app's standard motion, or none when the parent asked for none.
    static func soft(_ duration: Double = 0.28) -> Animation? {
        UIAccessibility.isReduceMotionEnabled ? nil : .smooth(duration: duration)
    }
}
