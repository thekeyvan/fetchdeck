import SwiftUI

struct DownloadsView: View {
  @EnvironmentObject private var downloads: DownloadManager

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        pageHeader
        if downloads.activeJobs.isEmpty {
          emptyState
        } else {
          ForEach(downloads.activeJobs) { job in
            JobCard(job: job, showsLog: true)
          }
        }
      }
      .padding(30)
      .frame(maxWidth: 940)
      .frame(maxWidth: .infinity)
    }
  }

  private var pageHeader: some View {
    SurfaceCard {
      VStack(alignment: .leading, spacing: 14) {
        HStack {
          VStack(alignment: .leading, spacing: 5) {
            Text("Downloads")
              .font(.largeTitle.bold())
            Text("A resilient multi-site queue with controlled parallel transfers.")
              .foregroundStyle(.secondary)
          }
          Spacer()
          if downloads.runningCount > 0 {
            StatusPill(
              icon: "bolt.fill",
              text: "\(downloads.runningCount) ACTIVE",
              tint: .green
            )
          }
          if downloads.queuedCount > 0 {
            StatusPill(
              icon: "clock.fill",
              text: "\(downloads.queuedCount) QUEUED",
              tint: .blue
            )
          }
        }

        if !downloads.activeJobs.isEmpty {
          ProgressView(value: downloads.aggregateProgress, total: 100)
          HStack {
            Text(
              "Up to \(downloads.maxConcurrentDownloads) simultaneous download\(downloads.maxConcurrentDownloads == 1 ? "" : "s")"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            Spacer()
            if downloads.queuedCount > 0 {
              Button {
                downloads.toggleQueuePause()
              } label: {
                Label(
                  downloads.queuePaused ? "Resume Queue" : "Pause Queue",
                  systemImage: downloads.queuePaused ? "play.fill" : "pause.fill"
                )
              }
              .help("Active transfers continue; this controls queued work.")
              Button("Cancel Queued", role: .destructive) {
                downloads.cancelQueued()
              }
            }
          }
          .buttonStyle(.bordered)
        }
      }
    }
  }

  private var emptyState: some View {
    SurfaceCard {
      VStack(spacing: 14) {
        Image(systemName: "tray.and.arrow.down.fill")
          .font(.system(size: 46))
          .foregroundStyle(.tint)
        Text("Your queue is clear")
          .font(.title2.bold())
        Text("Analyze a link in New Download to add your next video or playlist.")
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 46)
    }
  }
}

struct LibraryView: View {
  @EnvironmentObject private var downloads: DownloadManager

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        HStack {
          VStack(alignment: .leading, spacing: 5) {
            Text("History")
              .font(.largeTitle.bold())
            Text("Completed, cancelled, and retryable downloads.")
              .foregroundStyle(.secondary)
          }
          Spacer()
          if !downloads.historyJobs.isEmpty {
            Button("Clear History", role: .destructive) {
              downloads.clearHistory()
            }
          }
        }

        if downloads.historyJobs.isEmpty {
          SurfaceCard {
            VStack(spacing: 12) {
              Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 42))
                .foregroundStyle(.tint)
              Text("No history yet")
                .font(.title2.bold())
              Text("Finished downloads will appear here.")
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 36)
          }
        } else {
          ForEach(downloads.historyJobs) { job in
            JobCard(job: job, showsLog: false)
          }
        }
      }
      .padding(30)
      .frame(maxWidth: 940)
      .frame(maxWidth: .infinity)
    }
  }
}

private struct JobCard: View {
  @EnvironmentObject private var downloads: DownloadManager
  let job: DownloadJob
  let showsLog: Bool
  @State private var logExpanded = false

  var body: some View {
    SurfaceCard {
      VStack(alignment: .leading, spacing: 14) {
        HStack(spacing: 16) {
          MediaArtwork(urlString: job.preview.thumbnailURL, height: 92)
            .frame(width: 164)
          VStack(alignment: .leading, spacing: 7) {
            HStack {
              StatusPill(
                icon: job.state.symbol,
                text: job.state.title.uppercased(),
                tint: stateColor
              )
              StatusPill(
                icon: job.options.mode.symbol,
                text: job.formatSummary,
                tint: Color.secondary
              )
            }
            Text(job.preview.title)
              .font(.headline)
              .lineLimit(2)
            Text(job.statusText)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Spacer()
          actionButtons
        }

        if job.state.isPending || job.progress > 0 {
          VStack(spacing: 6) {
            ProgressView(value: job.progress, total: 100)
            HStack {
              Text(job.outputPath)
                .lineLimit(1)
                .truncationMode(.middle)
              Spacer()
              Text(job.progress, format: .number.precision(.fractionLength(0)))
                .monospacedDigit()
              Text("%")
              if let sizeText = job.sizeText {
                Text("· \(sizeText)")
              }
              if let speedText = job.speedText {
                Text("· \(speedText)")
              }
              if let etaText = job.etaText {
                Text("· ETA \(etaText)")
              }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
          }
        }

        if showsLog, !job.log.isEmpty {
          DisclosureGroup("Activity log", isExpanded: $logExpanded) {
            ScrollView {
              Text(job.log)
                .font(.system(.caption2, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
            }
            .frame(maxHeight: 180)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .padding(.top, 8)
          }
          .font(.caption.weight(.semibold))
        }
      }
    }
  }

  @ViewBuilder
  private var actionButtons: some View {
    HStack {
      if job.state == .queued {
        Button {
          downloads.moveUp(job.id)
        } label: {
          Image(systemName: "arrow.up")
        }
        .help("Move earlier")
        Button {
          downloads.moveDown(job.id)
        } label: {
          Image(systemName: "arrow.down")
        }
        .help("Move later")
        Button(role: .destructive) {
          downloads.cancel(job.id)
        } label: {
          Image(systemName: "xmark")
        }
        .help("Remove from queue")
      } else if job.state.isPending {
        Button(role: .destructive) {
          downloads.cancel(job.id)
        } label: {
          Image(systemName: "xmark")
        }
        .help("Cancel")
      } else {
        if job.state == .failed || job.state == .cancelled {
          Button {
            downloads.retry(job.id)
          } label: {
            Image(systemName: "arrow.clockwise")
          }
          .help("Retry and resume")
        }
        Button {
          downloads.reveal(job)
        } label: {
          Image(systemName: "folder")
        }
        .help("Show in Finder")
        Button(role: .destructive) {
          downloads.remove(job.id)
        } label: {
          Image(systemName: "trash")
        }
        .help("Remove from history")
      }
    }
    .buttonStyle(.bordered)
  }

  private var stateColor: Color {
    switch job.state {
    case .completed: .green
    case .failed: .red
    case .cancelled: .orange
    case .processing: .purple
    default: .accentColor
    }
  }
}
