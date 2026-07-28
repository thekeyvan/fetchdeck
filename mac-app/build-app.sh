#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
tools_dir="$repo_dir/.build-tools"
runtime_dir="$tools_dir/runtime"
dist_dir="$repo_dir/dist"
app_name="FetchDeck"
app_bundle="$dist_dir/$app_name.app"
contents_dir="$app_bundle/Contents"
macos_dir="$contents_dir/MacOS"
resources_dir="$contents_dir/Resources"
backend="$tools_dir/yt-dlp_macos"
checksums="$tools_dir/SHA2-256SUMS"
icon_png="$tools_dir/AppIcon-1024.png"
iconset="$tools_dir/AppIcon.iconset"
icon_file="$tools_dir/AppIcon.icns"
release_base="https://github.com/yt-dlp/yt-dlp/releases/latest/download"

mkdir -p "$tools_dir"
"$script_dir/fetch-distribution-dependencies.sh" >/dev/null

if [ ! -x "$backend" ]; then
    binary_tmp="$backend.download"
    checksums_tmp="$checksums.download"
    trap 'rm -f "$binary_tmp" "$checksums_tmp"' EXIT

    curl --fail --location --retry 3 \
        "$release_base/yt-dlp_macos" \
        --output "$binary_tmp"
    curl --fail --location --retry 3 \
        "$release_base/SHA2-256SUMS" \
        --output "$checksums_tmp"

    expected_hash=$(awk '$2 == "yt-dlp_macos" { print $1 }' "$checksums_tmp")
    actual_hash=$(shasum -a 256 "$binary_tmp" | awk '{ print $1 }')
    if [ -z "$expected_hash" ] || [ "$expected_hash" != "$actual_hash" ]; then
        echo "yt-dlp checksum verification failed." >&2
        exit 1
    fi

    mv "$binary_tmp" "$backend"
    mv "$checksums_tmp" "$checksums"
    chmod +x "$backend"
    trap - EXIT
fi

backend_version=$("$backend" --version)

swift test --package-path "$script_dir"
swift build \
    --configuration release \
    --package-path "$script_dir" \
    --arch arm64 \
    --arch x86_64

swift "$script_dir/generate-icon.swift" "$icon_png"
rm -rf "$iconset"
mkdir -p "$iconset"
for icon_size in 16 32 128 256 512; do
    double_size=$((icon_size * 2))
    sips -z "$icon_size" "$icon_size" "$icon_png" \
        --out "$iconset/icon_${icon_size}x${icon_size}.png" >/dev/null
    sips -z "$double_size" "$double_size" "$icon_png" \
        --out "$iconset/icon_${icon_size}x${icon_size}@2x.png" >/dev/null
done
iconutil --convert icns "$iconset" --output "$icon_file"

rm -rf "$app_bundle"
mkdir -p "$macos_dir" "$resources_dir"
cp "$script_dir/.build/apple/Products/Release/FetchDeckApp" \
    "$macos_dir/FetchDeckApp"
cp "$backend" "$resources_dir/yt-dlp_macos"
cp "$runtime_dir/ffmpeg" "$resources_dir/ffmpeg"
cp "$runtime_dir/ffprobe" "$resources_dir/ffprobe"
cp "$runtime_dir/node" "$resources_dir/node"
cp "$icon_file" "$resources_dir/AppIcon.icns"
cp "$script_dir/Info.plist" "$contents_dir/Info.plist"
cp "$repo_dir/LICENSE" "$resources_dir/FetchDeck-LICENSE"
cp "$repo_dir/third-party/yt-dlp-LICENSE" \
    "$resources_dir/yt-dlp-LICENSE"
cp "$repo_dir/third-party/yt-dlp-THIRD_PARTY_LICENSES.txt" \
    "$resources_dir/yt-dlp-THIRD_PARTY_LICENSES.txt"
cp "$runtime_dir/ffmpeg-LICENSE-LGPLv2.1" \
    "$resources_dir/ffmpeg-LICENSE-LGPLv2.1"
cp "$runtime_dir/ffmpeg-LICENSE-LGPLv3" \
    "$resources_dir/ffmpeg-LICENSE-LGPLv3"
cp "$runtime_dir/lame-LICENSE" "$resources_dir/lame-LICENSE"
cp "$tools_dir/distribution/ffmpeg-8.1.2.tar.xz" \
    "$resources_dir/ffmpeg-8.1.2-source.tar.xz"
cp "$tools_dir/distribution/lame-3.101.tar.gz" \
    "$resources_dir/lame-3.101-source.tar.gz"
cp "$script_dir/build-ffmpeg-runtime.sh" \
    "$resources_dir/build-ffmpeg-runtime.sh"
cp "$runtime_dir/node-LICENSE" "$resources_dir/node-LICENSE"
cp "$script_dir/THIRD_PARTY_NOTICES.md" "$resources_dir/THIRD_PARTY_NOTICES.md"

/usr/libexec/PlistBuddy \
    -c "Set :YTBackendVersion $backend_version" \
    "$contents_dir/Info.plist"
signing_identity=${SIGNING_IDENTITY:--}

sign_runtime() {
    if [ "$signing_identity" = "-" ]; then
        codesign --force --options runtime --sign - "$@"
    else
        codesign \
            --force \
            --options runtime \
            --timestamp \
            --sign "$signing_identity" \
            "$@"
    fi
}

sign_runtime \
    --entitlements "$script_dir/YTDLP.entitlements.plist" \
    "$resources_dir/yt-dlp_macos"
sign_runtime "$resources_dir/ffmpeg"
sign_runtime "$resources_dir/ffprobe"
sign_runtime \
    --entitlements "$script_dir/Node.entitlements.plist" \
    "$resources_dir/node"
sign_runtime \
    --entitlements "$script_dir/App.entitlements.plist" \
    "$app_bundle"
codesign --verify --deep --strict "$app_bundle"
for universal_binary in \
    "$macos_dir/FetchDeckApp" \
    "$resources_dir/yt-dlp_macos" \
    "$resources_dir/ffmpeg" \
    "$resources_dir/ffprobe" \
    "$resources_dir/node"
do
    lipo "$universal_binary" -verify_arch arm64 x86_64
done

echo "$app_bundle"
