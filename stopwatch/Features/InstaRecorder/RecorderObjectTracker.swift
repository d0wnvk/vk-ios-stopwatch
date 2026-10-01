import AVFoundation
import QuartzCore
import Vision

final class RecorderObjectTracker: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let queue = DispatchQueue(label: "vk.stopwatch.insta-object-tracker")
    private var sequenceHandler = VNSequenceRequestHandler()
    private var request: VNTrackObjectRequest?
    private var lastFrameTime: CFTimeInterval = 0

    var queueForCaptureOutput: DispatchQueue { queue }
    var onUpdate: (@Sendable (CGRect?, VNConfidence, CVPixelBuffer?) -> Void)?

    func select(visionRect: CGRect) {
        queue.async { [weak self] in
            guard let self else { return }
            sequenceHandler = VNSequenceRequestHandler()
            request = VNTrackObjectRequest(
                detectedObjectObservation: VNDetectedObjectObservation(
                    boundingBox: visionRect
                )
            )
            request?.trackingLevel = .accurate
            lastFrameTime = 0
        }
    }

    func reset() {
        queue.async { [weak self] in
            self?.request = nil
            self?.sequenceHandler = VNSequenceRequestHandler()
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let request,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let frameTime = CACurrentMediaTime()
        // DockKit requires custom observations at a fixed 10–30 Hz. Fifteen
        // updates per second leaves enough time for Vision on older phones.
        guard frameTime - lastFrameTime >= (1.0 / 15.0) else { return }
        lastFrameTime = frameTime

        do {
            try sequenceHandler.perform([request], on: pixelBuffer)
            guard let result = request.results?.first as? VNDetectedObjectObservation else {
                onUpdate?(nil, 0, pixelBuffer)
                return
            }
            guard result.confidence >= 0.25 else {
                onUpdate?(nil, result.confidence, pixelBuffer)
                return
            }

            request.inputObservation = result
            onUpdate?(result.boundingBox, result.confidence, pixelBuffer)
        } catch {
            onUpdate?(nil, 0, pixelBuffer)
        }
    }
}
