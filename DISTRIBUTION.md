# Distributing FetchDeck

The release workflow produces a self-contained universal macOS application and
a notarized DMG for direct distribution outside the Mac App Store.

The app bundles universal `arm64` and `x86_64` builds of the Swift executable,
yt-dlp, ffmpeg, ffprobe, and Node.js. Recipients do not need Homebrew or any
command-line setup.

## One-time Apple setup

1. Open **Xcode → Settings → Accounts** and add the Apple ID enrolled in the
   Apple Developer Program.
2. Select the team, choose **Manage Certificates…**, and create a
   **Developer ID Application** certificate.
3. Create an app-specific password for the Apple ID, then store notarization
   credentials in the login Keychain:

   ```sh
   xcrun notarytool store-credentials fetchdeck \
     --apple-id "YOUR_APPLE_ID" \
     --team-id "YOUR_TEAM_ID"
   ```

`notarytool` securely prompts for the app-specific password so it does not
appear in shell history. The release script reads the certificate from the
Keychain and notarization credentials through the profile name. Secrets are not
stored in this repository.

## Create a release

```sh
cd /path/to/fetchdeck
./mac-app/release-app.sh
```

The script:

1. verifies checksums for every downloaded runtime;
2. runs the native test suite;
3. builds the app for Apple Silicon and Intel;
4. signs nested executables and the app with Hardened Runtime enabled;
5. creates a compressed DMG with an Applications shortcut;
6. submits the DMG to Apple’s notary service and waits for approval;
7. staples the approval ticket and runs Gatekeeper verification.

The shareable artifact is:

```text
dist/FetchDeck.dmg
```

For packaging tests before the Developer ID certificate is installed:

```sh
./mac-app/release-app.sh --local
```

That mode creates an ad-hoc-signed DMG which is suitable only for local testing,
not distribution to other people.

## Optional overrides

- `DEVELOPER_ID_APPLICATION` — exact signing identity when more than one
  Developer ID Application certificate is installed.
- `NOTARY_PROFILE` — Keychain profile name; defaults to
  `fetchdeck`.

## Licensing

Third-party notices and full runtime license texts are embedded in the app’s
Resources directory. The dependency script pins versions and SHA-256 hashes,
and the build includes source locations for redistributed open-source
components.
