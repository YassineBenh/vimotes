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
    let binaryLibraryURL = repositoryURL.appending(path: "scripts/lib/binary-distribution.sh")
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    process.arguments = [
      "-c", "set -e; set -o pipefail; source \"$1\"; source \"$2\"; \(command)",
      "-", libraryURL.path, binaryLibraryURL.path,
    ]
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

  @Test("Distribution removes debug paths while preserving matching private dSYMs")
  func strippingPreservesDebugSymbols() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try Data("int main(void) { return 0; }\n".utf8)
      .write(to: directory.appending(path: "fixture.c"))
    #expect(try runShell("""
      cd '\(directory.path)'
      xcrun clang -g -c fixture.c -o fixture.o
      xcrun clang fixture.o -o fixture
      if vimotes_verify_binary_paths fixture '\(directory.path)' 2>/dev/null; then exit 1; fi
      vimotes_prepare_distribution_binary fixture fixture.dSYM '\(directory.path)'
      xcrun dwarfdump --debug-info fixture.dSYM | grep DW_TAG_compile_unit >/dev/null
      codesign --force --sign - fixture 2>/dev/null
      codesign --verify --strict fixture
      vimotes_verify_binary_paths fixture '\(directory.path)'
      vimotes_verify_debug_symbols fixture fixture.dSYM
      ./fixture
      echo verified
      """) == "verified")
  }

  @Test("Path checks inspect binary bytes and reject missing input")
  func pathChecksRejectEmbeddedLocalPaths() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let paths = [
      "/Users/example/project", "/home/example/project", "/private/tmp/build",
      "/private/var/folders/build", "/var/folders/build", "/tmp/build",
      "/Volumes/Build Disk/project/source.swift",
    ]
    for (index, path) in paths.enumerated() {
      let file = directory.appending(path: "fixture-\(index)")
      try (Data([0, 1, 2]) + Data(path.utf8) + Data([0])).write(to: file)
      #expect(try runShell("""
        if vimotes_verify_binary_paths '\(file.path)' '/Volumes/Build Disk/project' 2>/dev/null; then
          exit 1
        fi
        echo rejected
        """) == "rejected")
    }
    #expect(try runShell("""
      if vimotes_verify_binary_paths '\(directory.path)/missing' /build 2>/dev/null; then exit 1; fi
      echo rejected
      """) == "rejected")
  }

  @Test("Stripping cannot hide a local path embedded in application data")
  func preparationRejectsRemainingPaths() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try Data("const char *path = \"/Users/example/project\"; int main(void) { return path[0]; }\n".utf8)
      .write(to: directory.appending(path: "fixture.c"))
    #expect(try runShell("""
      cd '\(directory.path)'
      xcrun clang -g -c fixture.c -o fixture.o
      xcrun clang fixture.o -o fixture
      if vimotes_prepare_distribution_binary fixture fixture.dSYM '\(directory.path)' 2>/dev/null; then
        exit 1
      fi
      echo rejected
      """) == "rejected")
  }

  @Test("Debug symbols from another executable are rejected")
  func debugSymbolsMustMatchTheExecutable() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    try Data("int main(void) { return 0; }\n".utf8)
      .write(to: directory.appending(path: "first.c"))
    try Data("int main(void) { return 1; }\n".utf8)
      .write(to: directory.appending(path: "second.c"))
    #expect(try runShell("""
      cd '\(directory.path)'
      xcrun clang -g -c first.c -o first.o
      xcrun clang first.o -o first
      xcrun clang -g -c second.c -o second.o
      xcrun clang second.o -o second
      xcrun dsymutil first -o first.dSYM
      if vimotes_verify_debug_symbols second first.dSYM 2>/dev/null; then exit 1; fi
      echo rejected
      """) == "rejected")
  }
}

private enum ShellTestError: Error {
  case failed(String)
}
