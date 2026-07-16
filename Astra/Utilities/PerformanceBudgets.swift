//
//  PerformanceBudgets.swift
//  Astra
//
//  Measurable performance targets, in one place, so diagnostics and future
//  instrumentation compare against a single source of truth. See
//  docs/PERFORMANCE_BUDGETS.md for rationale and how each is measured. Values are
//  release-build targets on representative hardware; they are not enforced at
//  compile time (timing must be validated on-device with Instruments).
//

import Foundation

enum PerformanceBudgets {
    /// Cold launch to Home's first frame.
    static let coldLaunchMs: Double = 1200
    /// Home shelves interactive after launch.
    static let homeInteractiveMs: Double = 800
    /// First search results (predictive suggestions target 300ms).
    static let searchFirstResultsMs: Double = 900
    static let searchSuggestionsMs: Double = 300
    /// Poster decode, off the main thread (cached target 8ms).
    static let posterDecodeMs: Double = 40
    static let posterDecodeCachedMs: Double = 8
    /// Stream resolution from add-on to a playable link.
    static let streamResolutionMs: Double = 6000
    /// Player startup: tap to first playing frame (cached/direct target 1500ms).
    static let playerStartupMs: Double = 3000
    static let playerStartupCachedMs: Double = 1500
    /// Steady-state memory while browsing (excludes active decode buffers).
    static let steadyMemoryMB: Double = 350
    /// Acceptable dropped-frame ratio while scrolling.
    static let maxDroppedFrameRatio: Double = 0.01

    /// Whether a measured duration (ms) is within its budget, for diagnostics.
    static func within(_ measuredMs: Double, budget: Double) -> Bool {
        measuredMs <= budget
    }
}
