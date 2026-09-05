import Foundation
import Testing

struct ReleasePublicationTests {
  @Test("Source snapshots include a version bump without staging the real index")
  func sourceSnapshotPreservesTheIndex() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    #expect(
      try runShell(
        """
        cd '\(directory.path)'
        git init -q
        print first > Info.plist
        git add Info.plist
        git -c user.name=Test -c user.email=test@example.invalid -c commit.gpgsign=false commit -qm initial
        initial_tree=$(git rev-parse 'HEAD^{tree}')
        print second > Info.plist
        snapshot=$(vimotes_source_tree)
        [[ "$snapshot" != "$initial_tree" ]]
        [[ "$(git write-tree)" == "$initial_tree" ]]
        git add Info.plist
        [[ "$(git write-tree)" == "$snapshot" ]]
        echo isolated
        """) == "isolated")
  }

  @Test("A manifest rejects another source tree, version, or build")
  func manifestBindsArtifactsToTheirSources() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let manifest = directory.appending(path: "manifest.plist").path
    #expect(
      try runShell(
        """
        vimotes_write_manifest '\(manifest)' tree123 1.2.0 9 publickey
        vimotes_verify_manifest '\(manifest)' tree123 1.2.0 9 && echo match
        ! vimotes_verify_manifest '\(manifest)' other 1.2.0 9 || exit 1
        ! vimotes_verify_manifest '\(manifest)' tree123 1.3.0 9 || exit 1
        ! vimotes_verify_manifest '\(manifest)' tree123 1.2.0 10 || exit 1
        """) == "match")
  }

  @Test("Release retry reuses identical assets and rejects changed ones")
  func assetRetryNeverOverwrites() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let asset = directory.appending(path: "app.zip")
    let downloaded = directory.appending(path: "downloads")
    try FileManager.default.createDirectory(at: downloaded, withIntermediateDirectories: true)
    try Data("archive".utf8).write(to: asset)
    #expect(
      try runShell(
        """
        gh() {
          case "$2" in
            view) echo app.zip ;;
            download) cp '\(asset.path)' '\(downloaded.path)/app.zip' ;;
            *) return 99 ;;
          esac
        }
        vimotes_ensure_release_asset v1.2.0 '\(asset.path)' '\(downloaded.path)' && echo reused
        gh() {
          case "$2" in
            view) echo app.zip ;;
            download) print wrong > '\(downloaded.path)/app.zip' ;;
            *) return 99 ;;
          esac
        }
        if vimotes_ensure_release_asset v1.2.0 '\(asset.path)' '\(downloaded.path)' 2>/dev/null; then
          exit 1
        fi
        echo rejected
        """) == "reused\nrejected")
  }

  @Test("A missing asset is uploaded on retry")
  func retryUploadsOnlyMissingAsset() throws {
    #expect(
      try runShell(
        """
        gh() {
          case "$2" in
            view) echo existing.zip ;;
            upload) echo uploaded ;;
            *) return 99 ;;
          esac
        }
        vimotes_ensure_release_asset v1.2.0 /tmp/new.zip /tmp
        """) == "uploaded")
  }

  private func temporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: "ViMotes release tests \(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

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
    process.arguments = ["-c", "set -e; source \"$1\"; \(command)", "-", libraryURL.path]
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
