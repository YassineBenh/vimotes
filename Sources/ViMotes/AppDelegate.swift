import AppKit
import ViMotesCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, KeyboardEventTapDelegate {
  private let eventTap = KeyboardEventTap()
  private let modeIndicator = NotesWindowModeIndicator()
  private let settings = ViMotesSettings()
  private let updateController = UpdateController.configured()
  private var statusItem: NSStatusItem!
  private var menuBarModeIndicator: MenuBarModeIndicator!
  private lazy var settingsWindowController = SettingsWindowController(
    settings: settings,
    updatesAvailable: updateController != nil
  )
  private var enabledItem: NSMenuItem!
  private var modeItem: NSMenuItem!
  private var checkForUpdatesItem: NSMenuItem!
  private var focusTimer: Timer?
  private var eventTapRecoveryPolicy = EventTapRecoveryPolicy(retryInterval: 1)

  func applicationDidFinishLaunching(_ notification: Notification) {
    eventTap.delegate = self
    settings.onChange = { [weak self] in
      self?.applySettings()
    }
    configureStatusItem()
    updateController?.onUpdateAvailabilityChange = { [weak self] in
      self?.refreshState()
    }
    AccessibilityPermission.request()

    if !eventTap.start() {
      showPermissionAlert()
    }

    focusTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.refreshState()
      }
    }
    updateController?.automaticallyChecksForUpdates = settings.automaticallyChecksForUpdates
    updateController?.start()
    refreshState()
  }

  func applicationWillTerminate(_ notification: Notification) {
    focusTimer?.invalidate()
    eventTap.stop()
  }

  func keyboardEventTapDidChangeMode(to mode: VimMode) {
    modeItem.title = "Mode: \(mode.rawValue)"
    refreshState()
  }

  func keyboardEventTapDidYank() {
    modeIndicator.showYankFeedback()
  }

  func keyboardEventTapWasDisabled() {
    refreshState()
  }

  @objc private func toggleEnabled() {
    eventTap.isEnabled.toggle()
    enabledItem.state = eventTap.isEnabled ? .on : .off
    refreshState()
  }

  @objc private func showSettings() {
    settingsWindowController.showWindow(nil)
    NSApplication.shared.activate(ignoringOtherApps: true)
  }

  @objc private func checkForUpdates() {
    updateController?.checkForUpdates(nil)
  }

  @objc private func openIssues() {
    NSWorkspace.shared.open(URL(string: "https://github.com/YassineBenh/vimotes/issues")!)
  }

  @objc private func quit() {
    NSApplication.shared.terminate(nil)
  }

  private func configureStatusItem() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    if let button = statusItem.button {
      menuBarModeIndicator = MenuBarModeIndicator(button: button)
    }

    let menu = NSMenu()
    enabledItem = menu.addItem(
      withTitle: "Enable in Apple Notes",
      action: #selector(toggleEnabled),
      keyEquivalent: ""
    )
    enabledItem.target = self
    enabledItem.state = .on

    modeItem = NSMenuItem(title: "Mode: NORMAL", action: nil, keyEquivalent: "")
    modeItem.isEnabled = false
    menu.addItem(modeItem)
    menu.addItem(.separator())

    checkForUpdatesItem = menu.addItem(
      withTitle: "Check for Updates…",
      action: #selector(checkForUpdates),
      keyEquivalent: ""
    )
    checkForUpdatesItem.target = self

    let issuesItem = menu.addItem(
      withTitle: "Report an Issue…",
      action: #selector(openIssues),
      keyEquivalent: ""
    )
    issuesItem.target = self
    menu.addItem(.separator())

    let settingsItem = menu.addItem(
      withTitle: "Settings…",
      action: #selector(showSettings),
      keyEquivalent: ","
    )
    settingsItem.target = self
    menu.addItem(.separator())

    let quitItem = menu.addItem(
      withTitle: "Quit ViMotes",
      action: #selector(quit),
      keyEquivalent: "q"
    )
    quitItem.target = self
    statusItem.menu = menu
  }

  private func applySettings() {
    updateController?.automaticallyChecksForUpdates = settings.automaticallyChecksForUpdates
    refreshState()
  }

  private func refreshState() {
    eventTap.refreshContext()
    checkForUpdatesItem?.isEnabled = updateController?.canCheckForUpdates ?? false
    checkForUpdatesItem?.title =
      updateController?.hasPendingUpdate == true
      ? "Update Available…" : "Check for Updates…"
    let permissionGranted = AccessibilityPermission.isGranted
    if eventTapRecoveryPolicy.shouldAttemptStart(
      permissionGranted: permissionGranted,
      tapIsRunning: eventTap.isRunning,
      now: Date.timeIntervalSinceReferenceDate
    ) {
      _ = eventTap.start()
    }

    let active =
      eventTap.isEnabled && eventTap.isRunning && permissionGranted && NotesFocus.isEditorFocused
    modeItem.title = "Mode: \(eventTap.mode.rawValue)"
    menuBarModeIndicator.update(
      mode: eventTap.mode,
      isActive: active,
      isEnabled: eventTap.isEnabled,
      permissionGranted: permissionGranted,
      showsMode: settings.showsModeInMenuBar,
      hasPendingUpdate: updateController?.hasPendingUpdate ?? false
    )
    modeIndicator.update(
      mode: eventTap.mode,
      notesWindowFrame: active && settings.showsModeInNotesWindow
        ? NotesFocus.activeWindowFrame
        : nil
    )
  }

  private func showPermissionAlert() {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = "ViMotes needs Accessibility access"
    alert.informativeText =
      "Grant ViMotes access in System Settings. It will activate automatically as soon as the permission is available. This permission is required to intercept Vim commands only inside the Apple Notes editor."
    alert.addButton(withTitle: "Open ViMotes Settings")
    alert.addButton(withTitle: "Later")
    NSApplication.shared.activate(ignoringOtherApps: true)
    if alert.runModal() == .alertFirstButtonReturn {
      settingsWindowController.showAccessibility()
      NSApplication.shared.activate(ignoringOtherApps: true)
    }
  }
}
