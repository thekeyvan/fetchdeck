# Contributing to FetchDeck

Thanks for helping improve FetchDeck.

## Before opening an issue

- Search existing issues for the same behavior.
- Confirm the URL works with the latest yt-dlp release.
- Remove cookies, account details, local paths, and other private information
  from logs.
- Do not attach copyrighted media or authentication files.

## Development

```sh
swift test --package-path mac-app
xcrun swift-format lint --strict --recursive \
  mac-app/Sources mac-app/Tests mac-app/Package.swift \
  mac-app/generate-icon.swift
```

Build the complete local application with:

```sh
./mac-app/build-app.sh
```

## Pull requests

- Keep each pull request focused on one change.
- Add or update tests for behavior changes.
- Match the existing Swift formatting.
- Explain the user-visible impact and how you validated it.
- Do not commit build output, downloaded runtimes, cookies, or downloaded
  media.

By contributing, you agree that your contribution is licensed under the MIT
License.
