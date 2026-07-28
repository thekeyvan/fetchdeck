import Foundation

enum DownloadQuality: String, CaseIterable, Codable, Identifiable {
  case best
  case fourK = "4k"
  case fourteenForty = "1440p"
  case tenEighty = "1080p"
  case sevenTwenty = "720p"
  case fourEighty = "480p"

  var id: String { rawValue }

  var title: String {
    switch self {
    case .best: "Best available"
    case .fourK: "4K · 2160p"
    case .fourteenForty: "2K · 1440p"
    case .tenEighty: "Full HD · 1080p"
    case .sevenTwenty: "HD · 720p"
    case .fourEighty: "SD · 480p"
    }
  }

  var shortTitle: String {
    self == .best ? "Best" : rawValue
  }

  var selector: String {
    switch self {
    case .best: "bv*+ba/b"
    case .fourK: "bv*[height<=2160]+ba/b[height<=2160]"
    case .fourteenForty: "bv*[height<=1440]+ba/b[height<=1440]"
    case .tenEighty: "bv*[height<=1080]+ba/b[height<=1080]"
    case .sevenTwenty: "bv*[height<=720]+ba/b[height<=720]"
    case .fourEighty: "bv*[height<=480]+ba/b[height<=480]"
    }
  }
}

enum DownloadMode: String, CaseIterable, Codable, Identifiable {
  case video
  case audio

  var id: String { rawValue }
  var title: String { self == .video ? "Video" : "Audio only" }
  var symbol: String { self == .video ? "play.rectangle.fill" : "waveform" }
}

enum AudioFormat: String, CaseIterable, Codable, Identifiable {
  case original
  case mp3
  case m4a
  case flac

  var id: String { rawValue }
  var title: String {
    switch self {
    case .original: "Original · best quality"
    case .mp3: "MP3 · universal"
    case .m4a: "M4A · Apple friendly"
    case .flac: "FLAC · editing friendly"
    }
  }
}

enum DownloadRateLimit: String, CaseIterable, Codable, Identifiable {
  case unlimited
  case one = "1M"
  case two = "2M"
  case five = "5M"
  case ten = "10M"
  case twentyFive = "25M"
  case fifty = "50M"

  var id: String { rawValue }
  var title: String {
    self == .unlimited ? "Unlimited" : "\(rawValue.dropLast()) MB/s"
  }
  var ytDLPValue: String? {
    self == .unlimited ? nil : rawValue
  }
}

struct TransferOptions: Codable, Equatable {
  var concurrentFragments: Int
  var retries: Int
  var rateLimit: DownloadRateLimit

  static let standard = TransferOptions(
    concurrentFragments: 4,
    retries: 10,
    rateLimit: .unlimited
  )
}

enum YouTubeAccessSource: String, CaseIterable, Codable, Identifiable {
  case publicOnly
  case safari
  case chrome
  case brave
  case firefox
  case edge
  case chromium
  case vivaldi
  case cookiesFile

  var id: String { rawValue }

  var title: String {
    switch self {
    case .publicOnly: "Public videos only"
    case .safari: "Safari"
    case .chrome: "Google Chrome"
    case .brave: "Brave"
    case .firefox: "Firefox"
    case .edge: "Microsoft Edge"
    case .chromium: "Chromium"
    case .vivaldi: "Vivaldi"
    case .cookiesFile: "cookies.txt file"
    }
  }

  var shortTitle: String {
    switch self {
    case .publicOnly: "Public access"
    case .cookiesFile: "Cookie file"
    default: title
    }
  }

  var symbol: String {
    switch self {
    case .publicOnly: "globe"
    case .safari: "safari.fill"
    case .cookiesFile: "doc.badge.key.fill"
    default: "person.crop.circle.badge.checkmark"
    }
  }

  var browserValue: String? {
    switch self {
    case .safari: "safari"
    case .chrome: "chrome"
    case .brave: "brave"
    case .firefox: "firefox"
    case .edge: "edge"
    case .chromium: "chromium"
    case .vivaldi: "vivaldi"
    case .publicOnly, .cookiesFile: nil
    }
  }
}

struct AuthenticationOptions: Codable, Equatable {
  var source: YouTubeAccessSource
  var cookiesFilePath: String?

  var arguments: [String] {
    if let browserValue = source.browserValue {
      return ["--cookies-from-browser", browserValue]
    }
    if source == .cookiesFile, let cookiesFilePath, !cookiesFilePath.isEmpty {
      return ["--cookies", (cookiesFilePath as NSString).expandingTildeInPath]
    }
    return []
  }

  var summary: String {
    source == .cookiesFile
      ? URL(fileURLWithPath: cookiesFilePath ?? "").lastPathComponent
      : source.title
  }
}

struct DownloadOptions: Codable, Equatable {
  var mode: DownloadMode
  var quality: DownloadQuality
  var audioFormat: AudioFormat
  var embedMetadata: Bool
  var embedThumbnail: Bool
  var embedSubtitles: Bool
  var removeSponsors: Bool
  var authentication: AuthenticationOptions? = nil
  var transfer: TransferOptions? = nil
}

struct MediaPreview: Codable, Equatable {
  var sourceID: String
  var title: String
  var channel: String?
  var thumbnailURL: String?
  var duration: Double?
  var itemCount: Int
  var isPlaylist: Bool
  var siteName: String? = nil

  var detailText: String {
    var pieces: [String] = []
    if let siteName, !siteName.isEmpty {
      pieces.append(siteName)
    }
    if let channel, !channel.isEmpty {
      pieces.append(channel)
    }
    pieces.append(isPlaylist ? "\(itemCount) videos" : durationText)
    return pieces.joined(separator: "  ·  ")
  }

  var durationText: String {
    guard let duration else { return "Video" }
    let total = Int(duration.rounded())
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let seconds = total % 60
    return hours > 0
      ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
      : String(format: "%d:%02d", minutes, seconds)
  }

  static func fallback(for url: String) -> MediaPreview {
    MediaPreview(
      sourceID: url,
      title: "Media download",
      channel: nil,
      thumbnailURL: nil,
      duration: nil,
      itemCount: 1,
      isPlaylist: false,
      siteName: URL(string: url)?.host
    )
  }
}

enum DownloadState: String, Codable {
  case queued
  case downloading
  case processing
  case completed
  case failed
  case cancelled

  var title: String {
    switch self {
    case .queued: "Queued"
    case .downloading: "Downloading"
    case .processing: "Finishing"
    case .completed: "Complete"
    case .failed: "Failed"
    case .cancelled: "Cancelled"
    }
  }

  var symbol: String {
    switch self {
    case .queued: "clock.fill"
    case .downloading: "arrow.down.circle.fill"
    case .processing: "wand.and.stars"
    case .completed: "checkmark.circle.fill"
    case .failed: "exclamationmark.triangle.fill"
    case .cancelled: "xmark.circle.fill"
    }
  }

  var isPending: Bool {
    self == .queued || self == .downloading || self == .processing
  }
}

struct DownloadJob: Codable, Identifiable, Equatable {
  var id: UUID
  var sourceURL: String
  var preview: MediaPreview
  var options: DownloadOptions
  var outputPath: String
  var state: DownloadState
  var progress: Double
  var statusText: String
  var log: String
  var createdAt: Date
  var completedAt: Date?
  var speedText: String? = nil
  var etaText: String? = nil
  var sizeText: String? = nil

  init(
    sourceURL: String,
    preview: MediaPreview,
    options: DownloadOptions,
    outputPath: String
  ) {
    id = UUID()
    self.sourceURL = sourceURL
    self.preview = preview
    self.options = options
    self.outputPath = outputPath
    state = .queued
    progress = 0
    statusText = "Waiting in queue"
    log = ""
    createdAt = Date()
  }

  var formatSummary: String {
    options.mode == .video
      ? "\(options.quality.shortTitle) video · MKV"
      : "\(options.audioFormat.rawValue.uppercased()) audio"
  }
}

enum SidebarDestination: String, CaseIterable, Identifiable {
  case home
  case downloads
  case library
  case settings

  var id: String { rawValue }
  var title: String {
    switch self {
    case .home: "New Download"
    case .downloads: "Downloads"
    case .library: "History"
    case .settings: "Settings"
    }
  }
  var symbol: String {
    switch self {
    case .home: "sparkles.rectangle.stack.fill"
    case .downloads: "arrow.down.circle.fill"
    case .library: "clock.arrow.circlepath"
    case .settings: "slider.horizontal.3"
    }
  }
}
