//
//  LegalAccessGate.swift
//  Nova
//
//  Single source of truth for the legal-access confirmation copy and state.
//  Magnet and direct-link flows route their confirmation through this gate.
//

import Foundation

enum LegalAccessGate {
    /// The exact confirmation string shown to users before submitting
    /// magnet links or unverified direct links.
    static let confirmationText =
        "I confirm I own, control, or am authorized to access this content."

    /// Short explanation shown alongside the checkbox.
    static let explanation =
        "Nova is a personal media player. It does not search for, index, or " +
        "provide any content. You are responsible for ensuring you have the " +
        "legal right to access anything you add."

    /// Returns whether an action may proceed given the user's confirmation
    /// and the app-level "require confirmation" setting.
    static func mayProceed(userConfirmed: Bool, requireConfirmation: Bool) -> Bool {
        guard requireConfirmation else { return true }
        return userConfirmed
    }
}
