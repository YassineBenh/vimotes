import AppKit
import ServiceManagement

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
  private enum Section {
    case general
    case commands
    case accessibility
  }

  private let settings: ViMotesSettings
  private let launchAtLoginManager: LaunchAtLoginManager
  private let tabViewController: NSTabViewController
  private let menuBarSwitch: NSSwitch
  private let notesWindowSwitch: NSSwitch
  private let launchAtLoginSwitch: NSSwitch
  private let launchAtLoginDetail: NSTextField
  private let automaticUpdatesSwitch: NSSwitch
  private let accessibilityStatusDot: NSView
  private let accessibilityStatusTitle: NSTextField
  private let accessibilityStatusDetail: NSTextField
  private let accessibilityButton: NSButton
  private var accessibilityTimer: Timer?

  init(
    settings: ViMotesSettings,
    updatesAvailable: Bool
  ) {
    self.settings = settings
    launchAtLoginManager = LaunchAtLoginManager()
    tabViewController = NSTabViewController()
    menuBarSwitch = NSSwitch()
    notesWindowSwitch = NSSwitch()
    launchAtLoginSwitch = NSSwitch()
    launchAtLoginDetail = NSTextField(wrappingLabelWithString: "")
    automaticUpdatesSwitch = NSSwitch()
    accessibilityStatusDot = NSView()
    accessibilityStatusTitle = NSTextField(labelWithString: "")
    accessibilityStatusDetail = NSTextField(wrappingLabelWithString: "")
    accessibilityButton = NSButton(title: "", target: nil, action: nil)

    tabViewController.tabStyle = .toolbar
    tabViewController.preferredContentSize = NSSize(width: 620, height: 410)
    tabViewController.addTabViewItem(
      Self.makeTab(
        label: "General",
        symbol: "slider.horizontal.3",
        view: Self.makeGeneralView(
          menuBarSwitch: menuBarSwitch,
          notesWindowSwitch: notesWindowSwitch,
          launchAtLoginSwitch: launchAtLoginSwitch,
          launchAtLoginDetail: launchAtLoginDetail,
          automaticUpdatesSwitch: automaticUpdatesSwitch
        )
      )
    )
    tabViewController.addTabViewItem(
      Self.makeTab(
        label: "Commands",
        symbol: "keyboard",
        view: Self.makeCommandsView()
      )
    )
    tabViewController.addTabViewItem(
      Self.makeTab(
        label: "Accessibility",
        symbol: "lock.shield",
        view: Self.makeAccessibilityView(
          statusDot: accessibilityStatusDot,
          statusTitle: accessibilityStatusTitle,
          statusDetail: accessibilityStatusDetail,
          actionButton: accessibilityButton
        )
      )
    )

    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 620, height: 410),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    window.title = "ViMotes Settings"
    window.isReleasedWhenClosed = false
    window.contentViewController = tabViewController
    window.setContentSize(NSSize(width: 620, height: 410))
    window.center()

    super.init(window: window)

    window.delegate = self
    menuBarSwitch.target = self
    menuBarSwitch.action = #selector(toggleMenuBarMode)
    notesWindowSwitch.target = self
    notesWindowSwitch.action = #selector(toggleNotesWindowMode)
    launchAtLoginSwitch.target = self
    launchAtLoginSwitch.action = #selector(toggleLaunchAtLogin)
    automaticUpdatesSwitch.target = self
    automaticUpdatesSwitch.action = #selector(toggleAutomaticUpdates)
    automaticUpdatesSwitch.isEnabled = updatesAvailable
    accessibilityButton.target = self
    accessibilityButton.action = #selector(openAccessibilitySettings)
    syncControls()
    updateAccessibilityStatus()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func showWindow(_ sender: Any?) {
    present(section: .general, sender: sender)
  }

  func showAccessibility() {
    present(section: .accessibility, sender: nil)
  }

  func windowWillClose(_ notification: Notification) {
    accessibilityTimer?.invalidate()
    accessibilityTimer = nil
  }

  @objc private func toggleMenuBarMode() {
    settings.showsModeInMenuBar = menuBarSwitch.state == .on
  }

  @objc private func toggleNotesWindowMode() {
    settings.showsModeInNotesWindow = notesWindowSwitch.state == .on
  }

  @objc private func toggleLaunchAtLogin() {
    do {
      try launchAtLoginManager.setEnabled(launchAtLoginSwitch.state == .on)
      updateLaunchAtLoginStatus()
    } catch {
      updateLaunchAtLoginStatus()
      let alert = NSAlert(error: error)
      alert.messageText = "ViMotes could not update Launch at Login"
      if let window {
        alert.beginSheetModal(for: window)
      } else {
        alert.runModal()
      }
    }
  }

  @objc private func toggleAutomaticUpdates() {
    settings.automaticallyChecksForUpdates = automaticUpdatesSwitch.state == .on
  }

  @objc private func openAccessibilitySettings() {
    if !AccessibilityPermission.isGranted {
      AccessibilityPermission.request()
    }
    NSWorkspace.shared.open(
      URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
    )
    updateAccessibilityStatus()
  }

  private func present(section: Section, sender: Any?) {
    tabViewController.selectedTabViewItemIndex = tabIndex(for: section)
    syncControls()
    updateAccessibilityStatus()
    startAccessibilityUpdates()
    super.showWindow(sender)
    window?.makeKeyAndOrderFront(sender)
  }

  private func tabIndex(for section: Section) -> Int {
    switch section {
    case .general:
      0
    case .commands:
      1
    case .accessibility:
      2
    }
  }

  private func syncControls() {
    menuBarSwitch.state = settings.showsModeInMenuBar ? .on : .off
    notesWindowSwitch.state = settings.showsModeInNotesWindow ? .on : .off
    automaticUpdatesSwitch.state =
      settings.automaticallyChecksForUpdates
      ? .on
      : .off
    updateLaunchAtLoginStatus()
  }

  private func updateLaunchAtLoginStatus() {
    let status = launchAtLoginManager.status
    launchAtLoginSwitch.state = launchAtLoginManager.isRequested ? .on : .off

    switch status {
    case .enabled:
      launchAtLoginDetail.stringValue =
        "ViMotes will open automatically when you sign in to your Mac."
    case .requiresApproval:
      launchAtLoginDetail.stringValue =
        "Approval is required in System Settings → General → Login Items."
    case .notRegistered, .notFound:
      launchAtLoginDetail.stringValue =
        "Open ViMotes automatically when you sign in to your Mac."
    @unknown default:
      launchAtLoginDetail.stringValue = "The current Launch at Login status is unavailable."
    }
  }

  private func startAccessibilityUpdates() {
    accessibilityTimer?.invalidate()
    accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) {
      [weak self] _ in
      MainActor.assumeIsolated {
        self?.updateAccessibilityStatus()
      }
    }
  }

  private func updateAccessibilityStatus() {
    let granted = AccessibilityPermission.isGranted
    accessibilityStatusDot.layer?.backgroundColor =
      (granted ? NSColor.systemGreen : NSColor.systemOrange).cgColor
    accessibilityStatusTitle.stringValue =
      granted
      ? "Accessibility access is active"
      : "Accessibility access is required"
    accessibilityStatusDetail.stringValue =
      granted
      ? "ViMotes can detect the Notes editor and translate Vim commands."
      : "Grant access so ViMotes can detect the Notes editor and handle keyboard input."
    accessibilityButton.title = granted ? "Open System Settings…" : "Grant Access…"
  }

  private static func makeTab(label: String, symbol: String, view: NSView) -> NSTabViewItem {
    let viewController = NSViewController()
    viewController.view = view
    viewController.preferredContentSize = NSSize(width: 620, height: 410)
    let item = NSTabViewItem(viewController: viewController)
    item.label = label
    item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
    return item
  }

  private static func makeGeneralView(
    menuBarSwitch: NSSwitch,
    notesWindowSwitch: NSSwitch,
    launchAtLoginSwitch: NSSwitch,
    launchAtLoginDetail: NSTextField,
    automaticUpdatesSwitch: NSSwitch
  ) -> NSView {
    let menuBarRow = makeOptionRow(
      title: "Show mode in the menu bar",
      detail: "Display NORMAL, INSERT, or VISUAL next to the ViMotes icon while Notes is active.",
      toggle: menuBarSwitch
    )
    let notesWindowRow = makeOptionRow(
      title: "Show mode inside Apple Notes",
      detail:
        "Anchor a compact mode indicator to the lower-right corner of the active Notes window.",
      toggle: notesWindowSwitch
    )
    let launchAtLoginRow = makeOptionRow(
      title: "Launch ViMotes at login",
      detailField: launchAtLoginDetail,
      toggle: launchAtLoginSwitch
    )
    let updateRow = makeOptionRow(
      title: "Automatically check for updates",
      detail: "Show a notification when a signed ViMotes update is available.",
      toggle: automaticUpdatesSwitch
    )
    let options = NSStackView(views: [
      menuBarRow,
      makeDivider(),
      notesWindowRow,
      makeDivider(),
      launchAtLoginRow,
      makeDivider(),
      updateRow,
    ])
    options.orientation = .vertical
    options.alignment = .width
    options.spacing = 0

    let footer = NSTextField(labelWithString: "ViMotes is free and open source under MIT.")
    footer.font = .systemFont(ofSize: 11)
    footer.textColor = .secondaryLabelColor

    return makePage(
      title: "General",
      detail: "Choose how ViMotes appears and starts on your Mac.",
      symbol: "character.cursor.ibeam",
      color: .systemBlue,
      content: options,
      footer: footer,
      constraints: [
        menuBarRow.heightAnchor.constraint(equalToConstant: 56),
        notesWindowRow.heightAnchor.constraint(equalToConstant: 56),
        launchAtLoginRow.heightAnchor.constraint(equalToConstant: 56),
        updateRow.heightAnchor.constraint(equalToConstant: 56),
      ]
    )
  }

  private static func makeCommandsView() -> NSView {
    let normal = makeCommandRow(
      mode: "NORMAL",
      commands: "h j k l · w b e · 0 _ $ · { } · gg G",
      detail: "Characters, lines, words, paragraphs, and document boundaries",
      color: .systemBlue
    )
    let insert = makeCommandRow(
      mode: "INSERT",
      commands: "i a I A   o O   Esc",
      detail: "Enter Insert mode at the cursor, line boundaries, or a new line",
      color: .systemGreen
    )
    let editing = makeCommandRow(
      mode: "OPERATE",
      commands: "dd yy cc · d c y + motion",
      detail: "Delete, change, or yank lines and motion-defined ranges",
      color: .systemPurple
    )
    let changes = makeCommandRow(
      mode: "EDIT",
      commands: "x X · C S D Y J · r{char} · p P",
      detail: "Delete, change, replace, join, yank, and paste",
      color: .systemPink
    )
    let navigation = makeCommandRow(
      mode: "MORE",
      commands: "[count] · u Ctrl-r · . · / n N · Ctrl-u/d",
      detail: "Repeat, undo, search, and scroll by half a page",
      color: .systemIndigo
    )
    let visual = makeCommandRow(
      mode: "VISUAL",
      commands: "v V   motions   d x c y   Esc",
      detail: "Select characters or lines, then delete, change, yank, or cancel",
      color: .systemOrange
    )
    let rows = NSStackView(views: [
      normal,
      makeDivider(),
      insert,
      makeDivider(),
      editing,
      makeDivider(),
      changes,
      makeDivider(),
      navigation,
      makeDivider(),
      visual,
    ])
    rows.orientation = .vertical
    rows.alignment = .width
    rows.spacing = 0

    return makePage(
      title: "Supported commands",
      detail: "Commands currently translated into native Apple Notes actions.",
      symbol: "keyboard",
      color: .systemIndigo,
      content: rows,
      constraints: [
        normal.heightAnchor.constraint(equalToConstant: 48),
        insert.heightAnchor.constraint(equalToConstant: 48),
        editing.heightAnchor.constraint(equalToConstant: 48),
        changes.heightAnchor.constraint(equalToConstant: 48),
        navigation.heightAnchor.constraint(equalToConstant: 48),
        visual.heightAnchor.constraint(equalToConstant: 48),
      ]
    )
  }

  private static func makeAccessibilityView(
    statusDot: NSView,
    statusTitle: NSTextField,
    statusDetail: NSTextField,
    actionButton: NSButton
  ) -> NSView {
    statusDot.wantsLayer = true
    statusDot.layer?.cornerRadius = 5
    statusTitle.font = .systemFont(ofSize: 14, weight: .semibold)
    statusDetail.font = .systemFont(ofSize: 11.5)
    statusDetail.textColor = .secondaryLabelColor
    statusDetail.maximumNumberOfLines = 2
    actionButton.bezelStyle = .rounded

    let statusText = NSStackView(views: [statusTitle, statusDetail])
    statusText.orientation = .vertical
    statusText.alignment = .leading
    statusText.spacing = 4
    let statusRow = NSStackView(views: [statusDot, statusText, actionButton])
    statusRow.orientation = .horizontal
    statusRow.alignment = .centerY
    statusRow.spacing = 12
    statusText.setContentHuggingPriority(.defaultLow, for: .horizontal)
    statusText.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    actionButton.setContentHuggingPriority(.required, for: .horizontal)

    let statusCard = NSBox()
    statusCard.boxType = .custom
    statusCard.fillColor = .controlBackgroundColor
    statusCard.borderColor = .separatorColor
    statusCard.borderWidth = 0.5
    statusCard.cornerRadius = 10
    let statusContainer = NSView()
    statusContainer.addSubview(statusRow)
    statusRow.translatesAutoresizingMaskIntoConstraints = false
    statusCard.contentView = statusContainer
    NSLayoutConstraint.activate([
      statusRow.leadingAnchor.constraint(equalTo: statusContainer.leadingAnchor, constant: 16),
      statusRow.trailingAnchor.constraint(equalTo: statusContainer.trailingAnchor, constant: -16),
      statusRow.centerYAnchor.constraint(equalTo: statusContainer.centerYAnchor),
    ])

    let privacyTitle = NSTextField(labelWithString: "What ViMotes can access")
    privacyTitle.font = .systemFont(ofSize: 13, weight: .semibold)
    let privacyDetail = NSTextField(
      wrappingLabelWithString:
        "Accessibility is used to identify the focused Apple Notes editor and intercept keyboard input while it is active. ViMotes does not read or replace the contents of your notes."
    )
    privacyDetail.font = .systemFont(ofSize: 11.5)
    privacyDetail.textColor = .secondaryLabelColor
    privacyDetail.maximumNumberOfLines = 3
    let privacy = NSStackView(views: [privacyTitle, privacyDetail])
    privacy.orientation = .vertical
    privacy.alignment = .leading
    privacy.spacing = 6

    let content = NSStackView(views: [statusCard, privacy])
    content.orientation = .vertical
    content.alignment = .width
    content.spacing = 22

    return makePage(
      title: "Accessibility",
      detail: "Check the permission required for ViMotes to work in Apple Notes.",
      symbol: "lock.shield",
      color: .systemGreen,
      content: content,
      constraints: [
        statusCard.heightAnchor.constraint(equalToConstant: 88),
        statusDot.widthAnchor.constraint(equalToConstant: 10),
        statusDot.heightAnchor.constraint(equalToConstant: 10),
      ]
    )
  }

  private static func makePage(
    title: String,
    detail: String,
    symbol: String,
    color: NSColor,
    content pageContent: NSView,
    footer: NSView? = nil,
    constraints: [NSLayoutConstraint] = []
  ) -> NSView {
    let root = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 620, height: 410))
    root.material = .contentBackground
    root.state = .active

    let header = makeHeader(title: title, detail: detail, symbol: symbol, color: color)
    var views = [header, pageContent]
    if let footer {
      views.append(footer)
    }
    let stack = NSStackView(views: views)
    stack.orientation = .vertical
    stack.alignment = .width
    stack.spacing = 20
    stack.translatesAutoresizingMaskIntoConstraints = false
    root.addSubview(stack)

    NSLayoutConstraint.activate(
      [
        stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
        stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28),
        stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),
        stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -22),
      ] + constraints)
    return root
  }

  private static func makeHeader(
    title: String,
    detail: String,
    symbol: String,
    color: NSColor
  ) -> NSView {
    let icon = NSImageView()
    icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
    icon.contentTintColor = color
    icon.symbolConfiguration = .init(pointSize: 21, weight: .medium)

    let iconBackground = NSView()
    iconBackground.wantsLayer = true
    iconBackground.layer?.backgroundColor = color.withAlphaComponent(0.12).cgColor
    iconBackground.layer?.cornerRadius = 10
    iconBackground.addSubview(icon)
    icon.translatesAutoresizingMaskIntoConstraints = false

    let titleField = NSTextField(labelWithString: title)
    titleField.font = .systemFont(ofSize: 18, weight: .semibold)
    let detailField = NSTextField(labelWithString: detail)
    detailField.font = .systemFont(ofSize: 12)
    detailField.textColor = .secondaryLabelColor
    let text = NSStackView(views: [titleField, detailField])
    text.orientation = .vertical
    text.alignment = .leading
    text.spacing = 3
    let header = NSStackView(views: [iconBackground, text])
    header.orientation = .horizontal
    header.alignment = .centerY
    header.spacing = 13

    NSLayoutConstraint.activate([
      iconBackground.widthAnchor.constraint(equalToConstant: 42),
      iconBackground.heightAnchor.constraint(equalToConstant: 42),
      icon.centerXAnchor.constraint(equalTo: iconBackground.centerXAnchor),
      icon.centerYAnchor.constraint(equalTo: iconBackground.centerYAnchor),
    ])
    return header
  }

  private static func makeOptionRow(
    title: String,
    detail: String,
    toggle: NSSwitch
  ) -> NSView {
    let detailField = NSTextField(wrappingLabelWithString: detail)
    return makeOptionRow(title: title, detailField: detailField, toggle: toggle)
  }

  private static func makeOptionRow(
    title: String,
    detailField: NSTextField,
    toggle: NSSwitch
  ) -> NSView {
    let titleField = NSTextField(labelWithString: title)
    titleField.font = .systemFont(ofSize: 13, weight: .medium)
    detailField.font = .systemFont(ofSize: 11)
    detailField.textColor = .secondaryLabelColor
    detailField.maximumNumberOfLines = 2
    let text = NSStackView(views: [titleField, detailField])
    text.orientation = .vertical
    text.alignment = .leading
    text.spacing = 3
    let row = NSView()
    row.addSubview(text)
    row.addSubview(toggle)
    text.translatesAutoresizingMaskIntoConstraints = false
    toggle.translatesAutoresizingMaskIntoConstraints = false
    text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    toggle.setContentHuggingPriority(.required, for: .horizontal)
    NSLayoutConstraint.activate([
      text.leadingAnchor.constraint(equalTo: row.leadingAnchor),
      text.centerYAnchor.constraint(equalTo: row.centerYAnchor),
      text.trailingAnchor.constraint(
        lessThanOrEqualTo: toggle.leadingAnchor,
        constant: -16
      ),
      toggle.trailingAnchor.constraint(equalTo: row.trailingAnchor),
      toggle.centerYAnchor.constraint(equalTo: row.centerYAnchor),
    ])
    return row
  }

  private static func makeCommandRow(
    mode: String,
    commands: String,
    detail: String,
    color: NSColor
  ) -> NSView {
    let dot = NSView()
    dot.wantsLayer = true
    dot.layer?.backgroundColor = color.cgColor
    dot.layer?.cornerRadius = 4
    let modeField = NSTextField(labelWithString: mode)
    modeField.font = .monospacedSystemFont(ofSize: 10.5, weight: .semibold)
    modeField.textColor = color
    let modeStack = NSStackView(views: [dot, modeField])
    modeStack.orientation = .horizontal
    modeStack.alignment = .centerY
    modeStack.spacing = 7

    let commandsField = NSTextField(labelWithString: commands)
    commandsField.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
    let detailField = NSTextField(labelWithString: detail)
    detailField.font = .systemFont(ofSize: 10.5)
    detailField.textColor = .secondaryLabelColor
    let text = NSStackView(views: [commandsField, detailField])
    text.orientation = .vertical
    text.alignment = .leading
    text.spacing = 4
    let row = NSView()
    row.addSubview(modeStack)
    row.addSubview(text)
    modeStack.translatesAutoresizingMaskIntoConstraints = false
    text.translatesAutoresizingMaskIntoConstraints = false
    text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    NSLayoutConstraint.activate([
      dot.widthAnchor.constraint(equalToConstant: 8),
      dot.heightAnchor.constraint(equalToConstant: 8),
      modeStack.leadingAnchor.constraint(equalTo: row.leadingAnchor),
      modeStack.centerYAnchor.constraint(equalTo: row.centerYAnchor),
      modeStack.widthAnchor.constraint(equalToConstant: 112),
      text.leadingAnchor.constraint(equalTo: modeStack.trailingAnchor, constant: 20),
      text.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor),
      text.centerYAnchor.constraint(equalTo: row.centerYAnchor),
    ])
    return row
  }

  private static func makeDivider() -> NSBox {
    let divider = NSBox()
    divider.boxType = .separator
    return divider
  }
}
