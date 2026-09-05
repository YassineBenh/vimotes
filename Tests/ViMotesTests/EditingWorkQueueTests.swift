import Testing
import ViMotesCore

@testable import ViMotes

@MainActor
struct EditingWorkQueueTests {
  final class Driver: EditorDriver {
    var context: Int? = 1
    var selection = EditorSelection.empty
    var effects: [String] = []
    var fails = false
    var changeFocus = false

    func perform(_ action: VimAction) async -> Bool {
      effects.append("action")
      await Task.yield()
      if changeFocus { context = 2 }
      return !fails
    }
  }

  @Test func fastInsertionKeepsActionsAndRawEventsInOrder() async {
    let driver = Driver()
    let queue = EditingWorkQueue<Driver, String>(driver: driver) { driver.effects.append($0) }
    queue.enqueue([.deleteForward], event: nil, context: 1)
    queue.enqueue([], event: "a-down", context: 1)
    queue.enqueue([], event: "a-up", context: 1)
    queue.enqueue([.collapseSelection], event: nil, context: 1)
    await queue.finishPendingWork()
    #expect(driver.effects == ["action", "a-down", "a-up", "action"])
    #expect(!queue.isBusy)
  }

  @Test func cancellingDropsQueuedEditsAndText() async {
    let driver = Driver()
    let queue = EditingWorkQueue<Driver, String>(driver: driver) { driver.effects.append($0) }
    queue.enqueue([.deleteForward], event: "text", context: 1)
    queue.cancel()
    await queue.finishPendingWork()
    #expect(driver.effects.isEmpty)
    #expect(!queue.isBusy)
  }

  @Test func focusChangeDuringAnActionPreventsReplayingText() async {
    let driver = Driver()
    driver.changeFocus = true
    let queue = EditingWorkQueue<Driver, String>(driver: driver) { driver.effects.append($0) }
    var failed = false
    queue.onFailure = { failed = true }
    queue.enqueue([.move(.lineEnd)], event: "text", context: 1)
    await queue.finishPendingWork()
    #expect(driver.effects == ["action"])
    #expect(failed)
  }

  @Test func failureDropsSubsequentWork() async {
    let driver = Driver()
    driver.fails = true
    let queue = EditingWorkQueue<Driver, String>(driver: driver) { driver.effects.append($0) }
    queue.enqueue([.move(.lineEnd)], event: nil, context: 1)
    queue.enqueue([.deleteForward], event: "text", context: 1)
    await queue.finishPendingWork()
    #expect(driver.effects == ["action"])
  }

  @Test func accumulatedWorkCannotExceedTheBudget() async {
    let driver = Driver()
    let queue = EditingWorkQueue<Driver, String>(driver: driver) { driver.effects.append($0) }
    var failed = false
    queue.onFailure = { failed = true }
    queue.enqueue(Array(repeating: .deleteForward, count: 200), event: nil, context: 1)
    queue.enqueue(Array(repeating: .deleteForward, count: 100), event: nil, context: 1)
    await queue.finishPendingWork()
    #expect(driver.effects.isEmpty)
    #expect(failed)
  }

  @Test func newWorkRunsAfterCancellation() async {
    let driver = Driver()
    let queue = EditingWorkQueue<Driver, String>(driver: driver) { driver.effects.append($0) }
    queue.enqueue([.deleteForward], event: "old", context: 1)
    queue.cancel()
    queue.enqueue([], event: "new", context: 1)
    await queue.finishPendingWork()
    #expect(driver.effects == ["new"])
  }
}
