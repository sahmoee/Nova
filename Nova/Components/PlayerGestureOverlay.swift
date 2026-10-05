//
//  PlayerGestureOverlay.swift
//  Nova
//
//  A UIKit gesture surface for the video area (iOS/iPadOS).
//
//  Why UIKit: SwiftUI makes tap + horizontal drag-to-seek awkward on the same
//  surface — `TapGesture` and `DragGesture` fight over the same touches, and
//  `DragGesture` gives no direction locking or threshold, so a vertical intent
//  easily triggers a horizontal scrub and vice-versa. A plain `UIView` with an
//  explicit `UITapGestureRecognizer` + `UIPanGestureRecognizer` lets us lock the
//  pan to horizontal movement, ignore vertical drags, and report a clean scrub
//  fraction. It sits beneath the transport controls so button taps still win.
//

#if os(iOS)
import SwiftUI
import UIKit

struct PlayerGestureOverlay: UIViewRepresentable {
    /// A single tap on empty video area (toggle controls).
    var onTap: () -> Void
    /// Horizontal scrub. `state` is .began/.changed/.ended(/.cancelled); `fraction`
    /// is signed horizontal translation as a fraction of the surface width.
    var onScrub: (UIGestureRecognizer.State, CGFloat) -> Void
    /// Double tap, reporting the horizontal position as a 0...1 fraction of the width
    /// (left side skips back, right side forward). nil keeps single taps immediate.
    var onDoubleTap: ((CGFloat) -> Void)? = nil
    /// A clear downward swipe (minimize the player).
    var onSwipeDown: (() -> Void)? = nil

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = false

        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleTap))
        let pan = UIPanGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handlePan))
        pan.delegate = context.coordinator
        // A tap should not be swallowed by the pan.
        tap.require(toFail: pan)
        if onDoubleTap != nil {
            let doubleTap = UITapGestureRecognizer(target: context.coordinator,
                                                   action: #selector(Coordinator.handleDoubleTap))
            doubleTap.numberOfTapsRequired = 2
            tap.require(toFail: doubleTap)
            view.addGestureRecognizer(doubleTap)
        }
        view.addGestureRecognizer(tap)
        view.addGestureRecognizer(pan)

        context.coordinator.view = view
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: PlayerGestureOverlay
        weak var view: UIView?
        /// Set once a pan is confirmed horizontal, so vertical drags never scrub.
        private var scrubbing = false
        /// Set once a pan is confirmed vertical, for swipe-down-to-minimize.
        private var verticalDrag = false
        private let activateThreshold: CGFloat = 12

        init(_ parent: PlayerGestureOverlay) { self.parent = parent }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            parent.onTap()
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let view, view.bounds.width > 0 else { return }
            parent.onDoubleTap?(gesture.location(in: view).x / view.bounds.width)
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let view, view.bounds.width > 0 else { return }
            let translation = gesture.translation(in: view)
            let fraction = translation.x / view.bounds.width

            switch gesture.state {
            case .began:
                scrubbing = false
                verticalDrag = false
            case .changed:
                if !scrubbing {
                    // Lock direction only once movement is clearly horizontal.
                    if abs(translation.x) > activateThreshold,
                       abs(translation.x) > abs(translation.y) * 1.2 {
                        scrubbing = true
                        parent.onScrub(.began, fraction)
                    } else if abs(translation.y) > activateThreshold {
                        // Committed vertical: leave scrubbing off for this gesture.
                        verticalDrag = true
                        return
                    }
                } else {
                    parent.onScrub(.changed, fraction)
                }
            case .ended, .cancelled, .failed:
                if scrubbing { parent.onScrub(gesture.state, fraction) }
                // A deliberate downward swipe (distance or flick) minimizes.
                if !scrubbing, verticalDrag, gesture.state == .ended,
                   translation.y > 0, abs(translation.y) > abs(translation.x) * 1.5,
                   translation.y > 120 || gesture.velocity(in: view).y > 900 {
                    parent.onSwipeDown?()
                }
                scrubbing = false
                verticalDrag = false
            default:
                break
            }
        }

        // Let the pan coexist with SwiftUI gestures on sibling views if any.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
#endif
