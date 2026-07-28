# Changelog

## 1.0.1

- Prevent cancelled downloads from holding a queue slot indefinitely.
- Escalate cancellation when a downloader process does not exit cleanly.
- Preserve ordered progress output and useful final error messages.
- Prevent URL analysis from hanging on full output pipes.
- Cancel stale URL analyses and ignore results for superseded links.
- Harden backend argument handling and packaged app metadata.

## 1.0.0

- Initial FetchDeck release.
- Native SwiftUI interface for individual media and playlists.
- Persistent concurrent queue with configurable simultaneous downloads.
- Video quality and audio format selection.
- Browser-session and cookies-file access for authorized signed-in media.
- Retry, resume, bandwidth, fragment, metadata, artwork, subtitle, and
  SponsorBlock controls.
- Self-contained universal app for Apple Silicon and Intel.
- Developer ID signing and Apple notarization.
