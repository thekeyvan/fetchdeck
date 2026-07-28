import Foundation

enum ProgressPhase: Equatable {
  case merging
  case extractingAudio
  case addingMetadata
  case embeddingThumbnail
  case skippingArchived
  case saved
}

struct ProgressUpdate: Equatable {
  var itemIndex: Int?
  var itemCount: Int?
  var filePercent: Double?
  var speed: String?
  var eta: String?
  var size: String?
  var error: String?
  var phase: ProgressPhase?
}

enum ProgressParser {
  private static let itemExpression = expression(
    #"Downloading item (\d+) of (\d+)"#
  )
  private static let percentExpression = expression(
    #"\[download\]\s+(\d+(?:\.\d+)?)%"#
  )
  private static let speedExpression = expression(
    #"\bat\s+(\S+/s)"#
  )
  private static let etaExpression = expression(
    #"\bETA\s+(\S+)"#
  )
  private static let sizeExpression = expression(
    #"\bof\s+~?\s*(\d[\d.]*\s*[KMGT]?i?B)"#
  )
  private static let errorExpression = expression(
    #"ERROR:\s*(.+)$"#
  )

  static func parse(_ line: String) -> ProgressUpdate {
    var update = ProgressUpdate()

    if let values = captures(itemExpression, in: line), values.count == 2 {
      update.itemIndex = Int(values[0])
      update.itemCount = Int(values[1])
    }

    if line.hasPrefix("[download]") {
      if let percent = captures(percentExpression, in: line)?.first {
        update.filePercent = Double(percent)
      }
      update.speed = captures(speedExpression, in: line)?.first
      update.eta = captures(etaExpression, in: line)?.first
      update.size = captures(sizeExpression, in: line)?.first?
        .replacingOccurrences(of: " ", with: "")
    }

    update.error = captures(errorExpression, in: line)?.first?
      .trimmingCharacters(in: .whitespacesAndNewlines)

    if line.contains("[Merger]") {
      update.phase = .merging
    } else if line.contains("[ExtractAudio]") {
      update.phase = .extractingAudio
    } else if line.contains("[Metadata]") {
      update.phase = .addingMetadata
    } else if line.contains("[EmbedThumbnail]") {
      update.phase = .embeddingThumbnail
    } else if line.contains("has already been recorded in the archive") {
      update.phase = .skippingArchived
    } else if line.hasPrefix("__YTDLP_FILE__:") {
      update.phase = .saved
    }

    return update
  }

  private static func expression(_ pattern: String) -> NSRegularExpression {
    do {
      return try NSRegularExpression(pattern: pattern)
    } catch {
      preconditionFailure("Invalid progress parser expression: \(pattern)")
    }
  }

  private static func captures(
    _ expression: NSRegularExpression,
    in text: String
  ) -> [String]? {
    guard
      let match = expression.firstMatch(
        in: text,
        range: NSRange(text.startIndex..., in: text)
      )
    else { return nil }

    return (1..<match.numberOfRanges).compactMap {
      Range(match.range(at: $0), in: text).map { String(text[$0]) }
    }
  }
}
