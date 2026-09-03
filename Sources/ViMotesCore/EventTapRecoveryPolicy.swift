public struct EventTapRecoveryPolicy: Sendable {
  private let retryInterval: Double
  private var nextAllowedAttempt: Double = 0

  public init(retryInterval: Double) {
    self.retryInterval = retryInterval
  }

  public mutating func shouldAttemptStart(
    permissionGranted: Bool,
    tapIsRunning: Bool,
    now: Double
  ) -> Bool {
    guard permissionGranted, !tapIsRunning, now >= nextAllowedAttempt else {
      return false
    }

    nextAllowedAttempt = now + retryInterval
    return true
  }
}
