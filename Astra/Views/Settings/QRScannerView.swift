//
//  QRScannerView.swift
//  Astra
//
//  A lightweight camera QR scanner (iOS only) used to read a URL that points to a
//  snapshot the user wants to import. The QR holds a link, not the snapshot itself,
//  since a full backup is far larger than a QR can encode.
//

import SwiftUI

#if os(iOS)
import AVFoundation
import AudioToolbox

struct QRScannerView: View {
    /// Called with the decoded string (expected to be a URL) when a code is found.
    let onFound: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            QRScannerRepresentable { code in
                onFound(code)
                dismiss()
            }
            .ignoresSafeArea()

            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.appFont(20, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(Theme.Spacing.md)
                            .background(.black.opacity(0.5), in: Circle())
                    }
                    .padding(Theme.Spacing.lg)
                }
                Spacer()
                Text("Point the camera at a Astra snapshot QR code")
                    .font(.appFont(18, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(Theme.Spacing.md)
                    .background(.black.opacity(0.5), in: Capsule())
                    .padding(.bottom, Theme.Spacing.xl)
            }
            // A simple reticle.
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.85), lineWidth: 3)
                .frame(width: 240, height: 240)
        }
        .background(Color.black)
    }
}

/// UIKit bridge that runs an AVCaptureSession and reports decoded QR strings.
private struct QRScannerRepresentable: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> QRScannerController {
        let c = QRScannerController()
        c.onCode = onCode
        return c
    }
    func updateUIViewController(_ controller: QRScannerController, context: Context) {}
}

final class QRScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?
    private let session = AVCaptureSession()
    private var preview: AVCaptureVideoPreviewLayer?
    private var didReport = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configure()
    }

    private func configure() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.layer.bounds
        view.layer.addSublayer(layer)
        preview = layer

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview?.frame = view.layer.bounds
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if session.isRunning { session.stopRunning() }
    }

    // The delegate requirement is nonisolated, but this controller is @MainActor.
    // The output is delivered on `.main` (see `setMetadataObjectsDelegate` above),
    // so it's safe to assume main-actor isolation to touch the controller's state.
    nonisolated func metadataOutput(_ output: AVCaptureMetadataOutput,
                                    didOutput objects: [AVMetadataObject],
                                    from connection: AVCaptureConnection) {
        // Pull the Sendable `String` out of the non-Sendable metadata objects here in
        // the nonisolated context, so nothing non-Sendable is captured by the hop.
        guard let value = (objects.first as? AVMetadataMachineReadableCodeObject)?.stringValue
        else { return }
        MainActor.assumeIsolated {
            guard !didReport else { return }
            didReport = true
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
            if session.isRunning { session.stopRunning() }
            onCode?(value)
        }
    }
}
#endif
