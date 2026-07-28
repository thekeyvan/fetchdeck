# Third-party components

FetchDeck release builds bundle the following upstream tools:

- yt-dlp
- FFmpeg
- LAME
- Node.js

The build scripts verify downloaded artifacts with pinned SHA-256 hashes.
FFmpeg and LAME are compiled from official source for both Apple Silicon and
Intel. Their exact source archives, license texts, and the build recipe are
included in every app bundle.

`yt-dlp-LICENSE` and `yt-dlp-THIRD_PARTY_LICENSES.txt` document the licensing
of the official yt-dlp executable fetched during the build.

See `mac-app/THIRD_PARTY_NOTICES.md` for pinned versions and upstream source
locations.
