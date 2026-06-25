import AppKit
import Sparkle

@MainActor
final class UpdaterController: NSObject {
    static let shared = UpdaterController()

    private var controller: SPUStandardUpdaterController?

    private override init() {
        super.init()
    }

    func start() {
        guard controller == nil else { return }
        let controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        controller.startUpdater()
        self.controller = controller
    }

    @objc func checkForUpdates(_ sender: Any?) {
        controller?.checkForUpdates(sender)
    }
}
