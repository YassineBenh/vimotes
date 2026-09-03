import AppKit
import ViMotesCore

@MainActor
final class MenuBarModeIndicator {
  private let button: NSStatusBarButton

  init(button: NSStatusBarButton) {
    self.button = button
    button.imagePosition = .imageLeading
    button.imageScaling = .scaleProportionallyDown
    button.font = .monospacedSystemFont(ofSize: 10.5, weight: .semibold)
    button.setAccessibilityLabel("ViMotes")
  }

  func update(
    mode: VimMode,
    isActive: Bool,
    isEnabled: Bool,
    permissionGranted: Bool,
    showsMode: Bool
  ) {
    if !permissionGranted {
      display(
        image: symbol("exclamationmark.triangle.fill"),
        title: nil,
        toolTip: "ViMotes needs Accessibility permission",
        accessibilityValue: "Accessibility permission required"
      )
      return
    }

    if !isEnabled {
      display(
        image: symbol("pause.fill"),
        title: nil,
        toolTip: "ViMotes is disabled",
        accessibilityValue: "Disabled"
      )
      return
    }

    if isActive && showsMode {
      display(
        image: dot(color: color(for: mode)),
        title: mode.rawValue,
        toolTip: "ViMotes — \(mode.rawValue) mode",
        accessibilityValue: "\(mode.rawValue) mode"
      )
      return
    }

    display(
      image: symbol("character.cursor.ibeam"),
      title: nil,
      toolTip: isActive ? "ViMotes is active" : "ViMotes activates in Apple Notes",
      accessibilityValue: isActive ? "Active" : "Waiting for Apple Notes"
    )
  }

  private func display(
    image: NSImage?,
    title: String?,
    toolTip: String,
    accessibilityValue: String
  ) {
    button.image = image
    button.title = title.map { " \($0)" } ?? ""
    button.toolTip = toolTip
    button.setAccessibilityValue(accessibilityValue)
  }

  private func symbol(_ name: String) -> NSImage? {
    let configuration = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
    let image = NSImage(
      systemSymbolName: name,
      accessibilityDescription: "ViMotes"
    )?.withSymbolConfiguration(configuration)
    image?.isTemplate = true
    return image
  }

  private func dot(color: NSColor) -> NSImage {
    let image = NSImage(size: NSSize(width: 8, height: 8), flipped: false) { rect in
      color.setFill()
      NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5)).fill()
      return true
    }
    image.isTemplate = false
    return image
  }

  private func color(for mode: VimMode) -> NSColor {
    switch mode {
    case .normal: .systemBlue
    case .insert: .systemGreen
    case .visual: .systemOrange
    }
  }
}
