import XCTest

@testable import FetchDeckApp

final class ProgressParserTests: XCTestCase {
  func testPlaylistItemLineDoesNotProduceFileSize() {
    let update = ProgressParser.parse(
      "[download] Downloading item 3 of 12"
    )

    XCTAssertEqual(update.itemIndex, 3)
    XCTAssertEqual(update.itemCount, 12)
    XCTAssertNil(update.size)
  }

  func testProgressLineParsesTransferDetails() {
    let update = ProgressParser.parse(
      "[download]  45.2% of ~  12.34MiB at    3.21MiB/s ETA 00:03"
    )

    XCTAssertEqual(update.filePercent, 45.2)
    XCTAssertEqual(update.size, "12.34MiB")
    XCTAssertEqual(update.speed, "3.21MiB/s")
    XCTAssertEqual(update.eta, "00:03")
  }

  func testCompletedLineParsesSizeWithoutSpeedOrETA() {
    let update = ProgressParser.parse(
      "[download] 100% of 5.00MiB in 00:02"
    )

    XCTAssertEqual(update.filePercent, 100)
    XCTAssertEqual(update.size, "5.00MiB")
    XCTAssertNil(update.speed)
    XCTAssertNil(update.eta)
  }

  func testErrorLineCapturesUsefulMessage() {
    let update = ProgressParser.parse("ERROR: Video unavailable")

    XCTAssertEqual(update.error, "Video unavailable")
  }

  func testPostProcessingPhases() {
    XCTAssertEqual(
      ProgressParser.parse("[Merger] Merging formats").phase,
      .merging
    )
    XCTAssertEqual(
      ProgressParser.parse("[ExtractAudio] Destination: audio.mp3").phase,
      .extractingAudio
    )
    XCTAssertEqual(
      ProgressParser.parse("[Metadata] Adding metadata").phase,
      .addingMetadata
    )
    XCTAssertEqual(
      ProgressParser.parse("[EmbedThumbnail] Adding thumbnail").phase,
      .embeddingThumbnail
    )
    XCTAssertEqual(
      ProgressParser.parse(
        "[download] abc has already been recorded in the archive"
      ).phase,
      .skippingArchived
    )
    XCTAssertEqual(
      ProgressParser.parse("__YTDLP_FILE__:/tmp/video.mkv").phase,
      .saved
    )
  }
}
