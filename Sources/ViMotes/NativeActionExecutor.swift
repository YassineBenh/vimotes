import ViMotesCore

enum EditorSelection {
  case unavailable
  case empty
  case selected
}

@MainActor
protocol EditorDriver {
  associatedtype Context: Equatable
  var context: Context? { get }
  var selection: EditorSelection { get }
  func perform(_ action: VimAction) async -> Bool
}

struct EditingResult: Equatable {
  let succeeded: Bool
  let copiedSelection: Bool
}

@MainActor
final class NativeActionExecutor<Driver: EditorDriver> {
  private let driver: Driver

  init(driver: Driver) {
    self.driver = driver
  }

  func execute(_ actions: [VimAction]) async -> EditingResult {
    guard actions.count <= VimEngine.maximumActions, let context = driver.context else {
      return EditingResult(succeeded: false, copiedSelection: false)
    }
    var copied = false
    for action in actions {
      guard !Task.isCancelled, driver.context == context else {
        return EditingResult(succeeded: false, copiedSelection: copied)
      }
      switch action {
      case .deleteSelection, .copySelection:
        guard driver.selection != .unavailable else {
          return EditingResult(succeeded: false, copiedSelection: copied)
        }
        if driver.selection == .empty { continue }
      case .deleteBackward, .deleteForward:
        guard driver.selection == .empty else {
          return EditingResult(succeeded: false, copiedSelection: copied)
        }
      default:
        break
      }
      guard await driver.perform(action) else {
        return EditingResult(succeeded: false, copiedSelection: copied)
      }
      if action == .copySelection { copied = true }
    }
    return EditingResult(succeeded: true, copiedSelection: copied)
  }
}
