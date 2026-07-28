import SwiftUI

@main
struct FetchDeckApp: App {
  @StateObject private var settings = AppSettings()
  @StateObject private var downloads = DownloadManager()

  var body: some Scene {
    WindowGroup {
      RootView()
        .environmentObject(settings)
        .environmentObject(downloads)
        .frame(minWidth: 900, minHeight: 650)
    }
    .defaultSize(width: 1080, height: 760)
    .windowResizability(.contentMinSize)
  }
}
