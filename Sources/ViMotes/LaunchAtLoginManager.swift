import ServiceManagement

@MainActor
final class LaunchAtLoginManager {
  var status: SMAppService.Status {
    SMAppService.mainApp.status
  }

  var isRequested: Bool {
    status == .enabled || status == .requiresApproval
  }

  func setEnabled(_ enabled: Bool) throws {
    let service = SMAppService.mainApp
    if enabled {
      guard service.status == .notRegistered || service.status == .notFound else { return }
      try service.register()
    } else {
      guard service.status == .enabled || service.status == .requiresApproval else { return }
      try service.unregister()
    }
  }
}
