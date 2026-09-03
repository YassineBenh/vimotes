import AppKit
@preconcurrency import ApplicationServices
import ViMotesCore

enum AccessibilityPermission {
  static var isGranted: Bool {
    AXIsProcessTrusted()
  }

  static func request() {
    AXIsProcessTrustedWithOptions(
      [
        "AXTrustedCheckOptionPrompt": true
      ] as CFDictionary)
  }
}

enum NotesFocus {
  enum SelectionResult {
    case unavailable
    case empty
    case selected
  }

  private struct LineSelectionContext {
    let element: AXUIElement
    let selectedRange: CFRange
    let lineNumber: Int
    let currentLine: CFRange
  }

  private static let notesBundleIdentifier = "com.apple.Notes"
  private static let supportedEditorRoles: Set<String> = [
    kAXTextAreaRole as String,
    "AXWebArea",
  ]

  static var isEditorFocused: Bool {
    guard AccessibilityPermission.isGranted,
      NSWorkspace.shared.frontmostApplication?.bundleIdentifier == notesBundleIdentifier,
      let focusedElement = focusedUIElement(),
      let role: String = attribute(kAXRoleAttribute, from: focusedElement),
      supportedEditorRoles.contains(role)
    else {
      return false
    }

    let enabled: Bool? = attribute(kAXEnabledAttribute, from: focusedElement)
    return enabled ?? true
  }

  static var hasSelection: Bool {
    guard let focusedElement = focusedUIElement(),
      let range = selectedTextRange(from: focusedElement)
    else {
      return false
    }
    return range.length > 0
  }

  static var activeWindowFrame: CGRect? {
    guard AccessibilityPermission.isGranted,
      let application = NSWorkspace.shared.frontmostApplication,
      application.bundleIdentifier == notesBundleIdentifier,
      let primaryScreen = NSScreen.screens.first
    else {
      return nil
    }

    let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
    guard let window = elementAttribute(kAXFocusedWindowAttribute, from: applicationElement),
      let position = pointAttribute(kAXPositionAttribute, from: window),
      let size = sizeAttribute(kAXSizeAttribute, from: window)
    else {
      return nil
    }

    return CGRect(
      x: position.x,
      y: primaryScreen.frame.maxY - position.y - size.height,
      width: size.width,
      height: size.height
    )
  }

  static func selectCurrentLines(_ count: Int) -> Bool {
    guard let context = lineSelectionContext() else { return false }

    let selectionRange: CFRange
    if let nextLine = rangeParameterizedAttribute(
      kAXRangeForLineParameterizedAttribute,
      parameter: context.lineNumber + max(1, count),
      from: context.element
    ), nextLine.location >= context.currentLine.location {
      selectionRange = CFRange(
        location: context.currentLine.location,
        length: nextLine.location - context.currentLine.location
      )
    } else {
      let characterCount: NSNumber? = attribute(
        kAXNumberOfCharactersAttribute,
        from: context.element
      )
      let selectionEnd = max(
        context.currentLine.location + context.currentLine.length,
        characterCount?.intValue ?? 0
      )
      if context.lineNumber > 0,
        context.currentLine.location > 0,
        let previousLine = rangeParameterizedAttribute(
          kAXRangeForLineParameterizedAttribute,
          parameter: context.lineNumber - 1,
          from: context.element
        )
      {
        let previousLineEnd = previousLine.location + previousLine.length
        let selectionStart = min(previousLineEnd, context.currentLine.location - 1)
        selectionRange = CFRange(
          location: selectionStart,
          length: selectionEnd - selectionStart
        )
      } else {
        selectionRange = CFRange(
          location: context.currentLine.location,
          length: selectionEnd - context.currentLine.location
        )
      }
    }

    return selectionRange.length > 0
      && setSelectedTextRange(selectionRange, in: context.element)
  }

  static func selectCurrentLineContents(_ count: Int) -> Bool {
    guard let context = lineSelectionContext() else { return false }

    let lastLineNumber = context.lineNumber + max(1, count) - 1
    let selectionEnd: Int
    if let lastLine = rangeParameterizedAttribute(
      kAXRangeForLineParameterizedAttribute,
      parameter: lastLineNumber,
      from: context.element
    ) {
      selectionEnd = lastLine.location + lastLine.length
    } else {
      let characterCount: NSNumber? = attribute(
        kAXNumberOfCharactersAttribute,
        from: context.element
      )
      selectionEnd = max(
        context.currentLine.location + context.currentLine.length,
        characterCount?.intValue ?? 0
      )
    }

    let range = CFRange(
      location: context.currentLine.location,
      length: max(0, selectionEnd - context.currentLine.location)
    )
    return setSelectedTextRange(range, in: context.element)
  }

  static func selectToLineBoundary(_ boundary: LineBoundary) -> SelectionResult {
    guard let context = lineSelectionContext() else { return .unavailable }

    let boundaryLocation = boundary == .start
      ? context.currentLine.location
      : context.currentLine.location + context.currentLine.length
    let range = CFRange(
      location: min(context.selectedRange.location, boundaryLocation),
      length: abs(boundaryLocation - context.selectedRange.location)
    )
    guard setSelectedTextRange(range, in: context.element) else { return .unavailable }
    return range.length > 0 ? .selected : .empty
  }

  static func joinableLineCount(maximum: Int) -> Int? {
    guard let context = lineSelectionContext(),
      let characterCount: NSNumber = attribute(
        kAXNumberOfCharactersAttribute,
        from: context.element
      ),
      characterCount.intValue > 0,
      let lastLineNumber = integerParameterizedAttribute(
        kAXLineForIndexParameterizedAttribute,
        parameter: characterCount.intValue - 1,
        from: context.element
      )
    else {
      return nil
    }
    return min(max(0, maximum), max(0, lastLineNumber - context.lineNumber))
  }

  @discardableResult
  static func collapseSelection() -> Bool {
    guard let focusedElement = focusedUIElement(),
      let range = selectedTextRange(from: focusedElement)
    else {
      return true
    }

    guard range.length > 0 else { return true }

    return setSelectedTextRange(
      CFRange(location: range.location, length: 0),
      in: focusedElement
    )
  }

  private static func lineSelectionContext() -> LineSelectionContext? {
    guard let element = focusedUIElement(),
      let selectedRange = selectedTextRange(from: element),
      let lineNumber = insertionLineNumber(
        at: selectedRange.location,
        in: element
      ),
      let currentLine = rangeParameterizedAttribute(
        kAXRangeForLineParameterizedAttribute,
        parameter: lineNumber,
        from: element
      )
    else {
      return nil
    }
    return LineSelectionContext(
      element: element,
      selectedRange: selectedRange,
      lineNumber: lineNumber,
      currentLine: currentLine
    )
  }

  private static func setSelectedTextRange(
    _ selectedRange: CFRange,
    in element: AXUIElement
  ) -> Bool {
    var range = selectedRange
    guard let value = AXValueCreate(.cfRange, &range) else { return false }
    return AXUIElementSetAttributeValue(
      element,
      kAXSelectedTextRangeAttribute as CFString,
      value
    ) == .success
  }

  private static func focusedUIElement() -> AXUIElement? {
    let systemWideElement = AXUIElementCreateSystemWide()
    var value: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(
      systemWideElement,
      kAXFocusedUIElementAttribute as CFString,
      &value
    )

    guard result == .success, let value,
      CFGetTypeID(value) == AXUIElementGetTypeID()
    else {
      return nil
    }

    return unsafeDowncast(value, to: AXUIElement.self)
  }

  private static func attribute<T>(_ name: String, from element: AXUIElement) -> T? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
      return nil
    }
    return value as? T
  }

  private static func elementAttribute(
    _ name: String,
    from element: AXUIElement
  ) -> AXUIElement? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success,
      let value,
      CFGetTypeID(value) == AXUIElementGetTypeID()
    else {
      return nil
    }
    return unsafeDowncast(value, to: AXUIElement.self)
  }

  private static func pointAttribute(
    _ name: String,
    from element: AXUIElement
  ) -> CGPoint? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success,
      let value,
      CFGetTypeID(value) == AXValueGetTypeID()
    else {
      return nil
    }

    let axValue = unsafeDowncast(value, to: AXValue.self)
    var point = CGPoint.zero
    return AXValueGetValue(axValue, .cgPoint, &point) ? point : nil
  }

  private static func sizeAttribute(
    _ name: String,
    from element: AXUIElement
  ) -> CGSize? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success,
      let value,
      CFGetTypeID(value) == AXValueGetTypeID()
    else {
      return nil
    }

    let axValue = unsafeDowncast(value, to: AXValue.self)
    var size = CGSize.zero
    return AXValueGetValue(axValue, .cgSize, &size) ? size : nil
  }

  private static func selectedTextRange(from element: AXUIElement) -> CFRange? {
    var value: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(
        element,
        kAXSelectedTextRangeAttribute as CFString,
        &value
      ) == .success,
      let value,
      CFGetTypeID(value) == AXValueGetTypeID()
    else {
      return nil
    }

    let axValue = unsafeDowncast(value, to: AXValue.self)
    guard AXValueGetType(axValue) == .cfRange else { return nil }

    var range = CFRange()
    return AXValueGetValue(axValue, .cfRange, &range) ? range : nil
  }

  private static func insertionLineNumber(
    at characterIndex: Int,
    in element: AXUIElement
  ) -> Int? {
    if let number: NSNumber = attribute(
      kAXInsertionPointLineNumberAttribute,
      from: element
    ) {
      return number.intValue
    }

    guard let characterCount: NSNumber = attribute(
      kAXNumberOfCharactersAttribute,
      from: element
    ), characterCount.intValue > 0 else {
      return nil
    }
    return integerParameterizedAttribute(
      kAXLineForIndexParameterizedAttribute,
      parameter: min(characterIndex, characterCount.intValue - 1),
      from: element
    )
  }

  private static func integerParameterizedAttribute(
    _ name: String,
    parameter: Int,
    from element: AXUIElement
  ) -> Int? {
    var value: CFTypeRef?
    guard AXUIElementCopyParameterizedAttributeValue(
      element,
      name as CFString,
      NSNumber(value: parameter),
      &value
    ) == .success else {
      return nil
    }
    return (value as? NSNumber)?.intValue
  }

  private static func rangeParameterizedAttribute(
    _ name: String,
    parameter: Int,
    from element: AXUIElement
  ) -> CFRange? {
    var value: CFTypeRef?
    guard AXUIElementCopyParameterizedAttributeValue(
      element,
      name as CFString,
      NSNumber(value: parameter),
      &value
    ) == .success,
      let value,
      CFGetTypeID(value) == AXValueGetTypeID()
    else {
      return nil
    }

    let axValue = unsafeDowncast(value, to: AXValue.self)
    guard AXValueGetType(axValue) == .cfRange else { return nil }
    var range = CFRange()
    return AXValueGetValue(axValue, .cfRange, &range) ? range : nil
  }
}
