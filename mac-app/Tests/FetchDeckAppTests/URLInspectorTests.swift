import Darwin
import Foundation
import XCTest

@testable import FetchDeckApp

final class URLInspectorTests: XCTestCase {
  func testInspectionDrainsLargeOutputAndErrorsConcurrently() async throws {
    let script = """
      #!/bin/zsh
      for index in {1..7000}; do
        printf '          '
        printf 'warning warning warning\\n' >&2
      done
      printf '{"id":"large","title":"Large output","_type":"video"}\\n'
      """

    let preview = try await withBackendScript(script) {
      try await URLInspector.inspect(
        "https://example.com/large-output",
        timeout: 5
      )
    }

    XCTAssertEqual(preview.sourceID, "large")
    XCTAssertEqual(preview.title, "Large output")
  }

  func testInspectionTimesOut() async throws {
    let script = """
      #!/bin/zsh
      exec /bin/sleep 5
      """

    do {
      _ = try await withBackendScript(script) {
        try await URLInspector.inspect(
          "https://example.com/timeout",
          timeout: 0.1
        )
      }
      XCTFail("Expected inspection to time out")
    } catch {
      XCTAssertTrue(error.localizedDescription.contains("timed out"))
    }
  }

  func testInspectionHonorsCancellation() async throws {
    let script = """
      #!/bin/zsh
      exec /bin/sleep 5
      """

    try await withBackendScript(script) {
      let inspection = Task {
        try await URLInspector.inspect(
          "https://example.com/cancel",
          timeout: 10
        )
      }
      try await Task.sleep(nanoseconds: 100_000_000)
      inspection.cancel()

      do {
        _ = try await inspection.value
        XCTFail("Expected inspection to be cancelled")
      } catch is CancellationError {
        // Expected.
      } catch {
        XCTFail("Expected CancellationError, received \(error)")
      }
    }
  }

  private func withBackendScript<Result>(
    _ contents: String,
    operation: () async throws -> Result
  ) async throws -> Result {
    let fileManager = FileManager.default
    let directory = fileManager.temporaryDirectory.appendingPathComponent(
      "FetchDeckTests-\(UUID().uuidString)",
      isDirectory: true
    )
    let scriptURL = directory.appendingPathComponent("fake-yt-dlp")
    let previousOverride: String?
    if let value = getenv("YT_DLP_BINARY") {
      previousOverride = String(cString: value)
    } else {
      previousOverride = nil
    }

    try fileManager.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    try Data(contents.utf8).write(to: scriptURL)
    try fileManager.setAttributes(
      [.posixPermissions: 0o755],
      ofItemAtPath: scriptURL.path
    )
    setenv("YT_DLP_BINARY", scriptURL.path, 1)

    defer {
      if let previousOverride {
        setenv("YT_DLP_BINARY", previousOverride, 1)
      } else {
        unsetenv("YT_DLP_BINARY")
      }
      try? fileManager.removeItem(at: directory)
    }

    return try await operation()
  }
}
