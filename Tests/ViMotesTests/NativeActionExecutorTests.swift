import Testing
import ViMotesCore

@testable import ViMotes

@MainActor
struct NativeActionExecutorTests {
  @MainActor
  final class Driver: EditorDriver {
    var context: Int? = 1
    var selection = EditorSelection.empty
    var actions: [VimAction] = []
    var fails = false
    var changesFocus = false

    func perform(_ action: VimAction) async -> Bool {
      actions.append(action)
      if changesFocus { context = 2 }
      return !fails
    }
  }

  @Test func emptyMovementDoesNotDeletePreviousCharacter() async {
    let driver = Driver()
    let executor = NativeActionExecutor(driver: driver)
    let result = await executor.execute([
      .move(.characterForward, extendingSelection: true), .deleteSelection,
    ])
    #expect(result.succeeded)
    #expect(!driver.actions.contains(.deleteSelection))
  }

  @Test func unavailableSelectionFailsClosed() async {
    let driver = Driver()
    driver.selection = .unavailable
    let result = await NativeActionExecutor(driver: driver).execute([.deleteSelection])
    #expect(!result.succeeded)
    #expect(driver.actions.isEmpty)
  }

  @Test func changedFocusCancelsRemainingEdits() async {
    let driver = Driver()
    driver.changesFocus = true
    let result = await NativeActionExecutor(driver: driver).execute([
      .move(.lineEnd), .deleteForward,
    ])
    #expect(!result.succeeded)
    #expect(!driver.actions.contains(.deleteForward))
  }

  @Test func failedSelectionCancelsDeletion() async {
    let driver = Driver()
    driver.fails = true
    let result = await NativeActionExecutor(driver: driver).execute([
      .selectCurrentLines(1), .deleteSelection,
    ])
    #expect(!result.succeeded)
    #expect(driver.actions == [.selectCurrentLines(1)])
  }

  @Test func yankFeedbackRequiresAnActualCopy() async {
    let driver = Driver()
    let executor = NativeActionExecutor(driver: driver)
    #expect(
      await executor.execute([.copySelection])
        == EditingResult(succeeded: true, copiedSelection: false))
    driver.selection = .selected
    #expect(
      await executor.execute([.copySelection])
        == EditingResult(succeeded: true, copiedSelection: true))
  }

  @Test func oversizedBatchDoesNotRun() async {
    let driver = Driver()
    let result = await NativeActionExecutor(driver: driver).execute(
      Array(repeating: .deleteForward, count: 257))
    #expect(!result.succeeded)
    #expect(driver.actions.isEmpty)
  }

  @Test func missingContextDoesNotRun() async {
    let driver = Driver()
    driver.context = nil
    let result = await NativeActionExecutor(driver: driver).execute([.deleteForward])
    #expect(!result.succeeded)
    #expect(driver.actions.isEmpty)
  }

  @Test func selectedTextIsNotDeletedByCharacterCommands() async {
    let driver = Driver()
    driver.selection = .selected
    let result = await NativeActionExecutor(driver: driver).execute([.deleteForward])
    #expect(!result.succeeded)
    #expect(driver.actions.isEmpty)
  }

  @Test func cancelledExecutionHasNoEffects() async {
    let driver = Driver()
    let executor = NativeActionExecutor(driver: driver)
    let task = Task { await executor.execute([.deleteForward]) }
    task.cancel()
    #expect(await task.value.succeeded == false)
    #expect(driver.actions.isEmpty)
  }
}
