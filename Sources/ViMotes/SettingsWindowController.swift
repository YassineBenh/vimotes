import AppKit
import ServiceManagement

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
  private enum Section {
    case general
    case commands
    case accessibility
  }

  private enum Links {
    static let repository = URL(string: "https://github.com/YassineBenh/vimotes")!
    static let newIssue = URL(string: "https://github.com/YassineBenh/vimotes/issues/new")!
  }

  private let settings: ViMotesSettings
  private let launchAtLoginManager: LaunchAtLoginManager
  private let tabViewController: NSTabViewController
  private let menuBarSwitch: NSSwitch
  private let notesWindowSwitch: NSSwitch
  private let launchAtLoginSwitch: NSSwitch
  private let launchAtLoginDetail: NSTextField
  private let automaticUpdatesSwitch: NSSwitch
  private let githubButton: NSButton
  private let reportIssueButton: NSButton
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
    githubButton = NSButton(title: "Open GitHub", target: nil, action: nil)
    reportIssueButton = NSButton(title: "Report an Issue", target: nil, action: nil)
    accessibilityStatusDot = NSView()
    accessibilityStatusTitle = NSTextField(labelWithString: "")
    accessibilityStatusDetail = NSTextField(wrappingLabelWithString: "")
    accessibilityButton = NSButton(title: "", target: nil, action: nil)

    tabViewController.tabStyle = .toolbar
    tabViewController.preferredContentSize = NSSize(width: 620, height: 480)
    tabViewController.addTabViewItem(
      SettingsViews.makeTab(
        label: "General",
        symbol: "slider.horizontal.3",
        view: SettingsViews.makeGeneralView(
          menuBarSwitch: menuBarSwitch,
          notesWindowSwitch: notesWindowSwitch,
          launchAtLoginSwitch: launchAtLoginSwitch,
          launchAtLoginDetail: launchAtLoginDetail,
          automaticUpdatesSwitch: automaticUpdatesSwitch,
          githubButton: githubButton,
          reportIssueButton: reportIssueButton
        )
      )
    )
    tabViewController.addTabViewItem(
      SettingsViews.makeTab(
        label: "Commands",
        symbol: "keyboard",
        view: SettingsViews.makeCommandsView()
      )
    )
    tabViewController.addTabViewItem(
      SettingsViews.makeTab(
        label: "Accessibility",
        symbol: "lock.shield",
        view: SettingsViews.makeAccessibilityView(
          statusDot: accessibilityStatusDot,
          statusTitle: accessibilityStatusTitle,
          statusDetail: accessibilityStatusDetail,
          actionButton: accessibilityButton
        )
      )
    )

    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 620, height: 480),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    window.title = "ViMotes Settings"
    window.isReleasedWhenClosed = false
    window.contentViewController = tabViewController
    window.setContentSize(NSSize(width: 620, height: 480))
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
    githubButton.target = self
    githubButton.action = #selector(openGitHubRepository)
    reportIssueButton.target = self
    reportIssueButton.action = #selector(openNewGitHubIssue)
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

  @objc private func openGitHubRepository() {
    NSWorkspace.shared.open(Links.repository)
  }

  @objc private func openNewGitHubIssue() {
    NSWorkspace.shared.open(Links.newIssue)
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
}
