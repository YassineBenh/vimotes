import Foundation
import Testing

struct ReleasePublicationTests {
  @Test("Release tag planning creates, skips, or rejects without ambiguity")
  func tagPlanningIsIdempotent() throws {
    #expect(try runShell("vimotes_tag_action '' abc123") == "create")
    #expect(try runShell("vimotes_tag_action abc123 abc123") == "skip")
    #expect(try runShell("vimotes_tag_action old123 abc123") == "conflict")
  }

  @Test("Installing the same appcast twice produces no second change")
  func appcastInstallationIsIdempotent() throws {
    let root = FileManager.default.temporaryDirectory
      .appending(path: "ViMotesReleaseTests-\(UUID().uuidString)")
    let payload = root.appending(path: "payload")
    let pages = root.appending(path: "pages")
    try FileManager.default.createDirectory(
      at: payload,
      withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(at: pages, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data("feed".utf8).write(to: payload.appending(path: "appcast.xml"))

    let first = try runShell(
      "vimotes_sync_pages_payload '\(payload.path)' '\(pages.path)'"
    )
    let second = try runShell(
      "vimotes_sync_pages_payload '\(payload.path)' '\(pages.path)'"
    )

    #expect(first == "changed")
    #expect(second == "unchanged")
    #expect(
      FileManager.default.fileExists(atPath: pages.appending(path: ".nojekyll").path)
    )
    #expect(
      try String(contentsOf: pages.appending(path: "appcast.xml"), encoding: .utf8)
        == "feed"
    )
  }

  private func runShell(_ command: String) throws -> String {
    let repositoryURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let libraryURL = repositoryURL.appending(path: "scripts/lib/release-publication.sh")
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    process.arguments = ["-c", "source \(libraryURL.path); \(command)"]
    process.standardOutput = output
    process.standardError = output
    try process.run()
    process.waitUntilExit()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    let value = String(decoding: data, as: UTF8.self)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard process.terminationStatus == 0 else {
      throw ShellTestError.failed(value)
    }
    return value
  }
}

private enum ShellTestError: Error {
  case failed(String)
}
