import AVFoundation
import SwiftUI
import UIKit

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    let onTapToFocus: (CGPoint) -> Void
    let onOrientationChange: (UIInterfaceOrientation) -> Void

    func makeUIView(context: Context) -> RecorderPreviewUIView {
        let view = RecorderPreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.onOrientationChange = context.coordinator.handleOrientationChange(_:)
        let recognizer = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(recognizer)
        return view
    }

    func updateUIView(_ uiView: RecorderPreviewUIView, context: Context) {
        uiView.previewLayer.session = session
        uiView.onOrientationChange = context.coordinator.handleOrientationChange(_:)
        uiView.updatePreviewOrientation()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onTapToFocus: onTapToFocus, onOrientationChange: onOrientationChange)
    }
}

extension CameraPreviewView {
    final class Coordinator: NSObject {
        private let onTapToFocus: (CGPoint) -> Void
        private let onOrientationChange: (UIInterfaceOrientation) -> Void

        init(
            onTapToFocus: @escaping (CGPoint) -> Void,
            onOrientationChange: @escaping (UIInterfaceOrientation) -> Void
        ) {
            self.onTapToFocus = onTapToFocus
            self.onOrientationChange = onOrientationChange
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let view = recognizer.view as? RecorderPreviewUIView else { return }
            let layerPoint = recognizer.location(in: view)
            let devicePoint = view.previewLayer.captureDevicePointConverted(fromLayerPoint: layerPoint)
            view.showFocusIndicator(at: layerPoint)
            onTapToFocus(devicePoint)
        }

        func handleOrientationChange(_ interfaceOrientation: UIInterfaceOrientation) {
            onOrientationChange(interfaceOrientation)
        }
    }
}

final class RecorderPreviewUIView: UIView {
    var onOrientationChange: ((UIInterfaceOrientation) -> Void)?
    private let focusIndicatorView = FocusIndicatorUIView()
    private var pendingFocusIndicatorHide: DispatchWorkItem?

    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        guard let layer = layer as? AVCaptureVideoPreviewLayer else {
            fatalError("Expected AVCaptureVideoPreviewLayer")
        }
        return layer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        focusIndicatorView.alpha = 0
        addSubview(focusIndicatorView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updatePreviewOrientation()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updatePreviewOrientation()
    }

    func updatePreviewOrientation() {
        guard let interfaceOrientation = window?.windowScene?.interfaceOrientation,
              let videoOrientation = AVCaptureVideoOrientation(interfaceOrientation),
              let connection = previewLayer.connection,
              connection.isVideoOrientationSupported
        else {
            return
        }

        connection.videoOrientation = videoOrientation
        onOrientationChange?(interfaceOrientation)
    }

    func showFocusIndicator(at point: CGPoint) {
        pendingFocusIndicatorHide?.cancel()
        pendingFocusIndicatorHide = nil
        focusIndicatorView.layer.removeAllAnimations()
        focusIndicatorView.bounds = CGRect(x: 0, y: 0, width: 72, height: 72)
        focusIndicatorView.center = point
        focusIndicatorView.setNeedsLayout()
        focusIndicatorView.layoutIfNeeded()
        bringSubviewToFront(focusIndicatorView)

        UIView.performWithoutAnimation {
            focusIndicatorView.alpha = 1
        }

        let hideWorkItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            UIView.animate(
                withDuration: 0.2,
                delay: 0,
                options: [.beginFromCurrentState, .allowUserInteraction],
                animations: {
                    self.focusIndicatorView.alpha = 0
                }
            )
        }
        pendingFocusIndicatorHide = hideWorkItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + 0.8,
            execute: hideWorkItem
        )
    }
}

private final class FocusIndicatorUIView: UIView {
    private let horizontalLine = CALayer()
    private let verticalLine = CALayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        layer.borderColor = UIColor.systemYellow.cgColor
        layer.borderWidth = 2
        layer.cornerRadius = 8
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.35
        layer.shadowRadius = 6

        horizontalLine.backgroundColor = UIColor.systemYellow.cgColor
        verticalLine.backgroundColor = UIColor.systemYellow.cgColor
        layer.addSublayer(horizontalLine)
        layer.addSublayer(verticalLine)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        horizontalLine.frame = CGRect(
            x: (bounds.width - 20) / 2,
            y: (bounds.height - 2) / 2,
            width: 20,
            height: 2
        )
        verticalLine.frame = CGRect(
            x: (bounds.width - 2) / 2,
            y: (bounds.height - 20) / 2,
            width: 2,
            height: 20
        )
    }
}
