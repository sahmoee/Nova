//
//  PlatformCapabilities.swift
//  Astra
//
//  Compile-time capability boundary for iPhone, iPad, and Apple TV. Views consult
//  this type before exposing platform-only affordances so UIKit-only actions, tvOS
//  focus behavior, widgets, Top Shelf, QR scanning, and external players never leak
//  into a target that cannot support them.
//

import SwiftUI

#if os(iOS)
import UIKit
#endif

enum AstraPlatform: String, Codable, CaseIterable {
    case iPhone
    case iPad
    case appleTV

    var displayName: String {
        switch self {
        case .iPhone:  return "iPhone"
        case .iPad:    return "iPad"
        case .appleTV: return "Apple TV"
        }
    }
}

enum PlatformFeature: Hashable {
    case haptics
    case widgets
    case spotlight
    case qrScanner
    case shareSheet
    case externalPlayers
    case dragAndDrop
    case pullToRefresh
    case topShelf
    case focusEngine
    case remoteMenuCommand
    case pictureInPicture
    case multiColumnNavigation
}

enum PlatformNavigationStyle {
    case bottomTabs
    case sidebar
    case televisionTabs
}

enum PlatformCapabilities {
    static var platform: AstraPlatform {
        #if os(tvOS)
        return .appleTV
        #else
        return UIDevice.current.userInterfaceIdiom == .pad ? .iPad : .iPhone
        #endif
    }

    static var navigationStyle: PlatformNavigationStyle {
        switch platform {
        case .iPhone:  return .bottomTabs
        case .iPad:    return .sidebar
        case .appleTV: return .televisionTabs
        }
    }

    static func supports(_ feature: PlatformFeature) -> Bool {
        switch feature {
        case .haptics, .widgets, .spotlight, .qrScanner, .shareSheet,
             .externalPlayers, .dragAndDrop, .pullToRefresh,
             .pictureInPicture:
            #if os(iOS)
            return true
            #else
            return false
            #endif

        case .topShelf, .focusEngine, .remoteMenuCommand:
            #if os(tvOS)
            return true
            #else
            return false
            #endif

        case .multiColumnNavigation:
            #if os(iOS)
            return UIDevice.current.userInterfaceIdiom == .pad
            #else
            return false
            #endif
        }
    }

    static var contentInsets: EdgeInsets {
        switch platform {
        case .iPhone:
            return EdgeInsets(top: 12, leading: 20, bottom: 24, trailing: 20)
        case .iPad:
            return EdgeInsets(top: 18, leading: 34, bottom: 34, trailing: 34)
        case .appleTV:
            return EdgeInsets(top: 38, leading: 70, bottom: 52, trailing: 70)
        }
    }

    static var homeHeroHeight: CGFloat {
        switch platform {
        case .iPhone:  return 470
        case .iPad:    return 560
        case .appleTV: return 640
        }
    }

    static var railPosterScale: CGFloat {
        switch platform {
        case .iPhone:  return 0.66
        case .iPad:    return 0.78
        case .appleTV: return 1.0
        }
    }
}

/// Makes it easy to completely omit a view on unsupported targets instead of
/// showing a control that can never work there.
struct PlatformOnly<Content: View>: View {
    let feature: PlatformFeature
    private let content: () -> Content

    init(_ feature: PlatformFeature, @ViewBuilder content: @escaping () -> Content) {
        self.feature = feature
        self.content = content
    }

    @ViewBuilder
    var body: some View {
        if PlatformCapabilities.supports(feature) {
            content()
        }
    }
}
