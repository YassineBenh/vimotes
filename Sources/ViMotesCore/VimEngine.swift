public enum VimMode: String, Equatable, Sendable {
  case normal = "NORMAL"
  case insert = "INSERT"
  case visual = "VISUAL"
}

public enum VimInput: Equatable, Sendable {
  case character(Character)
  case control(Character)
  case command(Character)
  case escape
  case backspace
  case deleteForward
  case newline
  case tab
  case other
}

public enum CursorMotion: Equatable, Sendable {
  case characterBackward
  case characterForward
  case lineDown
  case lineUp
  case wordForward
  case wordBackward
  case wordEnd
  case lineStart
  case lineEnd
  case documentStart
  case documentEnd
  case paragraphBackward
  case paragraphForward
}

public enum ScrollDirection: Equatable, Sendable {
  case up
  case down
}

public enum LineBoundary: Equatable, Sendable {
  case start
  case end
}

public enum VimAction: Equatable, Sendable {
  case move(CursorMotion, extendingSelection: Bool = false)
  case collapseSelection
  case selectCurrentCharacter
  case selectCurrentLines(Int)
  case selectCurrentLineContents(Int)
  case selectToLineBoundary(LineBoundary)
  case deleteBackward
  case deleteForward
  case deleteSelection
  case insertNewline
  case insertText(String)
  case joinLines(Int)
  case copySelection
  case paste
  case undo
  case redo
  case openFind
  case findNext
  case findPrevious
  case scrollHalfPage(ScrollDirection)
  case changeMode(VimMode)
}

public struct VimTransition: Equatable, Sendable {
  public let consumesInput: Bool
  public let actions: [VimAction]
  public let mode: VimMode

  public init(consumesInput: Bool, actions: [VimAction], mode: VimMode) {
    self.consumesInput = consumesInput
    self.actions = actions
    self.mode = mode
  }

  public static func passthrough(mode: VimMode) -> Self {
    Self(consumesInput: false, actions: [], mode: mode)
  }
}

public struct VimEngine: Sendable {
  public static let maximumCount = 100
  public static let maximumActions = 256
  public static let maximumRecordedTextBytes = 16_384
  private struct VimCount: Sendable {
    private(set) var input = ""
    private var value: Int?

    var resolved: Int { value ?? 1 }

    mutating func append(_ character: Character) -> Bool {
      guard let digit = character.wholeNumberValue,
        digit != 0 || value != nil
      else {
        return false
      }
      if input.count < 8 { input.append(character) }
      value = min(VimEngine.maximumCount, (value ?? 0) * 10 + digit)
      return true
    }

    mutating func consume() -> (value: Int, input: String) {
      let result = (resolved, input)
      self = VimCount()
      return result
    }
  }

  private enum OperatorKind: Sendable {
    case delete
    case change
    case yank

    var character: Character {
      switch self {
      case .delete: "d"
      case .change: "c"
      case .yank: "y"
      }
    }
  }

  private struct PendingOperator: Sendable {
    let kind: OperatorKind
    let leadingCount: Int
    var inputPrefix: String
    var motionCount = VimCount()
    var isWaitingForSecondG = false
  }

  private struct PendingReplace: Sendable {
    let count: Int
    let inputPrefix: String
  }

  private struct InsertRecording: Sendable {
    let actions: [VimAction]
    var text = ""
  }

  public private(set) var mode: VimMode
  private var pendingCount = VimCount()
  private var pendingGPrefix: String?
  private var pendingOperator: PendingOperator?
  private var pendingReplace: PendingReplace?
  private var insertRecording: InsertRecording?
  private var lastChange: [VimAction] = []
  private var visualSelection: [VimAction] = []

  public init(mode: VimMode = .normal) {
    self.mode = mode
  }

  public mutating func cancelContext() {
    if insertRecording != nil { lastChange = [] }
    insertRecording = nil
    visualSelection = []
    resetPendingInput()
    mode = .normal
  }

  public mutating func discardLastChange() {
    lastChange = []
    insertRecording = nil
  }

  public mutating func handle(_ input: VimInput) -> VimTransition {
    if case .command = input {
      if mode == .insert || mode == .visual {
        discardLastChange()
        visualSelection = []
      }
      let restoration = pendingInputPrefix
      resetPendingInput()
      return passthrough(restoring: restoration)
    }

    switch mode {
    case .insert:
      return handleInsert(input)
    case .normal:
      return handleNormal(input)
    case .visual:
      let transition = handleVisual(input)
      if !transition.consumesInput {
        visualSelection = []
        discardLastChange()
      }
      if mode == .visual {
        let selections = transition.actions.filter {
          if case .move = $0 { return true }
          return false
        }
        if !visualSelection.isEmpty,
          visualSelection.count + selections.count <= Self.maximumActions - 4
        {
          visualSelection += selections
        } else {
          visualSelection = []
        }
      }
      return transition
    }
  }

  private mutating func handleInsert(_ input: VimInput) -> VimTransition {
    if input == .escape {
      finishInsertRecording()
      return changeMode(to: .normal, after: .collapseSelection)
    }

    guard var recording = insertRecording else { return .passthrough(mode: mode) }
    switch input {
    case .character(let character):
      if character.unicodeScalars.contains(where: {
        $0.value < 32 || $0.value == 127 || (0xF700...0xF8FF).contains($0.value)
      }) {
        discardLastChange()
        return .passthrough(mode: mode)
      }
      recording.text.append(character)
    case .newline:
      recording.text.append("\n")
    case .tab:
      recording.text.append("\t")
    case .backspace:
      guard !recording.text.isEmpty else {
        discardLastChange()
        return .passthrough(mode: mode)
      }
      recording.text.removeLast()
    default:
      discardLastChange()
      return .passthrough(mode: mode)
    }
    guard recording.text.utf8.count <= Self.maximumRecordedTextBytes else {
      discardLastChange()
      return .passthrough(mode: mode)
    }
    insertRecording = recording
    return .passthrough(mode: mode)
  }

  private mutating func handleNormal(_ input: VimInput) -> VimTransition {
    if input == .escape {
      resetPendingInput()
      return consumed(.collapseSelection)
    }

    if pendingOperator != nil {
      return handlePendingOperator(input)
    }

    if pendingReplace != nil {
      return handlePendingReplace(input)
    }

    if pendingGPrefix != nil {
      return handlePendingG(input)
    }

    if input == .control("r") {
      return consumed(repeating: [.redo], count: pendingCount.consume().value)
    }

    if input == .control("u") {
      return consumed(
        repeating: [.scrollHalfPage(.up)], count: pendingCount.consume().value)
    }

    if input == .control("d") {
      return consumed(
        repeating: [.scrollHalfPage(.down)], count: pendingCount.consume().value)
    }

    guard case .character(let character) = input else {
      let restoration = pendingCount.input
      resetPendingInput()
      return passthrough(restoring: restoration)
    }

    if pendingCount.append(character) {
      return consumed()
    }

    let resolvedCount = pendingCount.consume()
    let count = resolvedCount.value

    if let motion = VimCommandCatalog.motion(for: character) {
      return consumed(repeating: [.move(motion)], count: count)
    }

    switch character {
    case "g":
      pendingGPrefix = resolvedCount.input + "g"
      return consumed()
    case "i": return enterInsert(after: .collapseSelection)
    case "a":
      return enterInsert(
        after: .collapseSelection, .move(.characterForward)
      )
    case "I": return enterInsert(after: .move(.lineStart))
    case "A": return enterInsert(after: .move(.lineEnd))
    case "o": return enterInsert(after: .move(.lineEnd), .insertNewline)
    case "O":
      return enterInsert(
        after: .move(.lineStart), .insertNewline, .move(.lineUp)
      )
    case "x":
      return recordAndConsumeChange(
        [.collapseSelection] + Array(repeating: .deleteForward, count: count))
    case "X":
      return recordAndConsumeChange(
        [.collapseSelection] + Array(repeating: .deleteBackward, count: count))
    case "u": return consumed(repeating: [.undo], count: count)
    case "r":
      pendingReplace = PendingReplace(
        count: count,
        inputPrefix: resolvedCount.input + "r"
      )
      return consumed()
    case "v":
      visualSelection = [.collapseSelection, .selectCurrentCharacter]
      return changeMode(
        to: .visual,
        after: .collapseSelection, .selectCurrentCharacter
      )
    case "V":
      visualSelection = [.collapseSelection, .selectCurrentLines(count)]
      return changeMode(
        to: .visual,
        after: .collapseSelection, .selectCurrentLines(count)
      )
    case "Y":
      return consumed(
        .collapseSelection,
        .selectCurrentLines(count),
        .copySelection,
        .collapseSelection
      )
    case "D":
      return recordAndConsumeChange([
        .collapseSelection,
        .selectCurrentLines(count),
        .deleteSelection,
      ])
    case "d": return beginOperator(.delete, count: count, input: resolvedCount.input)
    case "c": return beginOperator(.change, count: count, input: resolvedCount.input)
    case "y": return beginOperator(.yank, count: count, input: resolvedCount.input)
    case "C":
      return enterInsert(
        after:
          .collapseSelection,
        .selectToLineBoundary(.end),
        .deleteSelection
      )
    case "S":
      return enterInsert(
        after: .collapseSelection, .selectCurrentLineContents(count), .deleteSelection
      )
    case "J":
      return recordAndConsumeChange([.collapseSelection, .joinLines(count)])
    case "p":
      return recordAndConsumeChange(
        [.collapseSelection, .move(.characterForward)]
          + Array(repeating: .paste, count: count))
    case "P":
      return recordAndConsumeChange(
        [.collapseSelection] + Array(repeating: .paste, count: count))
    case ".": return consumed(repeating: lastChange, count: count)
    case "/": return consumed(.openFind)
    case "n": return consumed(repeating: [.findNext], count: count)
    case "N": return consumed(repeating: [.findPrevious], count: count)
    default: return passthrough(restoring: resolvedCount.input)
    }
  }

  private mutating func handleVisual(_ input: VimInput) -> VimTransition {
    if input == .escape || input == .character("v") {
      return changeMode(to: .normal, after: .collapseSelection)
    }

    if pendingGPrefix != nil {
      return handlePendingG(input)
    }

    guard case .character(let character) = input else {
      let restoration = pendingCount.input
      resetPendingInput()
      return passthrough(restoring: restoration)
    }

    if pendingCount.append(character) {
      return consumed()
    }

    let resolvedCount = pendingCount.consume()
    let count = resolvedCount.value

    if let motion = VimCommandCatalog.motion(for: character) {
      return consumed(repeating: [.move(motion, extendingSelection: true)], count: count)
    }

    switch character {
    case "g":
      pendingGPrefix = resolvedCount.input + "g"
      return consumed()
    case "d", "x":
      lastChange = visualSelection.isEmpty ? [] : visualSelection + [.deleteSelection]
      return changeMode(to: .normal, after: .deleteSelection)
    case "c":
      lastChange = []
      insertRecording =
        visualSelection.isEmpty
        ? nil : InsertRecording(actions: visualSelection + [.deleteSelection])
      return changeMode(to: .insert, after: .deleteSelection)
    case "y":
      return changeMode(
        to: .normal,
        after: .copySelection, .collapseSelection
      )
    default: return passthrough(restoring: resolvedCount.input)
    }
  }

  private func consumed(_ actions: VimAction...) -> VimTransition {
    VimTransition(consumesInput: true, actions: actions, mode: mode)
  }

  private func consumed(_ actions: [VimAction]) -> VimTransition {
    VimTransition(consumesInput: true, actions: actions, mode: mode)
  }

  private func consumed(repeating actions: [VimAction], count: Int) -> VimTransition {
    guard !actions.isEmpty, count <= Self.maximumActions / actions.count else { return consumed() }
    return consumed(Array(repeating: actions, count: count).flatMap { $0 })
  }

  private func passthrough(restoring input: String) -> VimTransition {
    VimTransition(
      consumesInput: false,
      actions: input.isEmpty ? [] : [.insertText(input)],
      mode: mode
    )
  }

  private mutating func recordAndConsumeChange(
    _ actions: [VimAction]
  ) -> VimTransition {
    lastChange = actions
    return consumed(actions)
  }

  private mutating func beginOperator(
    _ kind: OperatorKind,
    count: Int,
    input: String
  ) -> VimTransition {
    pendingOperator = PendingOperator(
      kind: kind,
      leadingCount: count,
      inputPrefix: input + String(kind.character)
    )
    return consumed()
  }

  private mutating func handlePendingG(_ input: VimInput) -> VimTransition {
    guard pendingGPrefix != nil,
      input == .character("g")
    else {
      let restoration = pendingGPrefix ?? ""
      resetPendingInput()
      return passthrough(restoring: restoration)
    }

    self.pendingGPrefix = nil
    return consumed(
      .move(.documentStart, extendingSelection: mode == .visual)
    )
  }

  private mutating func handlePendingOperator(_ input: VimInput) -> VimTransition {
    guard var pendingOperator,
      case .character(let character) = input
    else {
      let restoration = pendingOperator?.inputPrefix ?? ""
      resetPendingInput()
      return passthrough(restoring: restoration)
    }

    if pendingOperator.motionCount.append(character) {
      if pendingOperator.inputPrefix.count < 18 { pendingOperator.inputPrefix.append(character) }
      self.pendingOperator = pendingOperator
      return consumed()
    }

    let count = min(
      Self.maximumCount,
      pendingOperator.leadingCount * pendingOperator.motionCount.resolved
    )

    if pendingOperator.isWaitingForSecondG {
      guard character == "g" else {
        let restoration = pendingOperator.inputPrefix
        resetPendingInput()
        return passthrough(restoring: restoration)
      }
      return completeOperator(
        pendingOperator.kind,
        motion: .documentStart,
        count: count
      )
    }

    if character == "g" {
      pendingOperator.isWaitingForSecondG = true
      pendingOperator.inputPrefix.append(character)
      self.pendingOperator = pendingOperator
      return consumed()
    }

    if character == pendingOperator.kind.character {
      return completeLineOperator(pendingOperator.kind, count: count)
    }

    guard var motion = VimCommandCatalog.motion(for: character) else {
      let restoration = pendingOperator.inputPrefix
      resetPendingInput()
      return passthrough(restoring: restoration)
    }
    if pendingOperator.kind == .change, motion == .wordForward {
      motion = .wordEnd
    }
    return completeOperator(pendingOperator.kind, motion: motion, count: count)
  }

  private mutating func completeLineOperator(
    _ kind: OperatorKind,
    count: Int
  ) -> VimTransition {
    let selectionAction: VimAction =
      kind == .change
      ? .selectCurrentLineContents(count)
      : .selectCurrentLines(count)
    return completeOperator(
      kind,
      selectionActions: [.collapseSelection, selectionAction]
    )
  }

  private mutating func handlePendingReplace(_ input: VimInput) -> VimTransition {
    guard let pendingReplace,
      case .character(let character) = input
    else {
      let restoration = pendingReplace?.inputPrefix ?? ""
      resetPendingInput()
      return passthrough(restoring: restoration)
    }

    self.pendingReplace = nil
    let replacement = [VimAction.deleteForward, .insertText(String(character))]
    return recordAndConsumeChange(
      [.collapseSelection]
        + Array(repeating: replacement, count: pendingReplace.count).flatMap { $0 }
    )
  }

  private mutating func completeOperator(
    _ kind: OperatorKind,
    motion: CursorMotion,
    count: Int
  ) -> VimTransition {
    let selectionActions: [VimAction]
    switch motion {
    case .lineStart:
      selectionActions = [.collapseSelection, .selectToLineBoundary(.start)]
    case .lineEnd:
      selectionActions = [.collapseSelection, .selectToLineBoundary(.end)]
    default:
      selectionActions =
        [.collapseSelection]
        + Array(
          repeating: .move(motion, extendingSelection: true),
          count: count
        )
    }
    return completeOperator(
      kind,
      selectionActions: selectionActions
    )
  }

  private mutating func completeOperator(
    _ kind: OperatorKind,
    selectionActions: [VimAction]
  ) -> VimTransition {
    pendingOperator = nil

    switch kind {
    case .delete:
      return recordAndConsumeChange(selectionActions + [.deleteSelection])
    case .change:
      return enterInsert(
        after: selectionActions + [.deleteSelection]
      )
    case .yank:
      return consumed(selectionActions + [.copySelection, .collapseSelection])
    }
  }

  private var pendingInputPrefix: String {
    pendingOperator?.inputPrefix
      ?? pendingReplace?.inputPrefix
      ?? pendingGPrefix
      ?? pendingCount.input
  }

  private mutating func resetPendingInput() {
    pendingCount = VimCount()
    pendingGPrefix = nil
    pendingOperator = nil
    pendingReplace = nil
  }

  private mutating func enterInsert(
    after actions: VimAction...
  ) -> VimTransition {
    enterInsert(after: actions)
  }

  private mutating func enterInsert(
    after actions: [VimAction]
  ) -> VimTransition {
    insertRecording = InsertRecording(actions: actions)
    return changeMode(to: .insert, after: actions)
  }

  private mutating func finishInsertRecording() {
    guard let insertRecording else { return }
    self.insertRecording = nil

    let hasImmediateChange = insertRecording.actions.contains { action in
      switch action {
      case .deleteSelection, .insertNewline:
        true
      default:
        false
      }
    }
    guard hasImmediateChange || !insertRecording.text.isEmpty else { return }

    lastChange = insertRecording.actions
    if !insertRecording.text.isEmpty {
      lastChange.append(.insertText(insertRecording.text))
    }
  }

  private mutating func changeMode(
    to newMode: VimMode,
    after actions: VimAction...
  ) -> VimTransition {
    changeMode(to: newMode, after: actions)
  }

  private mutating func changeMode(
    to newMode: VimMode,
    after actions: [VimAction]
  ) -> VimTransition {
    mode = newMode
    resetPendingInput()
    return VimTransition(
      consumesInput: true,
      actions: actions + [.changeMode(newMode)],
      mode: newMode
    )
  }
}
