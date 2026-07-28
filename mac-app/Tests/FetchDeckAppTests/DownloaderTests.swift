import Foundation
import XCTest

@testable import FetchDeckApp

final class DownloaderTests: XCTestCase {
  private var videoOptions: DownloadOptions {
    DownloadOptions(
      mode: .video,
      quality: .fourK,
      audioFormat: .original,
      embedMetadata: true,
      embedThumbnail: true,
      embedSubtitles: true,
      removeSponsors: true
    )
  }

  func testBestQualityHasNoResolutionCap() {
    XCTAssertEqual(DownloadQuality.best.selector, "bv*+ba/b")
  }

  func testVideoCommandIncludesQualityArchiveAndFinishingOptions() {
    let arguments = DownloaderCommandBuilder.arguments(
      url: "https://www.youtube.com/playlist?list=test",
      options: videoOptions,
      outputDirectory: URL(fileURLWithPath: "/tmp/YT Downloads"),
      ffmpegDirectory: "/opt/homebrew/bin",
      nodePath: "/opt/homebrew/bin/node"
    )

    XCTAssertTrue(arguments.contains("bv*[height<=2160]+ba/b[height<=2160]"))
    XCTAssertTrue(arguments.contains("/tmp/YT Downloads/.download-archive.txt"))
    XCTAssertTrue(arguments.contains("--embed-subs"))
    XCTAssertTrue(arguments.contains("--embed-thumbnail"))
    XCTAssertTrue(arguments.contains("--sponsorblock-remove"))
    XCTAssertTrue(arguments.contains("--no-quiet"))
    XCTAssertTrue(arguments.contains("--progress"))
    XCTAssertEqual(
      arguments[arguments.firstIndex(of: "--concurrent-fragments")! + 1],
      "4"
    )
    XCTAssertEqual(arguments[arguments.firstIndex(of: "--retries")! + 1], "10")
    XCTAssertEqual(arguments.last, "https://www.youtube.com/playlist?list=test")
  }

  func testAudioCommandUsesSeparateArchiveAndExtractionFormat() {
    var options = videoOptions
    options.mode = .audio
    options.audioFormat = .mp3
    let arguments = DownloaderCommandBuilder.arguments(
      url: "https://youtu.be/test",
      options: options,
      outputDirectory: URL(fileURLWithPath: "/tmp/output"),
      ffmpegDirectory: nil,
      nodePath: nil
    )

    XCTAssertTrue(arguments.contains("/tmp/output/.download-archive-audio.txt"))
    XCTAssertTrue(arguments.contains("--extract-audio"))
    XCTAssertEqual(arguments[arguments.firstIndex(of: "--audio-format")! + 1], "mp3")
    XCTAssertFalse(arguments.contains("--embed-subs"))
  }

  func testBrowserSessionIsUsedForAnalysisAndDownload() {
    let authentication = AuthenticationOptions(
      source: .chrome,
      cookiesFilePath: nil
    )
    var options = videoOptions
    options.authentication = authentication

    let downloadArguments = DownloaderCommandBuilder.arguments(
      url: "https://youtu.be/member-video",
      options: options,
      outputDirectory: URL(fileURLWithPath: "/tmp/output"),
      ffmpegDirectory: "/opt/homebrew/bin",
      nodePath: "/opt/homebrew/bin/node"
    )
    let previewArguments = URLInspector.arguments(
      url: "https://youtu.be/member-video",
      authentication: authentication,
      nodePath: "/opt/homebrew/bin/node"
    )

    XCTAssertEqual(
      downloadArguments[downloadArguments.firstIndex(of: "--cookies-from-browser")! + 1],
      "chrome"
    )
    XCTAssertEqual(
      previewArguments[previewArguments.firstIndex(of: "--cookies-from-browser")! + 1],
      "chrome"
    )
  }

  func testCookiesFilePathIsPassedWithoutCookieContents() {
    let authentication = AuthenticationOptions(
      source: .cookiesFile,
      cookiesFilePath: "/tmp/private cookies.txt"
    )

    XCTAssertEqual(
      authentication.arguments,
      ["--cookies", "/tmp/private cookies.txt"]
    )
  }

  func testCustomTransferLimitsArePassedToBackend() {
    var options = videoOptions
    options.transfer = TransferOptions(
      concurrentFragments: 8,
      retries: 20,
      rateLimit: .five
    )
    let arguments = DownloaderCommandBuilder.arguments(
      url: "https://vimeo.com/test",
      options: options,
      outputDirectory: URL(fileURLWithPath: "/tmp/output"),
      ffmpegDirectory: "/opt/homebrew/bin",
      nodePath: nil
    )

    XCTAssertEqual(
      arguments[arguments.firstIndex(of: "--concurrent-fragments")! + 1],
      "8"
    )
    XCTAssertEqual(arguments[arguments.firstIndex(of: "--retries")! + 1], "20")
    XCTAssertEqual(arguments[arguments.firstIndex(of: "--limit-rate")! + 1], "5M")
  }

  func testConcurrencyPolicyRespectsLimitAndQueuePause() {
    XCTAssertEqual(
      DownloadConcurrencyPolicy.availableSlots(
        activeCount: 2,
        maximum: 5,
        queuePaused: false
      ),
      3
    )
    XCTAssertEqual(
      DownloadConcurrencyPolicy.availableSlots(
        activeCount: 2,
        maximum: 5,
        queuePaused: true
      ),
      0
    )
    XCTAssertEqual(
      DownloadConcurrencyPolicy.availableSlots(
        activeCount: 5,
        maximum: 2,
        queuePaused: false
      ),
      0
    )
  }

  func testOldDownloadOptionsDecodeWithoutAuthentication() throws {
    let data = Data(
      """
      {
        "mode": "video",
        "quality": "best",
        "audioFormat": "original",
        "embedMetadata": true,
        "embedThumbnail": true,
        "embedSubtitles": false,
        "removeSponsors": false
      }
      """.utf8
    )

    let options = try JSONDecoder().decode(DownloadOptions.self, from: data)
    XCTAssertNil(options.authentication)
    XCTAssertNil(options.transfer)
  }

  func testPlaylistPreviewParsing() throws {
    let data = Data(
      """
      {
        "id": "playlist-id",
        "title": "Creative Playlist",
        "channel": "Studio",
        "playlist_count": 12,
        "_type": "playlist",
        "extractor_key": "VimeoChannel",
        "thumbnails": [{"url": "https://example.com/thumb.jpg"}],
        "entries": [{"duration": 125.0}]
      }
      """.utf8
    )
    let preview = try URLInspector.parse(data)

    XCTAssertEqual(preview.title, "Creative Playlist")
    XCTAssertEqual(preview.itemCount, 12)
    XCTAssertTrue(preview.isPlaylist)
    XCTAssertEqual(preview.thumbnailURL, "https://example.com/thumb.jpg")
    XCTAssertEqual(preview.siteName, "Vimeo Channel")
  }

  func testDownloadJobCapturesRecipe() {
    let job = DownloadJob(
      sourceURL: "https://youtu.be/test",
      preview: .fallback(for: "https://youtu.be/test"),
      options: videoOptions,
      outputPath: "/tmp/output"
    )

    XCTAssertEqual(job.state, .queued)
    XCTAssertEqual(job.formatSummary, "4k video · MKV")
  }
}
