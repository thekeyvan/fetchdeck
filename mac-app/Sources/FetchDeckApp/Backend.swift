import Darwin
import Foundation

enum BackendLocator {
  static var ytDLP: URL? {
    if let resourceURL = Bundle.main.resourceURL {
      let bundled = resourceURL.appendingPathComponent("yt-dlp_macos")
      if FileManager.default.isExecutableFile(atPath: bundled.path) {
        return bundled
      }
    }
    #if DEBUG
      if let override = ProcessInfo.processInfo.environment["YT_DLP_BINARY"] {
        let url = URL(fileURLWithPath: override)
        if FileManager.default.isExecutableFile(atPath: url.path) {
          return url
        }
      }
    #endif
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

  static func processEnvironment() -> [String: String] {
    var environment = ProcessInfo.processInfo.environment
    environment["PATH"] = [
      "/opt/homebrew/bin",
      "/usr/local/bin",
      environment["PATH"] ?? "/usr/bin:/bin",
    ].joined(separator: ":")
    return environment
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
    arguments += ["--", url]
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

private struct InspectionResult {
  let terminationStatus: Int32
  let output: Data
  let errors: Data
}

// Mutable capture state is confined to stateQueue.
private final class InspectionSession: @unchecked Sendable {
  private let process = Process()
  private let output = Pipe()
  private let errors = Pipe()
  private let stateQueue = DispatchQueue(
    label: "com.ksapps.fetchdeck.url-inspection"
  )

  private var outputData = Data()
  private var errorData = Data()
  private var outputReachedEOF = false
  private var errorsReachedEOF = false
  private var terminationStatus: Int32?
  private var continuation: CheckedContinuation<InspectionResult, Error>?
  private var timeoutWorkItem: DispatchWorkItem?
  private var cancellationRequested = false
  private var finished = false

  init(
    executableURL: URL,
    arguments: [String],
    environment: [String: String]
  ) {
    process.executableURL = executableURL
    process.arguments = arguments
    process.standardOutput = output
    process.standardError = errors
    process.environment = environment
  }

  func run(timeout: TimeInterval) async throws -> InspectionResult {
    try await withTaskCancellationHandler {
      try Task.checkCancellation()
      return try await withCheckedThrowingContinuation { continuation in
        stateQueue.async { [self] in
          start(continuation: continuation, timeout: timeout)
        }
      }
    } onCancel: {
      cancel()
    }
  }

  private func start(
    continuation: CheckedContinuation<InspectionResult, Error>,
    timeout: TimeInterval
  ) {
    guard !cancellationRequested else {
      continuation.resume(throwing: CancellationError())
      return
    }

    self.continuation = continuation
    installHandlers()

    do {
      try process.run()
    } catch {
      complete(with: .failure(error))
      return
    }

    let timeoutWorkItem = DispatchWorkItem { [weak self] in
      self?.timeOut()
    }
    self.timeoutWorkItem = timeoutWorkItem
    stateQueue.asyncAfter(
      deadline: .now() + timeout,
      execute: timeoutWorkItem
    )
  }

  private func installHandlers() {
    output.fileHandleForReading.readabilityHandler = { [weak self] handle in
      let data = handle.availableData
      if data.isEmpty {
        handle.readabilityHandler = nil
      }
      self?.stateQueue.async {
        self?.receiveOutput(data)
      }
    }
    errors.fileHandleForReading.readabilityHandler = { [weak self] handle in
      let data = handle.availableData
      if data.isEmpty {
        handle.readabilityHandler = nil
      }
      self?.stateQueue.async {
        self?.receiveErrors(data)
      }
    }
    process.terminationHandler = { [weak self] process in
      self?.stateQueue.async {
        self?.receiveTermination(process.terminationStatus)
      }
    }
  }

  private func receiveOutput(_ data: Data) {
    guard !finished else { return }
    if data.isEmpty {
      outputReachedEOF = true
    } else {
      outputData.append(data)
    }
    completeIfReady()
  }

  private func receiveErrors(_ data: Data) {
    guard !finished else { return }
    if data.isEmpty {
      errorsReachedEOF = true
    } else {
      errorData.append(data)
    }
    completeIfReady()
  }

  private func receiveTermination(_ status: Int32) {
    guard !finished else { return }
    terminationStatus = status
    completeIfReady()
  }

  private func completeIfReady() {
    guard outputReachedEOF,
      errorsReachedEOF,
      let terminationStatus
    else { return }
    complete(
      with: .success(
        InspectionResult(
          terminationStatus: terminationStatus,
          output: outputData,
          errors: errorData
        )
      )
    )
  }

  private func timeOut() {
    guard !finished else { return }
    stopProcess()
    complete(
      with: .failure(
        PreviewError.inspectionFailed(
          "Analysis timed out. Check your connection and try again."
        )
      )
    )
  }

  private func cancel() {
    stateQueue.async { [self] in
      cancellationRequested = true
      guard continuation != nil, !finished else { return }
      stopProcess()
      complete(with: .failure(CancellationError()))
    }
  }

  private func stopProcess() {
    output.fileHandleForReading.readabilityHandler = nil
    errors.fileHandleForReading.readabilityHandler = nil
    try? output.fileHandleForReading.close()
    try? errors.fileHandleForReading.close()

    guard process.isRunning else { return }
    let processID = process.processIdentifier
    process.terminate()
    stateQueue.asyncAfter(deadline: .now() + 1) { [self] in
      if process.isRunning {
        _ = Darwin.kill(processID, SIGKILL)
      }
    }
  }

  private func complete(
    with result: Result<InspectionResult, Error>
  ) {
    guard !finished, let continuation else { return }
    finished = true
    self.continuation = nil
    timeoutWorkItem?.cancel()
    timeoutWorkItem = nil
    output.fileHandleForReading.readabilityHandler = nil
    errors.fileHandleForReading.readabilityHandler = nil
    process.terminationHandler = nil
    continuation.resume(with: result)
  }
}

enum URLInspector {
  static func inspect(
    _ url: String,
    authentication: AuthenticationOptions? = nil,
    timeout: TimeInterval = 45
  ) async throws -> MediaPreview {
    guard let backend = BackendLocator.ytDLP else {
      throw PreviewError.missingBackend
    }

    let session = InspectionSession(
      executableURL: backend,
      arguments: arguments(
        url: url,
        authentication: authentication,
        nodePath: BackendLocator.nodePath
      ),
      environment: BackendLocator.processEnvironment()
    )
    let result = try await session.run(timeout: timeout)
    try Task.checkCancellation()
    let errorText = String(decoding: result.errors, as: UTF8.self)

    guard result.terminationStatus == 0 else {
      let message = cleanError(errorText)
      throw requiresAuthentication(message)
        ? PreviewError.authenticationRequired(message)
        : PreviewError.inspectionFailed(message)
    }
    return try parse(result.output)
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
    arguments += ["--", url]
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
