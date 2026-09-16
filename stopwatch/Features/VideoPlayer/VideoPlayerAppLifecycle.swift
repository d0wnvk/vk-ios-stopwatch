import UIKit

enum VideoPlayerAppLifecycle {
    static func configuration(for sceneSession: UISceneSession) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: nil,
            sessionRole: sceneSession.role
        )

        if sceneSession.role == .windowExternalDisplayNonInteractive {
            configuration.delegateClass = ExternalDisplaySceneDelegate.self
        }

        return configuration
    }
}

final class ExternalDisplaySceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let viewController = ExternalDisplayViewController()
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = viewController
        window.makeKeyAndVisible()
        self.window = window

        ExternalDisplayManager.shared.connect(view: viewController.view)
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        ExternalDisplayManager.shared.disconnect()
        window = nil
    }
}

private final class ExternalDisplayViewController: UIViewController {
    override func loadView() {
        let outputView = UIView()
        outputView.backgroundColor = .black
        view = outputView
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        ExternalDisplayManager.shared.outputViewDidLayout()
    }

    override var prefersHomeIndicatorAutoHidden: Bool {
        true
    }
}
