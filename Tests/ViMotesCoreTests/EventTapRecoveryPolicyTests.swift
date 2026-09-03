import Testing

@testable import ViMotesCore

struct EventTapRecoveryPolicyTests {
  @Test("Event tap is retried when Accessibility becomes available")
  func retriesAfterPermissionGrant() {
    var policy = EventTapRecoveryPolicy(retryInterval: 1)

    let whileDenied = policy.shouldAttemptStart(
      permissionGranted: false, tapIsRunning: false, now: 0)
    let afterGrant = policy.shouldAttemptStart(
      permissionGranted: true, tapIsRunning: false, now: 0)
    let duringCooldown = policy.shouldAttemptStart(
      permissionGranted: true, tapIsRunning: false, now: 0.25)
    let whileRunning = policy.shouldAttemptStart(
      permissionGranted: true, tapIsRunning: true, now: 1)
    let afterTapStops = policy.shouldAttemptStart(
      permissionGranted: true, tapIsRunning: false, now: 1)

    #expect(!whileDenied)
    #expect(afterGrant)
    #expect(!duringCooldown)
    #expect(!whileRunning)
    #expect(afterTapStops)
  }
}
