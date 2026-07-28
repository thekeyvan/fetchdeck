import AppKit
import Foundation

enum DownloadConcurrencyPolicy {
  static func availableSlots(
    activeCount: Int,
    maximum: Int,
    queuePaused: Bool
  ) -> Int {
    guard !queuePaused else { return 0 }
    return max(maximum - activeCount, 0)
  }
}

@MainActor
final class DownloadManager: ObservableObject {
  private enum TransferEvent {
    case output(String)
    case endOfFile
    case terminated(Int32)
  }

  @Published private(set) var jobs: [DownloadJob] = []
  @Published private(set) var queuePaused = false
  @Published var maxConcurrentDownloads: Int {
    didSet {
      UserDefaults.standard.set(
        maxConcurrentDownloads,
        forKey: "maxConcurrentDownloads"
      )
      startEligibleJobs()
    }
  }

  private final class ActiveTransfer {
    let process: Process
    let pipe: Pipe
    var parseBuffer = ""
    var currentItem = 0
    var itemCount: Int
    var cancelRequested = false
    var lastError: String?
    var didReachEOF = false
    var terminationStatus: Int32?
    let eventContinuation: AsyncStream<TransferEvent>.Continuation
    var eventTask: Task<Void, Never>?

    init(
      process: Process,
      pipe: Pipe,
      itemCount: Int,
      eventContinuation: AsyncStream<TransferEvent>.Continuation
    ) {
      self.process = process
      self.pipe = pipe
      self.itemCount = itemCount
      self.eventContinuation = eventContinuation
    }
  }

  private var transfers: [UUID: ActiveTransfer] = [:]

  init() {
    let savedLimit = UserDefaults.standard.integer(forKey: "maxConcurrentDownloads")
    maxConcurrentDownloads = savedLimit > 0 ? min(savedLimit, 8) : 2
    load()
    for index in jobs.indices where jobs[index].state.isPending {
      jobs[index].state = .queued
      jobs[index].statusText = "Waiting in queue"
      jobs[index].speedText = nil
      jobs[index].etaText = nil
    }
    Task { @MainActor [weak self] in
      self?.startEligibleJobs()
    }
  }

  var activeJobs: [DownloadJob] {
    jobs.filter { $0.state.isPending }
  }

  var historyJobs: [DownloadJob] {
    jobs
      .filter { !$0.state.isPending }
      .sorted { ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt) }
  }

  var runningCount: Int { transfers.count }
  var queuedCount: Int { jobs.filter { $0.state == .queued }.count }

  var aggregateProgress: Double {
    let pending = activeJobs
    guard !pending.isEmpty else { return 0 }
    return pending.reduce(0) { $0 + $1.progress } / Double(pending.count)
  }

  func enqueue(
    url: String,
    preview: MediaPreview,
    options: DownloadOptions,
    outputPath: String
  ) {
    jobs.append(
      DownloadJob(
        sourceURL: url,
        preview: preview,
        options: options,
        outputPath: outputPath
      )
    )
    save()
    startEligibleJobs()
  }

  func toggleQueuePause() {
    queuePaused.toggle()
    if !queuePaused {
      startEligibleJobs()
    }
  }

  func cancel(_ id: UUID) {
    guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
    if let transfer = transfers[id], transfer.process.isRunning {
      transfer.cancelRequested = true
      jobs[index].statusText = "Cancelling safely…"
      transfer.process.interrupt()
    } else if jobs[index].state == .queued {
      jobs[index].state = .cancelled
      jobs[index].statusText = "Cancelled"
      jobs[index].completedAt = Date()
      save()
      startEligibleJobs()
    }
  }

  func cancelQueued() {
    for index in jobs.indices where jobs[index].state == .queued {
      jobs[index].state = .cancelled
      jobs[index].statusText = "Cancelled before starting"
      jobs[index].completedAt = Date()
    }
    save()
  }

  func retry(_ id: UUID) {
    guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
    jobs[index].state = .queued
    jobs[index].progress = 0
    jobs[index].speedText = nil
    jobs[index].etaText = nil
    jobs[index].statusText = "Waiting in queue"
    jobs[index].completedAt = nil
    save()
    startEligibleJobs()
  }

  func moveUp(_ id: UUID) {
    guard let index = jobs.firstIndex(where: { $0.id == id && $0.state == .queued }),
      let previous = jobs[..<index].lastIndex(where: { $0.state == .queued })
    else { return }
    jobs.swapAt(index, previous)
    save()
  }

  func moveDown(_ id: UUID) {
    guard let index = jobs.firstIndex(where: { $0.id == id && $0.state == .queued }),
      index + 1 < jobs.endIndex,
      let next = jobs[(index + 1)...].firstIndex(where: { $0.state == .queued })
    else { return }
    jobs.swapAt(index, next)
    save()
  }

  func remove(_ id: UUID) {
    guard transfers[id] == nil else { return }
    jobs.removeAll { $0.id == id }
    save()
  }

  func clearHistory() {
    jobs.removeAll { !$0.state.isPending }
    save()
  }

  func reveal(_ job: DownloadJob) {
    NSWorkspace.shared.open(
      URL(fileURLWithPath: job.outputPath, isDirectory: true)
    )
  }

  private func startEligibleJobs() {
    while DownloadConcurrencyPolicy.availableSlots(
      activeCount: transfers.count,
      maximum: maxConcurrentDownloads,
      queuePaused: queuePaused
    ) > 0,
      let index = jobs.firstIndex(where: { $0.state == .queued })
    {
      start(index: index)
    }
  }

  private func start(index: Int) {
    guard let backend = BackendLocator.ytDLP else {
      failBeforeStart(index, message: "Packaged yt-dlp engine is missing")
      return
    }
    guard let ffmpeg = BackendLocator.ffmpegDirectory else {
      failBeforeStart(index, message: "ffmpeg is missing — install it with Homebrew")
      return
    }

    let job = jobs[index]
    if let authentication = job.options.authentication,
      authentication.source == .cookiesFile
    {
      guard
        let cookiesFilePath = authentication.cookiesFilePath,
        FileManager.default.isReadableFile(
          atPath: (cookiesFilePath as NSString).expandingTildeInPath
        )
      else {
        failBeforeStart(
          index,
          message: "The selected cookies.txt file is missing or unreadable"
        )
        return
      }
    }

    let outputURL = URL(
      fileURLWithPath: (job.outputPath as NSString).expandingTildeInPath,
      isDirectory: true
    )
    do {
      try FileManager.default.createDirectory(
        at: outputURL,
        withIntermediateDirectories: true
      )
    } catch {
      failBeforeStart(index, message: error.localizedDescription)
      return
    }

    let process = Process()
    let pipe = Pipe()
    process.executableURL = backend
    process.arguments = DownloaderCommandBuilder.arguments(
      url: job.sourceURL,
      options: job.options,
      outputDirectory: outputURL,
      ffmpegDirectory: ffmpeg,
      nodePath: BackendLocator.nodePath
    )
    process.standardOutput = pipe
    process.standardError = pipe
    process.environment = processEnvironment()

    var continuation: AsyncStream<TransferEvent>.Continuation?
    let events = AsyncStream<TransferEvent> {
      continuation = $0
    }
    guard let continuation else {
      failBeforeStart(index, message: "Could not prepare the download stream")
      return
    }

    let transfer = ActiveTransfer(
      process: process,
      pipe: pipe,
      itemCount: max(job.preview.itemCount, 1),
      eventContinuation: continuation
    )
    transfer.eventTask = Task { @MainActor [weak self] in
      for await event in events {
        self?.receive(event, for: job.id)
      }
    }

    pipe.fileHandleForReading.readabilityHandler = { handle in
      let data = handle.availableData
      guard !data.isEmpty else {
        handle.readabilityHandler = nil
        continuation.yield(.endOfFile)
        return
      }
      let chunk = String(decoding: data, as: UTF8.self)
      continuation.yield(.output(chunk))
    }
    process.terminationHandler = { finished in
      continuation.yield(.terminated(finished.terminationStatus))
    }

    jobs[index].state = .downloading
    jobs[index].statusText =
      job.preview.isPlaylist ? "Reading collection…" : "Preparing download…"
    jobs[index].log = ""
    jobs[index].speedText = nil
    jobs[index].etaText = nil
    transfers[job.id] = transfer
    save()

    do {
      try process.run()
    } catch {
      pipe.fileHandleForReading.readabilityHandler = nil
      continuation.finish()
      transfer.eventTask?.cancel()
      transfers.removeValue(forKey: job.id)
      failBeforeStart(index, message: error.localizedDescription)
    }
  }

  private func failBeforeStart(_ index: Int, message: String) {
    jobs[index].state = .failed
    jobs[index].statusText = message
    jobs[index].completedAt = Date()
    save()
  }

  private func consume(_ chunk: String, for id: UUID) {
    guard let transfer = transfers[id] else { return }
    transfer.parseBuffer += chunk.replacingOccurrences(of: "\r", with: "\n")
    let lines = transfer.parseBuffer.components(separatedBy: "\n")
    transfer.parseBuffer = lines.last ?? ""
    for line in lines.dropLast() where !line.isEmpty {
      handle(line, for: id)
    }
  }

  private func handle(_ line: String, for id: UUID) {
    guard let transfer = transfers[id],
      let index = jobs.firstIndex(where: { $0.id == id })
    else { return }

    let update = ProgressParser.parse(line)

    if let itemIndex = update.itemIndex, let itemCount = update.itemCount {
      transfer.currentItem = itemIndex
      transfer.itemCount = itemCount
      jobs[index].statusText =
        "Item \(transfer.currentItem) of \(transfer.itemCount)"
    }

    if let fileProgress = update.filePercent {
      if transfer.currentItem > 0, transfer.itemCount > 0 {
        jobs[index].progress =
          (Double(transfer.currentItem - 1) + fileProgress / 100)
          / Double(transfer.itemCount) * 100
      } else {
        jobs[index].progress = fileProgress
      }
    }
    if let speed = update.speed {
      jobs[index].speedText = speed
    }
    if let eta = update.eta {
      jobs[index].etaText = eta
    }
    if let size = update.size {
      jobs[index].sizeText = size
    }

    switch update.phase {
    case .merging:
      jobs[index].state = .processing
      jobs[index].statusText = "Merging video and audio…"
    case .extractingAudio:
      jobs[index].state = .processing
      jobs[index].statusText =
        "Creating \(jobs[index].options.audioFormat.rawValue.uppercased())…"
    case .addingMetadata, .embeddingThumbnail:
      jobs[index].state = .processing
      jobs[index].statusText = "Adding finishing touches…"
    case .skippingArchived:
      jobs[index].statusText = "Already downloaded — skipping…"
    case .saved:
      jobs[index].statusText = "Saved successfully"
    case nil:
      break
    }
    if let error = update.error {
      transfer.lastError = error
    }
    appendLog(line + "\n", to: index)
  }

  private func receive(_ event: TransferEvent, for id: UUID) {
    guard let transfer = transfers[id] else { return }
    switch event {
    case .output(let chunk):
      consume(chunk, for: id)
    case .endOfFile:
      transfer.didReachEOF = true
      completeIfFinished(id)
    case .terminated(let status):
      transfer.terminationStatus = status
      completeIfFinished(id)
    }
  }

  private func completeIfFinished(_ id: UUID) {
    guard let transfer = transfers[id],
      transfer.didReachEOF,
      let exitCode = transfer.terminationStatus
    else { return }
    finish(id, exitCode: exitCode)
  }

  private func finish(_ id: UUID, exitCode: Int32) {
    guard let transfer = transfers[id],
      let index = jobs.firstIndex(where: { $0.id == id })
    else { return }

    if !transfer.parseBuffer.isEmpty {
      handle(transfer.parseBuffer, for: id)
      transfer.parseBuffer = ""
    }
    transfer.pipe.fileHandleForReading.readabilityHandler = nil
    transfer.eventContinuation.finish()
    transfers.removeValue(forKey: id)

    if transfer.cancelRequested {
      jobs[index].state = .cancelled
      jobs[index].statusText = "Cancelled — retry to resume"
      appendLog("\nCancelled. Retry to resume partial files.\n", to: index)
    } else if exitCode == 0 {
      jobs[index].state = .completed
      jobs[index].progress = 100
      jobs[index].statusText = "Download complete"
      appendLog("\nFinished successfully.\n", to: index)
    } else {
      jobs[index].state = .failed
      jobs[index].statusText =
        transfer.lastError.map { String($0.prefix(180)) }
        ?? "Failed with exit code \(exitCode)"
    }
    jobs[index].speedText = nil
    jobs[index].etaText = nil
    jobs[index].completedAt = Date()
    save()
    startEligibleJobs()
  }

  private func appendLog(_ text: String, to index: Int) {
    jobs[index].log += text
    if jobs[index].log.count > 30_000 {
      jobs[index].log.removeFirst(jobs[index].log.count - 30_000)
    }
  }

  private func processEnvironment() -> [String: String] {
    var environment = ProcessInfo.processInfo.environment
    environment["PATH"] = [
      "/opt/homebrew/bin",
      "/usr/local/bin",
      environment["PATH"] ?? "/usr/bin:/bin",
    ].joined(separator: ":")
    return environment
  }

  private var storageURL: URL {
    let root =
      FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      ).first ?? FileManager.default.homeDirectoryForCurrentUser
    return
      root
      .appendingPathComponent("FetchDeck", isDirectory: true)
      .appendingPathComponent("downloads.json")
  }

  private func load() {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    guard let data = try? Data(contentsOf: storageURL),
      let decoded = try? decoder.decode([DownloadJob].self, from: data)
    else { return }
    jobs = decoded
  }

  private func save() {
    do {
      try FileManager.default.createDirectory(
        at: storageURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      let encoder = JSONEncoder()
      encoder.dateEncodingStrategy = .iso8601
      try encoder.encode(jobs).write(to: storageURL, options: .atomic)
    } catch {
      // Transfers continue even if their UI history cannot be persisted.
    }
  }
}
