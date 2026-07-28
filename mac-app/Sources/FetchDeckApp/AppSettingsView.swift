import SwiftUI

private enum SettingsCategory: String, CaseIterable, Identifiable {
  case downloads
  case queue
  case media
  case access
  case advanced

  var id: String { rawValue }

  var title: String {
    switch self {
    case .downloads: "Downloads"
    case .queue: "Queue"
    case .media: "Media"
    case .access: "Access"
    case .advanced: "Advanced"
    }
  }

  var symbol: String {
    switch self {
    case .downloads: "arrow.down.circle.fill"
    case .queue: "list.number"
    case .media: "wand.and.stars"
    case .access: "person.badge.key.fill"
    case .advanced: "gearshape.2.fill"
    }
  }

  var detail: String {
    switch self {
    case .downloads:
      "Choose what new downloads contain and where FetchDeck saves them."
    case .queue:
      "Control simultaneous work, speed limits, fragments, and retries."
    case .media:
      "Choose the metadata, artwork, captions, and supported segments added to files."
    case .access:
      "Use a local browser session for media that requires an account."
    case .advanced:
      "Check the packaged components that power site support and media processing."
    }
  }
}

struct AppSettingsView: View {
  @EnvironmentObject private var settings: AppSettings
  @EnvironmentObject private var downloads: DownloadManager
  @State private var category: SettingsCategory = .downloads

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        pageHeader
        categoryPicker
        selectedCard
      }
      .padding(30)
      .frame(maxWidth: 820)
      .frame(maxWidth: .infinity)
    }
  }

  private var pageHeader: some View {
    HStack(alignment: .top) {
      VStack(alignment: .leading, spacing: 5) {
        Text("Settings")
          .font(.largeTitle.bold())
        Text("Defaults for new downloads, grouped by what they control.")
          .foregroundStyle(.secondary)
      }
      Spacer()
      Button("Reset Download Defaults") {
        settings.reset()
      }
      .help("Reset download, queue, and media defaults")
    }
  }

  private var categoryPicker: some View {
    VStack(alignment: .leading, spacing: 10) {
      Picker("Settings category", selection: $category) {
        ForEach(SettingsCategory.allCases) { item in
          Label(item.title, systemImage: item.symbol)
            .tag(item)
        }
      }
      .pickerStyle(.segmented)

      Text(category.detail)
        .font(.callout)
        .foregroundStyle(.secondary)
        .contentTransition(.opacity)
    }
  }

  @ViewBuilder
  private var selectedCard: some View {
    switch category {
    case .downloads:
      downloadCard
    case .queue:
      transferCard
    case .media:
      finishingCard
    case .access:
      accountCard
    case .advanced:
      systemCard
    }
  }

  private var transferCard: some View {
    SurfaceCard {
      VStack(alignment: .leading, spacing: 18) {
        HStack {
          Label("Queue & performance", systemImage: "speedometer")
            .font(.headline)
          Spacer()
          StatusPill(
            icon: "arrow.down.circle.fill",
            text: "\(downloads.maxConcurrentDownloads) AT ONCE",
            tint: .blue
          )
        }

        LabeledContent("Simultaneous downloads") {
          Stepper(
            value: $downloads.maxConcurrentDownloads,
            in: 1...8
          ) {
            Text("\(downloads.maxConcurrentDownloads)")
              .monospacedDigit()
              .frame(width: 24)
          }
        }
        Text(
          "Active transfers are allowed to finish when you lower this value; the new limit applies as queue slots become available."
        )
        .font(.caption)
        .foregroundStyle(.secondary)

        Divider()
        LabeledContent("Fragments per download") {
          Stepper(value: $settings.concurrentFragments, in: 1...16) {
            Text("\(settings.concurrentFragments)")
              .monospacedDigit()
              .frame(width: 24)
          }
        }
        LabeledContent("Maximum speed per download") {
          Picker("Maximum speed", selection: $settings.rateLimit) {
            ForEach(DownloadRateLimit.allCases) { limit in
              Text(limit.title).tag(limit)
            }
          }
          .labelsHidden()
          .frame(width: 180)
        }
        LabeledContent("Automatic retries") {
          Stepper(value: $settings.retries, in: 1...30) {
            Text("\(settings.retries)")
              .monospacedDigit()
              .frame(width: 30)
          }
        }

        Label(
          "Each queued item keeps the transfer settings it was created with.",
          systemImage: "info.circle"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
    }
  }

  private var accountCard: some View {
    SurfaceCard {
      VStack(alignment: .leading, spacing: 16) {
        HStack {
          Label("Site access", systemImage: "person.badge.key.fill")
            .font(.headline)
          Spacer()
          StatusPill(
            icon: settings.accessSource.symbol,
            text: settings.accessSource.shortTitle.uppercased(),
            tint: settings.authentication == nil ? Color.secondary : .green
          )
        }

        Text(
          "Member, private, premium, and age-restricted media needs the same signed-in session that can play it in your browser. FetchDeck reads that session locally; it never stores your password or uploads cookies."
        )
        .font(.callout)
        .foregroundStyle(.secondary)

        LabeledContent("Session source") {
          Picker("Session source", selection: $settings.accessSource) {
            ForEach(YouTubeAccessSource.allCases) { source in
              Text(source.title).tag(source)
            }
          }
          .labelsHidden()
          .frame(width: 220)
        }

        if settings.accessSource == .cookiesFile {
          Divider()
          LabeledContent("Cookie file") {
            HStack {
              Text(
                settings.cookiesFilePath.isEmpty
                  ? "No file selected" : settings.cookiesFilePath
              )
              .lineLimit(1)
              .truncationMode(.middle)
              Button(settings.cookiesFilePath.isEmpty ? "Choose…" : "Change…") {
                settings.chooseCookiesFile()
              }
            }
          }
          Text(
            "Use a Netscape-format cookies.txt file. Treat it like a password and never share it."
          )
          .font(.caption)
          .foregroundStyle(.orange)
        } else if settings.accessSource == .safari {
          Divider()
          HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.shield.fill")
              .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
              Text("Safari may require Full Disk Access")
                .fontWeight(.medium)
              Text(
                "If analysis reports a permission error, allow FetchDeck in Privacy & Security → Full Disk Access, then quit and reopen the app."
              )
              .font(.caption)
              .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open Privacy Settings") {
              settings.openFullDiskAccessSettings()
            }
          }
        } else if settings.authentication != nil {
          Divider()
          Label(
            "Be signed into the source site in \(settings.accessSource.title). macOS may ask for Keychain permission the first time.",
            systemImage: "checkmark.shield.fill"
          )
          .font(.caption)
          .foregroundStyle(.green)
        }
      }
    }
  }

  private var downloadCard: some View {
    SurfaceCard {
      VStack(alignment: .leading, spacing: 18) {
        Label("Download defaults", systemImage: "arrow.down.square.fill")
          .font(.headline)
        LabeledContent("Mode") {
          Picker("Mode", selection: $settings.mode) {
            ForEach(DownloadMode.allCases) { Text($0.title).tag($0) }
          }
          .labelsHidden()
          .frame(width: 220)
        }
        if settings.mode == .video {
          LabeledContent("Video quality") {
            Picker("Quality", selection: $settings.quality) {
              ForEach(DownloadQuality.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .frame(width: 220)
          }
        } else {
          LabeledContent("Audio format") {
            Picker("Audio", selection: $settings.audioFormat) {
              ForEach(AudioFormat.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .frame(width: 220)
          }
        }
        LabeledContent("Destination") {
          HStack {
            Text(settings.outputPath)
              .lineLimit(1)
              .truncationMode(.middle)
            Button("Choose…") { settings.chooseOutputDirectory() }
          }
        }
      }
    }
  }

  private var finishingCard: some View {
    SurfaceCard {
      VStack(alignment: .leading, spacing: 16) {
        Label("Media details", systemImage: "wand.and.stars")
          .font(.headline)
        settingToggle(
          "Embed metadata",
          "Keep title, creator, and source information in the file.",
          "tag.fill",
          $settings.embedMetadata
        )
        Divider()
        settingToggle(
          "Embed artwork",
          "Use the source thumbnail as cover art when supported.",
          "photo.fill",
          $settings.embedThumbnail
        )
        Divider()
        settingToggle(
          "Embed English subtitles",
          "Include creator captions or automatic captions in video downloads.",
          "captions.bubble.fill",
          $settings.embedSubtitles
        )
        Divider()
        settingToggle(
          "Skip supported sponsor segments",
          "Remove sponsors, intros, outros, and self-promotion when segment data is available.",
          "forward.fill",
          $settings.removeSponsors
        )
      }
    }
  }

  private var systemCard: some View {
    SurfaceCard {
      VStack(alignment: .leading, spacing: 15) {
        Label("Components & compatibility", systemImage: "stethoscope")
          .font(.headline)
        healthRow(
          "yt-dlp",
          detail: Bundle.main.object(forInfoDictionaryKey: "YTBackendVersion")
            as? String ?? "Development",
          ready: BackendLocator.ytDLP != nil
        )
        healthRow(
          "ffmpeg",
          detail: "Best-quality stream merging",
          ready: BackendLocator.ffmpegDirectory != nil
        )
        healthRow(
          "Node.js",
          detail: "Site JavaScript runtime",
          ready: BackendLocator.nodePath != nil
        )
        Divider()
        Link(
          "Browse yt-dlp’s supported sites",
          destination: URL(
            string: "https://github.com/yt-dlp/yt-dlp/blob/master/supportedsites.md"
          )!
        )
      }
    }
  }

  private func settingToggle(
    _ title: String,
    _ detail: String,
    _ icon: String,
    _ binding: Binding<Bool>
  ) -> some View {
    Toggle(isOn: binding) {
      HStack(spacing: 12) {
        Image(systemName: icon)
          .frame(width: 24)
          .foregroundStyle(.tint)
        VStack(alignment: .leading, spacing: 2) {
          Text(title).fontWeight(.medium)
          Text(detail)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
    .toggleStyle(.switch)
  }

  private func healthRow(
    _ name: String,
    detail: String,
    ready: Bool
  ) -> some View {
    HStack {
      Image(systemName: ready ? "checkmark.circle.fill" : "xmark.circle.fill")
        .foregroundStyle(ready ? .green : .red)
      Text(name).fontWeight(.medium)
      Spacer()
      Text(detail)
        .foregroundStyle(.secondary)
      Text(ready ? "Ready" : "Missing")
        .font(.caption.weight(.semibold))
        .foregroundStyle(ready ? .green : .red)
    }
  }
}
