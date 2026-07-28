import SwiftUI

struct RootView: View {
  @EnvironmentObject private var downloads: DownloadManager
  @State private var selection: SidebarDestination? = .home

  var body: some View {
    NavigationSplitView {
      List(selection: $selection) {
        Section("Create") {
          sidebarItem(.home)
        }
        Section("Your Space") {
          sidebarItem(.downloads, badge: downloads.activeJobs.count)
          sidebarItem(.library, badge: downloads.historyJobs.count)
        }
        Section {
          sidebarItem(.settings)
        }
      }
      .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 280)
      .safeAreaInset(edge: .bottom) {
        HStack(spacing: 10) {
          Image(systemName: "bolt.shield.fill")
            .foregroundStyle(.green)
          VStack(alignment: .leading, spacing: 1) {
            Text("Local & private")
              .font(.caption.weight(.semibold))
            Text("Multi-site · browser sessions stay local")
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
          Spacer()
        }
        .padding(14)
      }
    } detail: {
      ZStack {
        AppBackdrop()
        switch selection ?? .home {
        case .home:
          HomeView(
            didEnqueue: { selection = .downloads },
            openSettings: { selection = .settings }
          )
        case .downloads:
          DownloadsView()
        case .library:
          LibraryView()
        case .settings:
          AppSettingsView()
        }
      }
    }
    .navigationTitle((selection ?? .home).title)
  }

  private func sidebarItem(
    _ destination: SidebarDestination,
    badge: Int = 0
  ) -> some View {
    Label(destination.title, systemImage: destination.symbol)
      .badge(badge)
      .tag(destination)
  }
}

struct AppBackdrop: View {
  var body: some View {
    LinearGradient(
      colors: [
        Color(nsColor: .windowBackgroundColor),
        Color.accentColor.opacity(0.045),
        Color(nsColor: .windowBackgroundColor),
      ],
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
    .ignoresSafeArea()
  }
}

struct SurfaceCard<Content: View>: View {
  let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    content
      .padding(18)
      .background(.regularMaterial)
      .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
          .stroke(.white.opacity(0.12), lineWidth: 1)
      }
      .shadow(color: .black.opacity(0.06), radius: 18, y: 8)
  }
}

struct MediaArtwork: View {
  let urlString: String?
  var height: CGFloat = 180

  var body: some View {
    AsyncImage(url: urlString.flatMap(URL.init(string:))) { phase in
      switch phase {
      case .success(let image):
        image.resizable().scaledToFill()
      default:
        ZStack {
          LinearGradient(
            colors: [.blue.opacity(0.8), .purple.opacity(0.85)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
          Image(systemName: "play.rectangle.fill")
            .font(.system(size: 46))
            .foregroundStyle(.white.opacity(0.9))
        }
      }
    }
    .frame(maxWidth: .infinity)
    .frame(height: height)
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
  }
}

struct StatusPill: View {
  let icon: String
  let text: String
  var tint: Color = .accentColor

  var body: some View {
    Label(text, systemImage: icon)
      .font(.caption.weight(.semibold))
      .foregroundStyle(tint)
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .background(tint.opacity(0.11))
      .clipShape(Capsule())
  }
}
