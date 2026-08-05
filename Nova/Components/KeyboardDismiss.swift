//
//  KeyboardDismiss.swift
//  Nova
//
//  Small helpers to dismiss the on-screen keyboard on iPhone/iPad. Tapping anywhere
//  outside a text field, or scrolling, hides the keyboard — matching the behavior
//  people expect from native apps. No-ops on tvOS, which has no software keyboard
//  of this kind.
//

import SwiftUI

#if canImport(UIKit)
import UIKit

extension View {
    /// Dismisses the keyboard when the user taps outside a text field and as they
    /// scroll. Apply to a screen that contains text entry.
    func dismissKeyboardOnTap() -> some View {
        modifier(KeyboardDismissModifier())
    }
}

/// Resigns first responder app-wide, which closes the keyboard. `UIApplication` is
/// main-actor-isolated; this is only invoked from SwiftUI gesture callbacks on main.
func hideKeyboard() {
    MainActor.assumeIsolated {
        // Discard the Bool result so the closure (and assumeIsolated) returns Void.
        _ = UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                            to: nil, from: nil, for: nil)
    }
}

private struct KeyboardDismissModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            // Interactive scroll-to-dismiss, plus a background tap that doesn't steal
            // taps from buttons/fields (simultaneous gesture).
            .scrollDismissesKeyboard(.interactively)
            .simultaneousGesture(
                TapGesture().onEnded { hideKeyboard() }
            )
    }
}
#else
extension View {
    /// No-op on tvOS.
    func dismissKeyboardOnTap() -> some View { self }
}

func hideKeyboard() {}
#endif
