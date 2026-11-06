//
//  PlatformSupport.swift
//  Nova
//
//  Small type aliases and modifiers that let shared SwiftUI screens compile for
//  iOS, tvOS and the native macOS app without per-call platform checks.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
typealias PlatformTextContentType = UITextContentType
#elseif canImport(AppKit)
import AppKit
typealias PlatformTextContentType = NSTextContentType
#endif

extension View {
    /// Turns off automatic capitalization where the platform has it (not macOS).
    @ViewBuilder
    func novaNoAutocapitalization() -> some View {
        #if os(macOS)
        self
        #else
        textInputAutocapitalization(.never)
        #endif
    }
}

extension View {
    @ViewBuilder
    func novaInlineNavigationTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}

extension View {
    /// Full-screen cover on iPhone, iPad and Apple TV. macOS has no full-screen
    /// cover, so the content opens in a large resizable sheet instead.
    func novaFullScreenCover<Item: Identifiable, Content: View>(
        item: Binding<Item?>, onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        #if os(macOS)
        sheet(item: item, onDismiss: onDismiss) { value in
            content(value).frame(minWidth: 960, idealWidth: 1280, minHeight: 600, idealHeight: 800)
        }
        #else
        fullScreenCover(item: item, onDismiss: onDismiss, content: content)
        #endif
    }

    func novaFullScreenCover<Content: View>(
        isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        #if os(macOS)
        sheet(isPresented: isPresented, onDismiss: onDismiss) {
            content().frame(minWidth: 960, idealWidth: 1280, minHeight: 600, idealHeight: 800)
        }
        #else
        fullScreenCover(isPresented: isPresented, onDismiss: onDismiss, content: content)
        #endif
    }
}
