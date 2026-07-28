import AppKit
import Foundation

@MainActor
final class AppSettings: ObservableObject {
  @Published var mode: DownloadMode {
    didSet { save(mode.rawValue, key: "defaultMode") }
  }
  @Published var quality: DownloadQuality {
    didSet { save(quality.rawValue, key: "quality") }
  }
  @Published var audioFormat: AudioFormat {
    didSet { save(audioFormat.rawValue, key: "audioFormat") }
  }
  @Published var outputPath: String {
    didSet { save(outputPath, key: "outputPath") }
  }
  @Published var embedMetadata: Bool {
    didSet { save(embedMetadata, key: "embedMetadata") }
  }
  @Published var embedThumbnail: Bool {
    didSet { save(embedThumbnail, key: "embedThumbnail") }
  }
  @Published var embedSubtitles: Bool {
    didSet { save(embedSubtitles, key: "embedSubtitles") }
  }
  @Published var removeSponsors: Bool {
    didSet { save(removeSponsors, key: "removeSponsors") }
  }
  @Published var accessSource: YouTubeAccessSource {
    didSet { save(accessSource.rawValue, key: "youtubeAccessSource") }
  }
  @Published var cookiesFilePath: String {
    didSet { save(cookiesFilePath, key: "cookiesFilePath") }
  }
  @Published var concurrentFragments: Int {
    didSet { save(concurrentFragments, key: "concurrentFragments") }
  }
  @Published var retries: Int {
    didSet { save(retries, key: "retries") }
  }
  @Published var rateLimit: DownloadRateLimit {
    didSet { save(rateLimit.rawValue, key: "rateLimit") }
  }

  private let defaults = UserDefaults.standard

  init() {
    mode =
      DownloadMode(
        rawValue: defaults.string(forKey: "defaultMode") ?? ""
      ) ?? .video
    quality =
      DownloadQuality(
        rawValue: defaults.string(forKey: "quality") ?? ""
      ) ?? .best
    audioFormat =
      AudioFormat(
        rawValue: defaults.string(forKey: "audioFormat") ?? ""
      ) ?? .original
    outputPath = defaults.string(forKey: "outputPath") ?? Self.defaultOutputPath
    embedMetadata = defaults.object(forKey: "embedMetadata") as? Bool ?? true
    embedThumbnail = defaults.object(forKey: "embedThumbnail") as? Bool ?? true
    embedSubtitles = defaults.object(forKey: "embedSubtitles") as? Bool ?? false
    removeSponsors = defaults.object(forKey: "removeSponsors") as? Bool ?? false
    accessSource =
      YouTubeAccessSource(
        rawValue: defaults.string(forKey: "youtubeAccessSource") ?? ""
      ) ?? Self.recommendedAccessSource
    cookiesFilePath = defaults.string(forKey: "cookiesFilePath") ?? ""
    let savedFragments = defaults.integer(forKey: "concurrentFragments")
    concurrentFragments = savedFragments > 0 ? min(savedFragments, 16) : 4
    let savedRetries = defaults.integer(forKey: "retries")
    retries = savedRetries > 0 ? min(savedRetries, 30) : 10
    rateLimit =
      DownloadRateLimit(rawValue: defaults.string(forKey: "rateLimit") ?? "")
      ?? .unlimited
  }

  var authentication: AuthenticationOptions? {
    guard accessSource != .publicOnly else { return nil }
    if accessSource == .cookiesFile, cookiesFilePath.isEmpty {
      return nil
    }
    return AuthenticationOptions(
      source: accessSource,
      cookiesFilePath: cookiesFilePath.isEmpty ? nil : cookiesFilePath
    )
  }

  var options: DownloadOptions {
    DownloadOptions(
      mode: mode,
      quality: quality,
      audioFormat: audioFormat,
      embedMetadata: embedMetadata,
      embedThumbnail: embedThumbnail,
      embedSubtitles: embedSubtitles,
      removeSponsors: removeSponsors,
      authentication: authentication,
      transfer: TransferOptions(
        concurrentFragments: concurrentFragments,
        retries: retries,
        rateLimit: rateLimit
      )
    )
  }

  func chooseOutputDirectory() {
    let panel = NSOpenPanel()
    panel.title = "Choose Download Folder"
    panel.prompt = "Choose"
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.canCreateDirectories = true
    panel.allowsMultipleSelection = false
    panel.directoryURL = URL(fileURLWithPath: outputPath)
    if panel.runModal() == .OK, let url = panel.url {
      outputPath = url.path
    }
  }

  func chooseCookiesFile() {
    let panel = NSOpenPanel()
    panel.title = "Choose Browser cookies.txt"
    panel.message = "Choose a Netscape-format cookies file exported from your signed-in browser."
    panel.prompt = "Use Cookies"
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.allowsMultipleSelection = false
    if !cookiesFilePath.isEmpty {
      panel.directoryURL = URL(fileURLWithPath: cookiesFilePath).deletingLastPathComponent()
    }
    if panel.runModal() == .OK, let url = panel.url {
      cookiesFilePath = url.path
      accessSource = .cookiesFile
    }
  }

  func openFullDiskAccessSettings() {
    guard
      let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
      )
    else { return }
    NSWorkspace.shared.open(url)
  }

  func reset() {
    mode = .video
    quality = .best
    audioFormat = .original
    embedMetadata = true
    embedThumbnail = true
    embedSubtitles = false
    removeSponsors = false
    concurrentFragments = 4
    retries = 10
    rateLimit = .unlimited
  }

  private func save(_ value: Any, key: String) {
    defaults.set(value, forKey: key)
  }

  private static var defaultOutputPath: String {
    if let configured = Bundle.main.object(
      forInfoDictionaryKey: "YTDefaultDownloadsPath"
    ) as? String,
      !configured.isEmpty,
      configured != "__DEFAULT_DOWNLOADS__"
    {
      return configured
    }
    let movies =
      FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
      ?? FileManager.default.homeDirectoryForCurrentUser
    return movies.appendingPathComponent("FetchDeck Downloads").path
  }

  private static var recommendedAccessSource: YouTubeAccessSource {
    guard
      let webURL = URL(string: "https://www.youtube.com"),
      let applicationURL = NSWorkspace.shared.urlForApplication(toOpen: webURL),
      let bundleID = Bundle(url: applicationURL)?.bundleIdentifier
    else { return .publicOnly }

    switch bundleID {
    case "com.apple.Safari": return .safari
    case "com.google.Chrome": return .chrome
    case "com.brave.Browser": return .brave
    case "org.mozilla.firefox": return .firefox
    case "com.microsoft.edgemac": return .edge
    case "org.chromium.Chromium": return .chromium
    case "com.vivaldi.Vivaldi": return .vivaldi
    default: return .publicOnly
    }
  }
}
