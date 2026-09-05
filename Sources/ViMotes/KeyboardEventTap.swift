@preconcurrency import ApplicationServices
import ViMotesCore

@MainActor
protocol KeyboardEventTapDelegate: AnyObject {
  func keyboardEventTapDidChangeMode(to mode: VimMode)
  func keyboardEventTapDidYank()
  func keyboardEventTapWasDisabled()
}

@MainActor
final class KeyboardEventTap {
  weak var delegate: KeyboardEventTapDelegate?
  var isEnabled = true {
    didSet { if isEnabled != oldValue { cancelContext() } }
  }

  private var engine = VimEngine()
  private let actionQueue: EditingWorkQueue<NotesEditorDriver, CGEvent>
  private var currentContext: NotesFocus.EditorContext?
  private var swallowedKeys: Set<CGKeyCode> = []
  private var deferredKeys: Set<CGKeyCode> = []
  private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?

  init() {
    actionQueue = EditingWorkQueue(
      driver: NotesEditorDriver(),
      replay: { event in
        event.setIntegerValueField(.eventSourceUserData, value: EventOrigin.marker)
        event.post(tap: .cghidEventTap)
        try? await Task.sleep(for: .milliseconds(8))
      }
    )
    actionQueue.onFailure = { [weak self] in
      guard let self else { return }
      self.cancelContext()
      self.engine.discardLastChange()
      self.delegate?.keyboardEventTapDidChangeMode(to: self.engine.mode)
    }
    actionQueue.onCopy = { [weak self] in
      self?.delegate?.keyboardEventTapDidYank()
    }
  }

  var mode: VimMode { engine.mode }
  var isRunning: Bool {
    guard let eventTap else { return false }
    return CGEvent.tapIsEnabled(tap: eventTap)
  }

  func start() -> Bool {
    if let eventTap {
      CGEvent.tapEnable(tap: eventTap, enable: true)
      return CGEvent.tapIsEnabled(tap: eventTap)
    }

    let eventMask = [CGEventType.keyDown, .keyUp, .leftMouseDown, .rightMouseDown]
      .reduce(CGEventMask(0)) { $0 | CGEventMask(1 << $1.rawValue) }
    let callback: CGEventTapCallBack = { _, type, event, userInfo in
      guard let userInfo else { return Unmanaged.passUnretained(event) }
      let controller = Unmanaged<KeyboardEventTap>
        .fromOpaque(userInfo)
        .takeUnretainedValue()

      let consumesEvent = MainActor.assumeIsolated {
        controller.handle(type: type, event: event)
      }
      return consumesEvent ? nil : Unmanaged.passUnretained(event)
    }

    guard
      let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: eventMask,
        callback: callback,
        userInfo: Unmanaged.passUnretained(self).toOpaque()
      )
    else {
      return false
    }

    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    eventTap = tap
    runLoopSource = source
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    return true
  }

  func stop() {
    cancelContext()
    if let eventTap {
      CGEvent.tapEnable(tap: eventTap, enable: false)
    }
    if let runLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
    }
    eventTap = nil
    runLoopSource = nil
  }

  private func handle(type: CGEventType, event: CGEvent) -> Bool {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      cancelContext()
      if let eventTap {
        CGEvent.tapEnable(tap: eventTap, enable: true)
      }
      delegate?.keyboardEventTapWasDisabled()
      return false
    }

    guard event.getIntegerValueField(.eventSourceUserData) != EventOrigin.marker else {
      return false
    }
    if type == .leftMouseDown || type == .rightMouseDown {
      cancelContext()
      return false
    }
    refreshContext()
    let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
    if type == .keyUp {
      if deferredKeys.remove(keyCode) != nil {
        swallowedKeys.remove(keyCode)
        if let context = currentContext {
          enqueue([], event: event, context: context)
          return true
        }
        return false
      }
      if swallowedKeys.remove(keyCode) != nil { return true }
      return false
    }
    guard type == .keyDown, isEnabled, let context = currentContext else { return false }

    let input = VimInput(event: event)
    if input == .escape, actionQueue.isBusy, engine.mode != .insert { cancelContext() }
    let transition = engine.handle(input)
    let deferEvent =
      !transition.consumesInput && (!transition.actions.isEmpty || actionQueue.isBusy)
    if !transition.actions.isEmpty || deferEvent {
      enqueue(transition.actions, event: deferEvent ? event : nil, context: context)
    }
    if transition.consumesInput { swallowedKeys.insert(keyCode) }
    if deferEvent { deferredKeys.insert(keyCode) }

    if transition.actions.contains(where: { action in
      if case .changeMode = action { return true }
      return false
    }) {
      delegate?.keyboardEventTapDidChangeMode(to: transition.mode)
    }

    return transition.consumesInput || deferEvent
  }

  func refreshContext() {
    let context = isEnabled ? NotesFocus.editorContext : nil
    if currentContext != context {
      cancelContext()
      currentContext = context
    }
  }

  private func cancelContext() {
    actionQueue.cancel()
    engine.cancelContext()
  }

  private func enqueue(_ actions: [VimAction], event: CGEvent?, context: NotesFocus.EditorContext) {
    actionQueue.enqueue(actions, event: event?.copy(), context: context)
  }
}

extension VimInput {
  fileprivate init(event: CGEvent) {
    let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
    let flags = event.flags

    if keyCode == 53 {
      self = .escape
      return
    }

    if flags.contains(.maskCommand) {
      self = .command(KeyboardLayout.character(from: event) ?? " ")
      return
    }

    if flags.contains(.maskControl) {
      self = KeyboardLayout.character(for: keyCode).map(VimInput.control) ?? .other
      return
    }

    switch keyCode {
    case 51:
      self = flags.contains(.maskAlternate) ? .other : .backspace
      return
    case 117:
      self = .deleteForward
      return
    case 36, 76:
      self = .newline
      return
    case 48:
      self = .tab
      return
    case 123...126:
      self = .other
      return
    default: break
    }

    if let character = KeyboardLayout.character(from: event) {
      self = .character(character)
    } else {
      self = .other
    }
  }
}
