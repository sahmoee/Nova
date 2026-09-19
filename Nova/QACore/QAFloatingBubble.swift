// QAFloatingBubble.swift
// ─────────────────────────────────────────────────────────────────────────────
// Shared QACore — floating QA bubble (draggable, always-on-top UIWindow).
//
// Provides QAFloatingButtonWindow and QAFloatingMenuPresenter.
// No app-specific dependencies — the parent app calls attach() / present()
// with no session argument. The bubble taps open QAUnlockGate, which guards
// QAHubView.
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI
import UIKit

// MARK: - QAFloatingButtonWindow

/// A UIWindow that floats at .alert + 0.5 level and hosts a draggable bubble.
final class QAFloatingButtonWindow: UIWindow {

    private var dragOffset: CGPoint = .zero

    override init(windowScene: UIWindowScene) {
        super.init(windowScene: windowScene)
        windowLevel = .alert + 0.5
        backgroundColor = .clear
        isUserInteractionEnabled = true
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Attach the floating bubble to a scene.
    static func attach(to scene: UIWindowScene) {
        let win = QAFloatingButtonWindow(windowScene: scene)
        win.frame = scene.coordinateSpace.bounds
        let vc = UIHostingController(rootView: QAFloatingBubbleView())
        vc.view.backgroundColor = .clear
        win.rootViewController = vc
        win.makeKeyAndVisible()
        win.isHidden = false
        // Retain via association
        objc_setAssociatedObject(scene, &Self.windowKey, win, .OBJC_ASSOCIATION_RETAIN)
    }

    private static var windowKey: UInt8 = 0

    // MARK: Pass-through

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === rootViewController?.view ? nil : hit
    }
}

// MARK: - Floating bubble SwiftUI view

private struct QAFloatingBubbleView: View {

    @State private var position: CGSize = CGSize(width: 40, height: -120)
    @State private var showMenu = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if showMenu {
                    QAFloatingMenuPresenter(dismiss: { showMenu = false })
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }

                bubble(geo: geo)
            }
            .animation(.spring(response: 0.3), value: showMenu)
        }
    }

    private func bubble(geo: GeometryProxy) -> some View {
        ZStack {
            Circle()
                .fill(bubbleFill)
                .frame(width: 52, height: 52)
                .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 3)

            Image(systemName: QATriage.shared.verdictSymbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(QATriage.shared.verdictTint)
        }
        .offset(safeOffset(for: position, in: geo.size))
        .gesture(
            DragGesture()
                .onChanged { v in
                    position = v.translation
                }
                .onEnded { v in
                    position = v.predictedEndTranslation
                }
        )
        .onTapGesture { showMenu.toggle() }
    }

    private var bubbleFill: some ShapeStyle {
        AnyShapeStyle(
            .regularMaterial
        )
    }

    private func safeOffset(for size: CGSize, in bounds: CGSize) -> CGSize {
        let r: CGFloat = 30
        let x = max(r, min(bounds.width - r, bounds.width / 2 + size.width))
        let y = max(r + 60, min(bounds.height - r - 40, bounds.height / 2 + size.height))
        return CGSize(width: x - bounds.width / 2, height: y - bounds.height / 2)
    }
}

// MARK: - QAFloatingMenuPresenter

/// A transparent overlay hosting the quick-action menu above the bubble.
struct QAFloatingMenuPresenter: View {

    let dismiss: () -> Void

    @State private var showGate = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack(alignment: .trailing, spacing: 12) {
                // Triage summary chip
                triageChip

                // Open hub button
                Button {
                    dismiss()
                    showGate = true
                } label: {
                    Label("Open QA Hub", systemImage: "checklist")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                }

                // Quick ticket button
                Button {
                    dismiss()
                    QAFloatingMenuPresenter.openQuickTicket()
                } label: {
                    Label("File Ticket", systemImage: "plus.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                }
            }
            .padding(24)
        }
        .fullScreenCover(isPresented: $showGate) {
            QAUnlockGate()
        }
    }

    private var triageChip: some View {
        HStack(spacing: 6) {
            Image(systemName: QATriage.shared.verdictSymbol)
                .foregroundStyle(QATriage.shared.verdictTint)
            Text(QATriage.shared.verdict)
                .font(.system(size: 13, weight: .semibold))
            let b = QATriage.shared.blockers.count
            let w = QATriage.shared.warnings.count
            if b + w > 0 {
                Text("· \(b)B \(w)W")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
    }

    /// Opens the quick-file-ticket sheet via NotificationCenter so there's
    /// no coupling to a specific scene or app session.
    static func openQuickTicket() {
        NotificationCenter.default.post(name: .qaOpenQuickTicket, object: nil)
    }
}

// MARK: - Notification name

extension Notification.Name {
    static let qaOpenQuickTicket = Notification.Name("qa.openQuickTicket")
}
