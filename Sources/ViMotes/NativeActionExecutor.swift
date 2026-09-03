import ApplicationServices
import ViMotesCore

final class NativeActionExecutor: Sendable {
  static let eventMarker: Int64 = 0x56_494D_4F54_4553

  func execute(_ actions: [VimAction]) {
    var previousAction: VimAction?
    var suppressesSelectionEffects = false

    for action in actions {
      switch action {
      case .move(let motion, let extendingSelection):
        if extendingSelection {
          suppressesSelectionEffects = false
        }
        sendMotion(motion, extendingSelection: extendingSelection)
      case .collapseSelection:
        if suppressesSelectionEffects {
          suppressesSelectionEffects = false
        } else if previousAction == .copySelection {
          send(keyCode: 123)
        } else if !NotesFocus.collapseSelection() {
          send(keyCode: 123)
        }
      case .selectCurrentCharacter:
        send(keyCode: 124, flags: .maskShift)
      case .selectCurrentLines(let count):
        suppressesSelectionEffects = false
        selectCurrentLines(count)
      case .selectCurrentLineContents(let count):
        suppressesSelectionEffects = !selectCurrentLineContents(count)
      case .selectToLineBoundary(let boundary):
        suppressesSelectionEffects = !selectToLineBoundary(boundary)
      case .deleteBackward:
        if !NotesFocus.hasSelection {
          send(keyCode: 51)
        }
      case .deleteForward:
        if !NotesFocus.hasSelection {
          send(keyCode: 117)
        }
      case .deleteSelection:
        if !suppressesSelectionEffects
          && (followsSelection(previousAction) || NotesFocus.hasSelection)
        {
          send(keyCode: 51)
        }
      case .insertNewline:
        send(keyCode: 36)
      case .insertText(let text):
        send(text: text)
      case .joinLines(let count):
        joinLines(count)
      case .copySelection:
        if !suppressesSelectionEffects {
          sendShortcut("c", flags: .maskCommand)
        }
      case .paste:
        sendShortcut("v", flags: .maskCommand)
      case .undo:
        sendShortcut("z", flags: .maskCommand)
      case .redo:
        sendShortcut("z", flags: [.maskCommand, .maskShift])
      case .openFind:
        sendShortcut("f", flags: .maskCommand)
      case .findNext:
        sendShortcut("g", flags: .maskCommand)
      case .findPrevious:
        sendShortcut("g", flags: [.maskCommand, .maskShift])
      case .scrollHalfPage(let direction):
        scrollHalfPage(direction)
      case .changeMode:
        break
      }

      previousAction = action
    }
  }

  private func sendShortcut(_ character: Character, flags: CGEventFlags) {
    guard let keyCode = KeyboardLayout.keyCode(for: character) else { return }
    send(keyCode: keyCode, flags: flags)
  }

  private func selectCurrentLines(_ count: Int) {
    guard !NotesFocus.selectCurrentLines(count) else { return }
    sendMotion(.lineStart, extendingSelection: false)
    sendMotion(.lineEnd, extendingSelection: true)
    sendMotion(.characterForward, extendingSelection: true)
    for _ in 1..<max(1, count) {
      sendMotion(.lineDown, extendingSelection: true)
      sendMotion(.lineEnd, extendingSelection: true)
      sendMotion(.characterForward, extendingSelection: true)
    }
  }

  private func followsSelection(_ action: VimAction?) -> Bool {
    switch action {
    case .selectCurrentLines, .selectCurrentLineContents,
      .selectToLineBoundary:
      true
    case .move(_, extendingSelection: true):
      true
    default:
      false
    }
  }

  private func selectCurrentLineContents(_ count: Int) -> Bool {
    if NotesFocus.selectCurrentLineContents(count) {
      return NotesFocus.hasSelection
    }
    sendMotion(.lineStart, extendingSelection: false)
    sendMotion(.lineEnd, extendingSelection: true)
    for _ in 1..<max(1, count) {
      sendMotion(.lineDown, extendingSelection: true)
      sendMotion(.lineEnd, extendingSelection: true)
    }
    return true
  }

  private func selectToLineBoundary(_ boundary: LineBoundary) -> Bool {
    switch NotesFocus.selectToLineBoundary(boundary) {
    case .selected:
      return true
    case .empty:
      return false
    case .unavailable:
      sendMotion(
        boundary == .start ? .lineStart : .lineEnd,
        extendingSelection: true
      )
      return true
    }
  }

  private func joinLines(_ count: Int) {
    guard let joinableLineCount = NotesFocus.joinableLineCount(maximum: count) else {
      return
    }
    for _ in 0..<joinableLineCount {
      sendMotion(.lineEnd, extendingSelection: false)
      send(keyCode: 117)
      send(text: " ")
    }
  }

  private func sendMotion(_ motion: CursorMotion, extendingSelection: Bool) {
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
    send(keyCode: keyCode, flags: flags)
  }

  private func scrollHalfPage(_ direction: ScrollDirection) {
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
      return
    }
    event.setIntegerValueField(.eventSourceUserData, value: Self.eventMarker)
    event.post(tap: .cghidEventTap)
  }

  private func send(keyCode: CGKeyCode, flags: CGEventFlags = []) {
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
      return
    }

    for event in [keyDown, keyUp] {
      event.flags = flags
      event.setIntegerValueField(.eventSourceUserData, value: Self.eventMarker)
      event.post(tap: .cghidEventTap)
    }
  }

  private func send(text: String) {
    let characters = Array(text.utf16)
    guard !characters.isEmpty,
      let source = CGEventSource(stateID: .hidSystemState)
    else {
      return
    }

    for isKeyDown in [true, false] {
      guard let event = CGEvent(
        keyboardEventSource: source,
        virtualKey: 0,
        keyDown: isKeyDown
      ) else {
        continue
      }
      characters.withUnsafeBufferPointer { buffer in
        event.keyboardSetUnicodeString(
          stringLength: buffer.count,
          unicodeString: buffer.baseAddress
        )
      }
      event.setIntegerValueField(.eventSourceUserData, value: Self.eventMarker)
      event.post(tap: .cghidEventTap)
    }
  }
}
