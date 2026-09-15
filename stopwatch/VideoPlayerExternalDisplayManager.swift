import UIKit

final class ExternalDisplayManager {
    static let shared = ExternalDisplayManager()

    private weak var controller: VLCPlayerController?
    private weak var phoneView: UIView?
    private weak var externalView: UIView?

    private init() {}

    func register(controller: VLCPlayerController, phoneView: UIView) {
        self.controller = controller
        self.phoneView = phoneView
        updateOutput()
    }

    func connect(view: UIView) {
        externalView = view
        updateOutput()
    }

    func disconnect() {
        externalView = nil
        updateOutput()
    }

    func unregister(controller: VLCPlayerController) {
        guard self.controller === controller else { return }
        self.controller = nil
        phoneView = nil
    }

    func outputViewDidLayout() {
        controller?.outputViewDidLayout()
    }

    private func updateOutput() {
        let outputView = externalView ?? phoneView
        controller?.setOutputView(outputView, isExternal: externalView != nil)
    }
}
