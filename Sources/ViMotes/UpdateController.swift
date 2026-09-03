import Sparkle

@MainActor
final class UpdateController {
  static func configured(bundle: Bundle = .main) -> UpdateController? {
    guard
      let publicKey = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
      !publicKey.isEmpty,
      publicKey != "SPARKLE_PUBLIC_KEY_REQUIRED"
    else {
      return nil
    }
    return UpdateController()
  }

  private let controller = SPUStandardUpdaterController(
    startingUpdater: false,
    updaterDelegate: nil,
    userDriverDelegate: nil
  )
  private(set) var isStarted = false

  var automaticallyChecksForUpdates: Bool {
    get { controller.updater.automaticallyChecksForUpdates }
    set { controller.updater.automaticallyChecksForUpdates = newValue }
  }

  var canCheckForUpdates: Bool {
    isStarted && controller.updater.canCheckForUpdates
  }

  func start() {
    guard !isStarted else { return }
    controller.startUpdater()
    isStarted = true
  }

  func checkForUpdates(_ sender: Any?) {
    controller.checkForUpdates(sender)
  }
}
