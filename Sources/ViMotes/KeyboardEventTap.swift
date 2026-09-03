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
  var isEnabled = true

  private var engine = VimEngine()
  private let actionExecutor = NativeActionExecutor()
  private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?

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

    let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
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
      if let eventTap {
        CGEvent.tapEnable(tap: eventTap, enable: true)
      }
      delegate?.keyboardEventTapWasDisabled()
      return false
    }

    guard type == .keyDown,
      event.getIntegerValueField(.eventSourceUserData) != NativeActionExecutor.eventMarker,
      isEnabled,
      NotesFocus.isEditorFocused
    else {
      return false
    }

    let transition = engine.handle(VimInput(event: event))
    actionExecutor.execute(transition.actions)

    if transition.actions.contains(where: { action in
      if case .changeMode = action { return true }
      return false
    }) {
      delegate?.keyboardEventTapDidChangeMode(to: transition.mode)
    }

    if transition.actions.contains(.copySelection) {
      delegate?.keyboardEventTapDidYank()
    }

    return transition.consumesInput
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

    if let character = KeyboardLayout.character(from: event) {
      self = .character(character)
    } else {
      self = .other
    }
  }
}
