import ApplicationServices
import Carbon

enum KeyboardLayout {
  static func character(for keyCode: CGKeyCode) -> Character? {
    withKeyboardLayout { layout in
      translatedCharacter(for: UInt16(keyCode), layout: layout)
    }
  }

  static func character(from event: CGEvent) -> Character? {
    var length = 0
    var buffer = [UniChar](repeating: 0, count: 4)
    event.keyboardGetUnicodeString(
      maxStringLength: buffer.count,
      actualStringLength: &length,
      unicodeString: &buffer
    )
    guard length > 0 else { return nil }
    return String(utf16CodeUnits: buffer, count: length).first
  }

  static func keyCode(for character: Character) -> CGKeyCode? {
    let expected = String(character).lowercased()
    return withKeyboardLayout { layout in
      for rawKeyCode in 0..<128 {
        if translatedCharacter(for: UInt16(rawKeyCode), layout: layout).map({
          String($0).lowercased()
        }) == expected {
          return CGKeyCode(rawKeyCode)
        }
      }
      return nil
    }
  }

  private static func withKeyboardLayout<T>(
    _ operation: (UnsafePointer<UCKeyboardLayout>) -> T?
  ) -> T? {
    let inputSource = TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
    guard
      let property = TISGetInputSourceProperty(inputSource, kTISPropertyUnicodeKeyLayoutData)
    else {
      return nil
    }
    let data = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue()
    guard let layout = UnsafePointer<UCKeyboardLayout>(
      OpaquePointer(CFDataGetBytePtr(data))
    ) else {
      return nil
    }
    return withExtendedLifetime((inputSource, data)) {
      operation(layout)
    }
  }

  private static func translatedCharacter(
    for keyCode: UInt16,
    layout: UnsafePointer<UCKeyboardLayout>
  ) -> Character? {
    var deadKeyState: UInt32 = 0
    var length = 0
    var buffer = [UniChar](repeating: 0, count: 4)
    let status = UCKeyTranslate(
      layout,
      keyCode,
      UInt16(kUCKeyActionDown),
      0,
      UInt32(LMGetKbdType()),
      OptionBits(kUCKeyTranslateNoDeadKeysMask),
      &deadKeyState,
      buffer.count,
      &length,
      &buffer
    )
    guard status == noErr, length > 0 else { return nil }
    return String(utf16CodeUnits: buffer, count: length).first
  }
}
