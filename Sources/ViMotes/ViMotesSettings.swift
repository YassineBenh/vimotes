import Foundation

@MainActor
final class ViMotesSettings {
  private enum Key {
    static let showsModeInMenuBar = "showsModeInMenuBar"
    static let showsModeInNotesWindow = "showsModeInNotesWindow"
    static let automaticallyChecksForUpdates = "automaticallyChecksForUpdates"
  }

  private let defaults: UserDefaults
  var onChange: (() -> Void)?

  var showsModeInMenuBar: Bool {
    didSet {
      guard showsModeInMenuBar != oldValue else { return }
      defaults.set(showsModeInMenuBar, forKey: Key.showsModeInMenuBar)
      onChange?()
    }
  }

  var showsModeInNotesWindow: Bool {
    didSet {
      guard showsModeInNotesWindow != oldValue else { return }
      defaults.set(showsModeInNotesWindow, forKey: Key.showsModeInNotesWindow)
      onChange?()
    }
  }

  var automaticallyChecksForUpdates: Bool {
    didSet {
      guard automaticallyChecksForUpdates != oldValue else { return }
      defaults.set(
        automaticallyChecksForUpdates,
        forKey: Key.automaticallyChecksForUpdates
      )
      onChange?()
    }
  }

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    defaults.register(defaults: [
      Key.showsModeInMenuBar: true,
      Key.showsModeInNotesWindow: true,
      Key.automaticallyChecksForUpdates: true,
    ])
    showsModeInMenuBar = defaults.bool(forKey: Key.showsModeInMenuBar)
    showsModeInNotesWindow = defaults.bool(forKey: Key.showsModeInNotesWindow)
    automaticallyChecksForUpdates = defaults.bool(
      forKey: Key.automaticallyChecksForUpdates
    )
  }
}
