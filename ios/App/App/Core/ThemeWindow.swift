// The preference is intercepted at each PRESENTATION. A sheet does not
// inherit it, so the child picker and the paywall would keep the system
// appearance while the rest of the app changed.

import SwiftUI
import UIKit

extension AppTheme {
    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: return .unspecified
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

/// Applies the theme to the window that actually holds this view, and keeps
/// applying it when the choice changes.
struct ThemeApplier: ViewModifier {
    let theme: AppTheme

    func body(content: Content) -> some View {
        content
            .background(WindowReader { window in
                apply(to: window)
            })
            .onChange(of: theme) { _, _ in
                applyToAllWindows()
            }
            .onAppear { applyToAllWindows() }
    }

    private func apply(to window: UIWindow?) {
        guard let window else { return }
        /* Animated so the switch reads as a change of light rather than a
         * flash. 0.25s matches the system's own appearance transition. */
        UIView.transition(with: window, duration: 0.25,
                          options: .transitionCrossDissolve) {
            window.overrideUserInterfaceStyle = theme.interfaceStyle
        }
    }

    private func applyToAllWindows() {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                apply(to: window)
            }
        }
    }
}

extension View {
    func appTheme(_ theme: AppTheme) -> some View {
        modifier(ThemeApplier(theme: theme))
    }
}

/// Finds the UIWindow behind a SwiftUI view. A zero-size representable is the
/// standard way to reach it without a scene delegate.
private struct WindowReader: UIViewRepresentable {
    let onResolve: (UIWindow?) -> Void

    func makeUIView(context: Context) -> UIView {
        let v = UIView(frame: .zero)
        v.isUserInteractionEnabled = false
        DispatchQueue.main.async { onResolve(v.window) }
        return v
    }

    func updateUIView(_ v: UIView, context: Context) {
        DispatchQueue.main.async { onResolve(v.window) }
    }
}
