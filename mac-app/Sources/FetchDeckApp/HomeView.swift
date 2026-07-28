import AppKit
import SwiftUI

struct HomeView: View {
  @EnvironmentObject private var settings: AppSettings
  @EnvironmentObject private var downloads: DownloadManager
  let didEnqueue: () -> Void
  let openSettings: () -> Void

  @State private var urlString = ""
  @State private var preview: MediaPreview?
  @State private var isInspecting = false
  @State private var errorMessage: String?
  @State private var authenticationError = false
  @State private var inspectionID: UUID?
  @State private var inspectTask: Task<Void, Never>?
  @FocusState private var isURLFocused: Bool

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        hero
        inputCard
        if isInspecting {
          analyzingCard
        } else if let preview {
          previewCard(preview)
          optionsCard
        } else {
          inspirationRow
        }
      }
      .padding(30)
      .frame(maxWidth: 980)
      .frame(maxWidth: .infinity)
    }
    .onAppear { isURLFocused = true }
    .onDisappear { cancelInspection() }
    .alert(
      authenticationError ? "Account access required" : "Couldn’t analyze this URL",
      isPresented: Binding(
        get: { errorMessage != nil },
        set: {
          if !$0 {
            errorMessage = nil
            authenticationError = false
          }
        }
      )
    ) {
      if authenticationError {
        Button("Account Settings") {
          errorMessage = nil
          authenticationError = false
          openSettings()
        }
      }
      Button("OK") { errorMessage = nil }
    } message: {
      Text(errorMessage ?? "")
    }
  }

  private var hero: some View {
    ZStack(alignment: .bottomLeading) {
      RoundedRectangle(cornerRadius: 26, style: .continuous)
        .fill(
          LinearGradient(
            colors: [
              Color(red: 0.03, green: 0.43, blue: 0.96),
              Color(red: 0.36, green: 0.18, blue: 0.86),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        )
      Circle()
        .fill(.white.opacity(0.08))
        .frame(width: 330, height: 330)
        .offset(x: 590, y: -110)
      VStack(alignment: .leading, spacing: 10) {
        StatusPill(
          icon: "sparkles",
          text: "YOUR MEDIA, YOUR WAY",
          tint: .white
        )
        Text("Bring media offline.")
          .font(.system(size: 34, weight: .bold, design: .rounded))
          .foregroundStyle(.white)
        Text(
          "Videos, audio, streams, posts, and collections from across the web — organized in one native queue."
        )
        .font(.title3)
        .foregroundStyle(.white.opacity(0.78))
        .frame(maxWidth: 690, alignment: .leading)
      }
      .padding(28)
    }
    .frame(height: 220)
    .clipped()
  }

  private var inputCard: some View {
    SurfaceCard {
      VStack(alignment: .leading, spacing: 12) {
        Label("Paste a media link", systemImage: "link")
          .font(.headline)
        HStack(spacing: 10) {
          TextField(
            "Video, audio, post, or collection URL",
            text: $urlString
          )
          .textFieldStyle(.plain)
          .font(.title3)
          .focused($isURLFocused)
          .onSubmit { analyze() }
          .onChange(of: urlString) { _ in
            preview = nil
          }
          Button {
            paste()
          } label: {
            Label("Paste", systemImage: "doc.on.clipboard")
          }
          Button {
            analyze()
          } label: {
            Label("Analyze", systemImage: "sparkles")
          }
          .buttonStyle(.borderedProminent)
          .disabled(isInspecting || normalizedURL == nil)
        }
        .padding(12)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

        Divider()
        HStack(spacing: 12) {
          Image(systemName: settings.accessSource.symbol)
            .foregroundStyle(settings.authentication == nil ? Color.secondary : .green)
          VStack(alignment: .leading, spacing: 2) {
            Text("Signed-in browser access")
              .font(.caption.weight(.semibold))
            Text(
              settings.accessSource == .cookiesFile && settings.cookiesFilePath.isEmpty
                ? "Choose a cookies.txt file to enable account access."
                : settings.authentication == nil
                  ? "Use a signed-in browser for member, private, or age-restricted media."
                  : "Using your local \(settings.authentication?.summary ?? "") session."
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
          }
          Spacer()
          Picker("Signed-in browser access", selection: $settings.accessSource) {
            ForEach(YouTubeAccessSource.allCases) { source in
              Text(source.title).tag(source)
            }
          }
          .labelsHidden()
          .frame(width: 190)
          if settings.accessSource == .cookiesFile {
            Button(settings.cookiesFilePath.isEmpty ? "Choose…" : "Change…") {
              settings.chooseCookiesFile()
            }
          }
        }
      }
    }
  }

  private var analyzingCard: some View {
    SurfaceCard {
      HStack(spacing: 16) {
        ProgressView().controlSize(.large)
        VStack(alignment: .leading, spacing: 4) {
          Text("Reading the source…")
            .font(.headline)
          Text("Fetching the title, artwork, duration, and collection details.")
            .foregroundStyle(.secondary)
        }
        Spacer()
      }
    }
  }

  private func previewCard(_ preview: MediaPreview) -> some View {
    SurfaceCard {
      HStack(spacing: 20) {
        MediaArtwork(urlString: preview.thumbnailURL, height: 178)
          .frame(width: 316)
        VStack(alignment: .leading, spacing: 12) {
          StatusPill(
            icon: preview.isPlaylist ? "rectangle.stack.fill" : "play.fill",
            text: preview.isPlaylist ? "COLLECTION" : "MEDIA"
          )
          Text(preview.title)
            .font(.title2.bold())
            .lineLimit(3)
          Text(preview.detailText)
            .foregroundStyle(.secondary)
          Spacer()
          Label("Ready to add to your local queue", systemImage: "checkmark.seal.fill")
            .font(.caption.weight(.medium))
            .foregroundStyle(.green)
        }
        .frame(maxWidth: .infinity, minHeight: 178, alignment: .leading)
      }
    }
  }

  private var optionsCard: some View {
    SurfaceCard {
      VStack(alignment: .leading, spacing: 18) {
        HStack {
          Label("Download recipe", systemImage: "slider.horizontal.3")
            .font(.headline)
          Spacer()
          Picker("Mode", selection: $settings.mode) {
            ForEach(DownloadMode.allCases) { mode in
              Label(mode.title, systemImage: mode.symbol).tag(mode)
            }
          }
          .pickerStyle(.segmented)
          .frame(width: 290)
        }

        HStack(spacing: 18) {
          VStack(alignment: .leading, spacing: 7) {
            Text(settings.mode == .video ? "Maximum quality" : "Audio format")
              .font(.caption.weight(.semibold))
              .foregroundStyle(.secondary)
            if settings.mode == .video {
              Picker("Quality", selection: $settings.quality) {
                ForEach(DownloadQuality.allCases) { quality in
                  Text(quality.title).tag(quality)
                }
              }
              .labelsHidden()
            } else {
              Picker("Audio format", selection: $settings.audioFormat) {
                ForEach(AudioFormat.allCases) { format in
                  Text(format.title).tag(format)
                }
              }
              .labelsHidden()
            }
          }
          VStack(alignment: .leading, spacing: 7) {
            Text("Save to")
              .font(.caption.weight(.semibold))
              .foregroundStyle(.secondary)
            HStack {
              Text(settings.outputPath)
                .lineLimit(1)
                .truncationMode(.middle)
              Button("Choose…") { settings.chooseOutputDirectory() }
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }

        Divider()
        HStack(spacing: 16) {
          compactToggle("Metadata", "tag.fill", $settings.embedMetadata)
          compactToggle("Artwork", "photo.fill", $settings.embedThumbnail)
          if settings.mode == .video {
            compactToggle("English subs", "captions.bubble.fill", $settings.embedSubtitles)
          }
          compactToggle("Skip sponsors", "forward.fill", $settings.removeSponsors)
          Spacer()
          Button {
            enqueue()
          } label: {
            Label(
              preview?.isPlaylist == true ? "Download playlist" : "Start download",
              systemImage: "arrow.down.circle.fill"
            )
            .font(.headline)
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.large)
        }
      }
    }
  }

  private var inspirationRow: some View {
    HStack(spacing: 14) {
      feature("Across the web", "network", "YouTube, Vimeo, Twitch, X, and more")
      feature("Audio studio", "waveform", "MP3, M4A, FLAC, or original")
      feature("Smart transfers", "arrow.triangle.branch", "Parallel queue, limits, and resume")
    }
  }

  private func feature(_ title: String, _ icon: String, _ detail: String) -> some View {
    SurfaceCard {
      VStack(alignment: .leading, spacing: 8) {
        Image(systemName: icon)
          .font(.title2)
          .foregroundStyle(.tint)
        Text(title).font(.headline)
        Text(detail)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func compactToggle(
    _ title: String,
    _ icon: String,
    _ value: Binding<Bool>
  ) -> some View {
    Toggle(isOn: value) {
      Label(title, systemImage: icon)
        .font(.caption.weight(.medium))
    }
    .toggleStyle(.checkbox)
  }

  private var normalizedURL: String? {
    let value = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let url = URL(string: value),
      ["http", "https"].contains(url.scheme?.lowercased() ?? "")
    else { return nil }
    return value
  }

  private func paste() {
    if let value = NSPasteboard.general.string(forType: .string) {
      urlString = value.trimmingCharacters(in: .whitespacesAndNewlines)
      analyze()
    }
  }

  private func analyze() {
    guard let url = normalizedURL else { return }
    cancelInspection()
    let requestID = UUID()
    let authentication = settings.authentication
    inspectionID = requestID
    isInspecting = true
    preview = nil
    errorMessage = nil
    authenticationError = false
    inspectTask = Task { @MainActor in
      defer {
        if inspectionID == requestID {
          inspectionID = nil
          inspectTask = nil
          isInspecting = false
        }
      }
      do {
        let inspectedPreview = try await URLInspector.inspect(
          url,
          authentication: authentication
        )
        try Task.checkCancellation()
        guard inspectionID == requestID, normalizedURL == url else { return }
        preview = inspectedPreview
      } catch is CancellationError {
        return
      } catch {
        guard inspectionID == requestID, normalizedURL == url else { return }
        authenticationError =
          (error as? PreviewError)?.requiresAuthentication == true
        errorMessage = error.localizedDescription
      }
    }
  }

  private func cancelInspection() {
    inspectionID = nil
    inspectTask?.cancel()
    inspectTask = nil
    isInspecting = false
  }

  private func enqueue() {
    guard let url = normalizedURL, let preview else { return }
    downloads.enqueue(
      url: url,
      preview: preview,
      options: settings.options,
      outputPath: settings.outputPath
    )
    urlString = ""
    self.preview = nil
    didEnqueue()
  }
}
