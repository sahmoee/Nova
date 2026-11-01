//
//  MacCompatibility.swift
//  Nova
//
//  macOS stand-ins for iOS-only SwiftUI modifiers used by shared screens. Each
//  shim either maps to the closest Mac behavior (toolbar placements) or does
//  nothing where the concept doesn't exist on a Mac (keyboards, status bar,
//  auto-capitalization, inline navigation titles).
//

#if os(macOS)
import SwiftUI

enum NovaTitleDisplayMode { case automatic, inline, large }

struct NovaTextInputAutocapitalization {
    static let never = Self(), words = Self(), sentences = Self(), characters = Self()
}

enum NovaKeyboardType {
    case `default`, asciiCapable, numbersAndPunctuation, URL, numberPad, phonePad,
         namePhonePad, emailAddress, decimalPad, twitter, webSearch, asciiCapableNumberPad
}

extension View {
    func navigationBarTitleDisplayMode(_ mode: NovaTitleDisplayMode) -> some View { self }
    func textInputAutocapitalization(_ style: NovaTextInputAutocapitalization?) -> some View { self }
    func keyboardType(_ type: NovaKeyboardType) -> some View { self }
    func statusBarHidden(_ hidden: Bool = true) -> some View { self }
}

extension ToolbarItemPlacement {
    static var topBarLeading: ToolbarItemPlacement { .navigation }
    static var topBarTrailing: ToolbarItemPlacement { .primaryAction }
}

extension ToolbarPlacement {
    static var navigationBar: ToolbarPlacement { .windowToolbar }
}

/// Lists on the Mac reorder and delete through their own controls and context
/// menus, so the iOS Edit button has nothing to toggle.
struct EditButton: View {
    var body: some View { EmptyView() }
}
#endif
