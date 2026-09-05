import Sparkle

@MainActor
final class UpdateController: NSObject, @MainActor SPUStandardUserDriverDelegate {
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

  private lazy var controller = SPUStandardUpdaterController(
    startingUpdater: false,
    updaterDelegate: nil,
    userDriverDelegate: self
  )
  private(set) var isStarted = false
  private(set) var hasPendingUpdate = false {
    didSet {
      if oldValue != hasPendingUpdate { onUpdateAvailabilityChange?() }
    }
  }
  var onUpdateAvailabilityChange: (() -> Void)?
  var supportsGentleScheduledUpdateReminders: Bool { true }

  func standardUserDriverWillHandleShowingUpdate(
    _ handleShowingUpdate: Bool,
    forUpdate update: SUAppcastItem,
    state: SPUUserUpdateState
  ) {
    hasPendingUpdate = !state.userInitiated
  }

  func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
    hasPendingUpdate = false
  }

  func standardUserDriverWillFinishUpdateSession() {
    hasPendingUpdate = false
  }

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
