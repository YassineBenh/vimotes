import ApplicationServices
import ViMotesCore

enum EventOrigin {
  static let marker: Int64 = 0x56_494D_4F54_4553
}

@MainActor
struct NotesEditorDriver: EditorDriver {
  var context: NotesFocus.EditorContext? { NotesFocus.editorContext }
  var selection: EditorSelection {
    guard let snapshot = NotesFocus.selectionSnapshot else { return .unavailable }
    return snapshot.length > 0 ? .selected : .empty
  }

  func perform(_ action: VimAction) async -> Bool {
    guard let initialContext = context else { return false }
    let before = NotesFocus.selectionSnapshot
    let posted: Bool
    switch action {
    case .collapseSelection:
      return NotesFocus.collapseSelection()
    case .selectCurrentLines(let count):
      return NotesFocus.selectCurrentLines(count)
    case .selectCurrentLineContents(let count):
      return NotesFocus.selectCurrentLineContents(count)
    case .selectToLineBoundary(let boundary):
      switch NotesFocus.selectToLineBoundary(boundary) {
      case .unavailable: return false
      case .empty, .selected: return true
      }
    case .move(let motion, let extending):
      posted = sendMotion(motion, extendingSelection: extending)
    case .selectCurrentCharacter:
      posted = send(keyCode: 124, flags: .maskShift)
    case .deleteBackward, .deleteSelection:
      posted = send(keyCode: 51)
    case .deleteForward:
      posted = send(keyCode: 117)
    case .insertNewline:
      posted = send(keyCode: 36)
    case .insertText(let text):
      return await insert(text, in: initialContext)
    case .joinLines(let count):
      guard let lineCount = NotesFocus.joinableLineCount(maximum: count) else { return false }
      for _ in 0..<lineCount {
        guard !Task.isCancelled, context == initialContext,
          await perform(.move(.lineEnd)), context == initialContext,
          await perform(.deleteForward), context == initialContext,
          await insert(" ", in: initialContext)
        else { return false }
      }
      return true
    case .copySelection:
      posted = sendShortcut("c", flags: .maskCommand)
    case .paste:
      posted = sendShortcut("v", flags: .maskCommand)
    case .undo:
      posted = sendShortcut("z", flags: .maskCommand)
    case .redo:
      posted = sendShortcut("z", flags: [.maskCommand, .maskShift])
    case .openFind:
      posted = sendShortcut("f", flags: .maskCommand)
    case .findNext:
      posted = sendShortcut("g", flags: .maskCommand)
    case .findPrevious:
      posted = sendShortcut("g", flags: [.maskCommand, .maskShift])
    case .scrollHalfPage(let direction):
      posted = scrollHalfPage(direction)
    case .changeMode:
      return true
    }
    guard posted else { return false }
    for _ in 0..<12 {
      do { try await Task.sleep(for: .milliseconds(8)) } catch { return false }
      guard context == initialContext else { return false }
      if NotesFocus.selectionSnapshot != before { return true }
      if action == .copySelection || action == .openFind { return true }
    }
    switch action {
    case .move, .selectCurrentCharacter, .scrollHalfPage, .findNext, .findPrevious:
      return true
    default:
      return false
    }
  }

  private func insert(_ text: String, in initialContext: NotesFocus.EditorContext) async -> Bool {
    var chunks: [String] = []
    var chunk = ""
    for scalar in text.unicodeScalars {
      if chunk.utf16.count + scalar.utf16.count > 20 {
        chunks.append(chunk)
        chunk = ""
      }
      chunk.unicodeScalars.append(scalar)
    }
    if !chunk.isEmpty { chunks.append(chunk) }
    for chunk in chunks {
      guard !Task.isCancelled, context == initialContext else { return false }
      let before = NotesFocus.selectionSnapshot
      guard sendTextChunk(chunk) else { return false }
      var applied = false
      for _ in 0..<12 {
        do { try await Task.sleep(for: .milliseconds(8)) } catch { return false }
        guard context == initialContext else { return false }
        if NotesFocus.selectionSnapshot != before {
          applied = true
          break
        }
      }
      guard applied else { return false }
    }
    return true
  }

  private func sendTextChunk(_ text: String) -> Bool {
    let characters = Array(text.utf16)
    guard let source = CGEventSource(stateID: .hidSystemState),
      let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
      let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
    else { return false }
    for event in [down, up] {
      characters.withUnsafeBufferPointer {
        event.keyboardSetUnicodeString(stringLength: $0.count, unicodeString: $0.baseAddress)
      }
      event.flags = []
      event.setIntegerValueField(.eventSourceUserData, value: EventOrigin.marker)
      event.post(tap: .cghidEventTap)
    }
    return true
  }

  private func sendShortcut(_ character: Character, flags: CGEventFlags) -> Bool {
    guard let keyCode = KeyboardLayout.keyCode(for: character) else { return false }
    return send(keyCode: keyCode, flags: flags)
  }

  private func sendMotion(_ motion: CursorMotion, extendingSelection: Bool) -> Bool {
    let keyCode: CGKeyCode
    var flags: CGEventFlags = []

    switch motion {
    case .characterBackward: keyCode = 123
    case .characterForward: keyCode = 124
    case .lineDown: keyCode = 125
    case .lineUp: keyCode = 126
    case .wordForward:
      keyCode = 124
      flags.insert(.maskAlternate)
    case .wordBackward:
      keyCode = 123
      flags.insert(.maskAlternate)
    case .wordEnd:
      keyCode = 124
      flags.insert(.maskAlternate)
    case .lineStart:
      keyCode = 123
      flags.insert(.maskCommand)
    case .lineEnd:
      keyCode = 124
      flags.insert(.maskCommand)
    case .documentStart:
      keyCode = 126
      flags.insert(.maskCommand)
    case .documentEnd:
      keyCode = 125
      flags.insert(.maskCommand)
    case .paragraphBackward:
      keyCode = 126
      flags.insert(.maskAlternate)
    case .paragraphForward:
      keyCode = 125
      flags.insert(.maskAlternate)
    }

    if extendingSelection {
      flags.insert(.maskShift)
    }
    return send(keyCode: keyCode, flags: flags)
  }

  private func scrollHalfPage(_ direction: ScrollDirection) -> Bool {
    let distance = Int32(max(120, (NotesFocus.activeWindowFrame?.height ?? 600) / 2))
    let delta = direction == .up ? distance : -distance
    guard let source = CGEventSource(stateID: .hidSystemState),
      let event = CGEvent(
        scrollWheelEvent2Source: source,
        units: .pixel,
        wheelCount: 1,
        wheel1: delta,
        wheel2: 0,
        wheel3: 0
      )
    else {
      return false
    }
    event.setIntegerValueField(.eventSourceUserData, value: EventOrigin.marker)
    event.post(tap: .cghidEventTap)
    return true
  }

  private func send(keyCode: CGKeyCode, flags: CGEventFlags = []) -> Bool {
    guard let source = CGEventSource(stateID: .hidSystemState),
      let keyDown = CGEvent(
        keyboardEventSource: source,
        virtualKey: keyCode,
        keyDown: true
      ),
      let keyUp = CGEvent(
        keyboardEventSource: source,
        virtualKey: keyCode,
        keyDown: false
      )
    else {
      return false
    }

    for event in [keyDown, keyUp] {
      event.flags = flags
      event.setIntegerValueField(.eventSourceUserData, value: EventOrigin.marker)
      event.post(tap: .cghidEventTap)
    }
    return true
  }
}
