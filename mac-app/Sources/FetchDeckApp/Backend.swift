import Foundation

enum BackendLocator {
  static var ytDLP: URL? {
    if let resourceURL = Bundle.main.resourceURL {
      let bundled = resourceURL.appendingPathComponent("yt-dlp_macos")
      if FileManager.default.isExecutableFile(atPath: bundled.path) {
        return bundled
      }
    }
    if let override = ProcessInfo.processInfo.environment["YT_DLP_BINARY"] {
      let url = URL(fileURLWithPath: override)
      if FileManager.default.isExecutableFile(atPath: url.path) {
        return url
      }
    }
    return nil
  }

  static var ffmpegDirectory: String? {
    if let resourceURL = Bundle.main.resourceURL {
      let bundled = resourceURL.appendingPathComponent("ffmpeg")
      if FileManager.default.isExecutableFile(atPath: bundled.path) {
        return resourceURL.path
      }
    }
    return executablePath([
      "/opt/homebrew/bin/ffmpeg",
      "/usr/local/bin/ffmpeg",
      "/usr/bin/ffmpeg",
    ]).map { URL(fileURLWithPath: $0).deletingLastPathComponent().path }
  }

  static var nodePath: String? {
    if let resourceURL = Bundle.main.resourceURL {
      let bundled = resourceURL.appendingPathComponent("node")
      if FileManager.default.isExecutableFile(atPath: bundled.path) {
        return bundled.path
      }
    }
    return executablePath([
      "/opt/homebrew/bin/node",
      "/usr/local/bin/node",
      "/usr/bin/node",
    ])
  }

  private static func executablePath(_ candidates: [String]) -> String? {
    candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
  }
}

enum DownloaderCommandBuilder {
  static func arguments(
    url: String,
    options: DownloadOptions,
    outputDirectory: URL,
    ffmpegDirectory: String?,
    nodePath: String?
  ) -> [String] {
    let archiveName =
      options.mode == .video
      ? ".download-archive.txt" : ".download-archive-audio.txt"
    let archivePath = outputDirectory.appendingPathComponent(archiveName).path
    let outputTemplate =
      "%(playlist_title|Single videos)s/"
      + "%(playlist_index)03d - %(title).180B [%(id)s].%(ext)s"

    var arguments = [
      "--ignore-config",
      "--yes-playlist",
      "--paths", outputDirectory.path,
      "--output", outputTemplate,
      "--download-archive", archivePath,
      "--continue",
      "--no-overwrites",
      "--newline",
      "--progress-delta", "0.5",
      "--print", "after_move:__YTDLP_FILE__:%(filepath)s",
      "--no-quiet",
      "--progress",
    ]

    let transfer = options.transfer ?? .standard
    arguments += [
      "--concurrent-fragments", String(transfer.concurrentFragments),
      "--retries", String(transfer.retries),
      "--fragment-retries", String(transfer.retries),
      "--file-access-retries", String(transfer.retries),
      "--retry-sleep", "http:linear=1::2",
      "--retry-sleep", "fragment:linear=1::2",
    ]
    if let rateLimit = transfer.rateLimit.ytDLPValue {
      arguments += ["--limit-rate", rateLimit]
    }

    if let authentication = options.authentication {
      arguments += authentication.arguments
    }

    if options.mode == .video {
      arguments += [
        "--format", options.quality.selector,
        "--merge-output-format", "mkv",
      ]
    } else {
      arguments += ["--format", "ba/b"]
      if options.audioFormat != .original {
        arguments += [
          "--extract-audio",
          "--audio-format", options.audioFormat.rawValue,
          "--audio-quality", "0",
        ]
      }
    }

    if options.embedMetadata {
      arguments.append("--embed-metadata")
    }
    if options.embedThumbnail {
      arguments.append("--embed-thumbnail")
    }
    if options.embedSubtitles, options.mode == .video {
      arguments += [
        "--write-subs",
        "--write-auto-subs",
        "--sub-langs", "en.*,en",
        "--embed-subs",
      ]
    }
    if options.removeSponsors {
      arguments += [
        "--sponsorblock-remove",
        "sponsor,selfpromo,interaction,intro,outro",
      ]
    }
    if let ffmpegDirectory {
      arguments += ["--ffmpeg-location", ffmpegDirectory]
    }
    if let nodePath {
      arguments += ["--js-runtimes", "node:\(nodePath)"]
    }
    arguments.append(url)
    return arguments
  }
}

enum PreviewError: LocalizedError {
  case missingBackend
  case invalidResponse(String)
  case inspectionFailed(String)
  case authenticationRequired(String)

  var errorDescription: String? {
    switch self {
    case .missingBackend:
      "The packaged yt-dlp engine is missing."
    case .invalidResponse(let message):
      "The site returned an unreadable response. \(message)"
    case .inspectionFailed(let message):
      message.isEmpty ? "Could not analyze this URL." : message
    case .authenticationRequired(let message):
      "This media needs a signed-in browser session. Choose the browser where you can play it, then try again.\n\n\(message)"
    }
  }

  var requiresAuthentication: Bool {
    if case .authenticationRequired = self { return true }
    return false
  }
}

enum URLInspector {
  static func inspect(
    _ url: String,
    authentication: AuthenticationOptions? = nil
  ) async throws -> MediaPreview {
    guard let backend = BackendLocator.ytDLP else {
      throw PreviewError.missingBackend
    }

    return try await withCheckedThrowingContinuation { continuation in
      let process = Process()
      let output = Pipe()
      let errors = Pipe()
      process.executableURL = backend
      process.arguments = arguments(
        url: url,
        authentication: authentication,
        nodePath: BackendLocator.nodePath
      )
      process.standardOutput = output
      process.standardError = errors
      process.environment = processEnvironment()

      process.terminationHandler = { finished in
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        let errorText = String(decoding: errorData, as: UTF8.self)

        guard finished.terminationStatus == 0 else {
          let message = cleanError(errorText)
          let error: PreviewError =
            requiresAuthentication(message)
            ? .authenticationRequired(message)
            : .inspectionFailed(message)
          continuation.resume(throwing: error)
          return
        }
        do {
          continuation.resume(returning: try parse(data))
        } catch {
          continuation.resume(throwing: error)
        }
      }

      do {
        try process.run()
      } catch {
        continuation.resume(throwing: error)
      }
    }
  }

  static func arguments(
    url: String,
    authentication: AuthenticationOptions?,
    nodePath: String?
  ) -> [String] {
    var arguments = [
      "--ignore-config",
      "--flat-playlist",
      "--playlist-items", "1",
      "--dump-single-json",
    ]
    if let authentication {
      arguments += authentication.arguments
    }
    if let nodePath {
      arguments += ["--js-runtimes", "node:\(nodePath)"]
    }
    arguments.append(url)
    return arguments
  }

  static func parse(_ data: Data) throws -> MediaPreview {
    guard
      let object = try JSONSerialization.jsonObject(with: data)
        as? [String: Any],
      let title = object["title"] as? String
    else {
      throw PreviewError.invalidResponse("Missing title.")
    }

    let entries = object["entries"] as? [[String: Any]]
    let firstEntry = entries?.first
    let isPlaylist = (object["_type"] as? String) == "playlist"
    let thumbnails =
      (object["thumbnails"] as? [[String: Any]])
      ?? (firstEntry?["thumbnails"] as? [[String: Any]])
    let thumbnail = thumbnails?.last?["url"] as? String

    return MediaPreview(
      sourceID: object["id"] as? String ?? firstEntry?["id"] as? String ?? title,
      title: title,
      channel: object["channel"] as? String ?? firstEntry?["channel"] as? String,
      thumbnailURL: thumbnail,
      duration: object["duration"] as? Double ?? firstEntry?["duration"] as? Double,
      itemCount: object["playlist_count"] as? Int ?? 1,
      isPlaylist: isPlaylist,
      siteName: siteName(from: object)
    )
  }

  private static func siteName(from object: [String: Any]) -> String? {
    if let extractor = object["extractor_key"] as? String, !extractor.isEmpty {
      return
        extractor
        .replacingOccurrences(
          of: #"([a-z])([A-Z])"#,
          with: "$1 $2",
          options: .regularExpression
        )
    }
    if let domain = object["webpage_url_domain"] as? String {
      return domain
    }
    return nil
  }

  private static func processEnvironment() -> [String: String] {
    var environment = ProcessInfo.processInfo.environment
    environment["PATH"] = [
      "/opt/homebrew/bin",
      "/usr/local/bin",
      environment["PATH"] ?? "/usr/bin:/bin",
    ].joined(separator: ":")
    return environment
  }

  private static func cleanError(_ text: String) -> String {
    text
      .components(separatedBy: .newlines)
      .last(where: { $0.contains("ERROR:") })?
      .replacingOccurrences(of: "ERROR: ", with: "")
      ?? text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func requiresAuthentication(_ text: String) -> Bool {
    let message = text.lowercased()
    return [
      "members-only",
      "members only",
      "join this channel",
      "sign in",
      "login required",
      "confirm your age",
      "not a bot",
    ].contains { message.contains($0) }
  }
}
