//
//  FocusableButton.swift
//  Nova
//
//  A platform-adaptive Apple TV-style control with a bright, lifted focus state.
//

import SwiftUI

struct FocusableButton: View {
    let title: String
    var systemImage: String? = nil
    var prominent: Bool = false
    var accessibilityHint: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
                    .fontWeight(.semibold)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
            }
            // Prominent buttons stretch to fill; secondary buttons get a comfortable
            // minimum width so a short label ("Edit", "Add") still reads as a proper
            // button. The shared style owns minimum height after padding.
            .frame(minWidth: prominent ? nil : Theme.minButtonWidth,
                   maxWidth: prominent ? .infinity : nil)
        }
        .buttonStyle(FocusableButtonStyle(prominent: prominent))
        .accessibilityHint(accessibilityHint ?? "")
    }
}

/// The button style behind FocusableButton. Implemented as a ButtonStyle (reading
/// isFocused from the environment) so that on tvOS it fully replaces the system focus
/// appearance — no white card behind the button.
struct FocusableButtonStyle: ButtonStyle {
    var prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        #if os(tvOS)
        TVReferenceButtonStyle(prominent: prominent, horizontalPadding: 22, verticalPadding: 10).makeBody(configuration: configuration)
        #else
        NovaHandheldControl(configuration: configuration, role: prominent ? .prominent : .button)
        #endif
    }

}
