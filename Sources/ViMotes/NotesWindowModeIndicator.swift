import AppKit
import ViMotesCore

@MainActor
final class NotesWindowModeIndicator {
  private let panel: NSPanel
  private let dot: NSView
  private let label: NSTextField
  private var currentMode = VimMode.normal
  private var currentWindowFrame: CGRect?
  private var feedbackTimer: Timer?

  init() {
    dot = NSView(frame: NSRect(x: 0, y: 0, width: 7, height: 7))
    dot.wantsLayer = true
    dot.layer?.cornerRadius = 3.5

    label = NSTextField(labelWithString: VimMode.normal.rawValue)
    label.font = .monospacedSystemFont(ofSize: 10.5, weight: .semibold)
    label.textColor = .labelColor
    label.setContentHuggingPriority(.required, for: .horizontal)

    let stack = NSStackView(views: [dot, label])
    stack.orientation = .horizontal
    stack.alignment = .centerY
    stack.spacing = 7
    stack.edgeInsets = NSEdgeInsets(top: 6, left: 9, bottom: 6, right: 10)

    let background = NSVisualEffectView(
      frame: NSRect(x: 0, y: 0, width: 88, height: 28)
    )
    background.material = .hudWindow
    background.blendingMode = .behindWindow
    background.state = .active
    background.wantsLayer = true
    background.layer?.cornerRadius = 8
    background.layer?.borderWidth = 0.5
    background.layer?.borderColor = NSColor.separatorColor.cgColor
    background.addSubview(stack)

    stack.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: background.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: background.trailingAnchor),
      stack.topAnchor.constraint(equalTo: background.topAnchor),
      stack.bottomAnchor.constraint(equalTo: background.bottomAnchor),
      dot.widthAnchor.constraint(equalToConstant: 7),
      dot.heightAnchor.constraint(equalToConstant: 7),
    ])

    panel = NSPanel(
      contentRect: background.frame,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.contentView = background
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.level = .floating
    panel.ignoresMouseEvents = true
    panel.hasShadow = true
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.setAccessibilityLabel("ViMotes mode")
  }

  func update(mode: VimMode, notesWindowFrame: CGRect?) {
    guard mode != currentMode || notesWindowFrame != currentWindowFrame else { return }
    currentMode = mode
    currentWindowFrame = notesWindowFrame

    guard let notesWindowFrame else {
      panel.orderOut(nil)
      return
    }

    if feedbackTimer == nil {
      showMode(mode)
    }
    panel.setFrameOrigin(
      NSPoint(
        x: notesWindowFrame.maxX - panel.frame.width - 14,
        y: notesWindowFrame.minY + 14
      )
    )
    panel.orderFrontRegardless()
  }

  func showYankFeedback() {
    guard currentWindowFrame != nil else { return }

    feedbackTimer?.invalidate()
    label.stringValue = "YANKED"
    dot.layer?.backgroundColor = NSColor.systemGreen.cgColor
    panel.setAccessibilityValue("Yanked selection")

    let pulse = CAKeyframeAnimation(keyPath: "transform.scale")
    pulse.values = [1, 1.08, 1]
    pulse.keyTimes = [0, 0.45, 1]
    pulse.duration = 0.32
    panel.contentView?.layer?.add(pulse, forKey: "yankPulse")

    feedbackTimer = Timer.scheduledTimer(withTimeInterval: 0.65, repeats: false) {
      [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        self.feedbackTimer = nil
        self.showMode(self.currentMode)
      }
    }
  }

  private func showMode(_ mode: VimMode) {
    label.stringValue = mode.rawValue
    dot.layer?.backgroundColor = color(for: mode).cgColor
    panel.setAccessibilityValue("\(mode.rawValue) mode")
  }

  private func color(for mode: VimMode) -> NSColor {
    switch mode {
    case .normal: .systemBlue
    case .insert: .systemGreen
    case .visual: .systemOrange
    }
  }
}
