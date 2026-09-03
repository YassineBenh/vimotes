import Foundation
import Testing

@testable import ViMotes

@MainActor
struct ViMotesSettingsTests {
  @Test("Application preferences are enabled by default and persist")
  func preferencesPersist() {
    let suiteName = "ViMotesSettingsTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    defer {
      defaults.removePersistentDomain(forName: suiteName)
    }

    let settings = ViMotesSettings(defaults: defaults)
    #expect(settings.showsModeInMenuBar)
    #expect(settings.showsModeInNotesWindow)
    #expect(settings.automaticallyChecksForUpdates)

    var changeCount = 0
    settings.onChange = {
      changeCount += 1
    }
    settings.showsModeInMenuBar = false
    settings.showsModeInNotesWindow = false
    settings.automaticallyChecksForUpdates = false
    settings.showsModeInNotesWindow = false

    let reloadedSettings = ViMotesSettings(defaults: defaults)
    #expect(!reloadedSettings.showsModeInMenuBar)
    #expect(!reloadedSettings.showsModeInNotesWindow)
    #expect(!reloadedSettings.automaticallyChecksForUpdates)
    #expect(changeCount == 3)
  }
}
