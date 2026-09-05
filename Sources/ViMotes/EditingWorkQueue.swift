import ViMotesCore

@MainActor
final class EditingWorkQueue<Driver: EditorDriver, Event> {
  private struct Work {
    let actions: [VimAction]
    let event: Event?
    let context: Driver.Context
    var cost: Int { max(1, actions.count) }
  }

  private let driver: Driver
  private let executor: NativeActionExecutor<Driver>
  private let replay: @MainActor (Event) async -> Void
  private var queue: [Work] = []
  private var outstandingActions = 0
  private var worker: Task<Void, Never>?
  private var generation = 0
  var onFailure: (() -> Void)?
  var onCopy: (() -> Void)?
  var isBusy: Bool { worker != nil }

  init(driver: Driver, replay: @escaping @MainActor (Event) async -> Void) {
    self.driver = driver
    self.executor = NativeActionExecutor(driver: driver)
    self.replay = replay
  }

  func cancel() {
    generation += 1
    worker?.cancel()
    worker = nil
    queue = []
    outstandingActions = 0
  }

  func enqueue(_ actions: [VimAction], event: Event?, context: Driver.Context) {
    let work = Work(actions: actions, event: event, context: context)
    guard queue.count < 128, outstandingActions + work.cost <= VimEngine.maximumActions else {
      fail()
      return
    }
    queue.append(work)
    outstandingActions += work.cost
    guard worker == nil else { return }
    let jobGeneration = generation
    worker = Task { [weak self] in
      await self?.drain(generation: jobGeneration)
    }
  }

  func finishPendingWork() async {
    await worker?.value
  }

  private func fail() {
    cancel()
    onFailure?()
  }

  private func drain(generation jobGeneration: Int) async {
    defer { if generation == jobGeneration { worker = nil } }
    while !queue.isEmpty, !Task.isCancelled, generation == jobGeneration {
      let work = queue.removeFirst()
      guard driver.context == work.context else {
        fail()
        return
      }
      let result = await executor.execute(work.actions)
      guard generation == jobGeneration, !Task.isCancelled else { return }
      guard result.succeeded, driver.context == work.context else {
        fail()
        return
      }
      if result.copiedSelection { onCopy?() }
      if let event = work.event {
        await replay(event)
        guard generation == jobGeneration, !Task.isCancelled else { return }
      }
      outstandingActions -= work.cost
    }
  }
}
