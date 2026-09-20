// QAUnlockGate.swift
// ─────────────────────────────────────────────────────────────────────────────
// Shared QACore — passcode gate that guards QAHubView.
//
// Uses system colors throughout — no app-specific color tokens.
// The QAAccessGate handles passcode logic and 10-minute rolling window.
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI

// MARK: - QAUnlockGate

/// Present this as a fullScreenCover. On successful unlock it transitions
/// directly to QAHubView without dismissing (avoids a flash).
struct QAUnlockGate: View {

    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var shake = false
    @State private var unlocked = false
    @State private var showHub = false

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()

            if unlocked {
                QAHubView(dismiss: { dismiss() })
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing),
                        removal: .opacity
                    ))
            } else {
                lockScreen
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: unlocked)
        .onAppear {
            if QAAccessGate.shared.isUnlocked { unlocked = true }
        }
    }

    // MARK: Lock screen

    private var lockScreen: some View {
        VStack(spacing: 0) {
            Spacer()

            // Header
            VStack(spacing: 10) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(.secondary)
                Text("QA Access")
                    .font(.system(size: 22, weight: .semibold))
                Text(QA.config.appName + " · " + QA.config.version + " (\(QA.config.buildNumber))")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Spacer().frame(height: 48)

            // Code dots
            HStack(spacing: 16) {
                ForEach(0..<4, id: \.self) { i in
                    Circle()
                        .fill(i < code.count ? Color.accentColor : Color(uiColor: .tertiaryLabel))
                        .frame(width: 14, height: 14)
                }
            }
            .offset(x: shake ? -8 : 0)
            .animation(shake ? .default.repeatCount(3, autoreverses: true).speed(4) : .default, value: shake)

            Spacer().frame(height: 8)

            Text("Enter your four-digit access code")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            Spacer().frame(height: 40)

            // Keypad
            keypad

            Spacer()

            // Cancel
            Button("Cancel") { dismiss() }
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .padding(.bottom, 32)
        }
        .padding(.horizontal, 32)
    }

    // MARK: Keypad

    private var keypad: some View {
        VStack(spacing: 16) {
            ForEach([[1, 2, 3], [4, 5, 6], [7, 8, 9], [0]], id: \.self) { row in
                HStack(spacing: 24) {
                    if row == [0] { Color.clear.frame(width: 72, height: 72) }
                    ForEach(row, id: \.self) { digit in
                        keypadButton(digit)
                    }
                    if row == [0] {
                        // Backspace
                        Button {
                            if !code.isEmpty { code.removeLast() }
                        } label: {
                            Image(systemName: "delete.left")
                                .font(.system(size: 20))
                                .frame(width: 72, height: 72)
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }
        }
    }

    private func keypadButton(_ digit: Int) -> some View {
        Button {
            guard code.count < 4 else { return }
            code.append(String(digit))
            if code.count == 4 { attempt() }
        } label: {
            Text("\(digit)")
                .font(.system(size: 28, weight: .light))
                .frame(width: 72, height: 72)
                .background(Color(uiColor: .secondarySystemBackground), in: Circle())
        }
        .foregroundStyle(.primary)
    }

    // MARK: Attempt

    private func attempt() {
        if QAAccessGate.shared.unlock(with: code) {
            unlocked = true
        } else {
            code = ""
            shake = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { shake = false }
        }
    }
}
