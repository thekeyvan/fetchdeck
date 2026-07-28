#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
download_dir="$repo_dir/.build-tools/distribution"
runtime_dir="$repo_dir/.build-tools/runtime"

node_version="v24.18.0"

mkdir -p "$download_dir" "$runtime_dir"

fetch_checked() {
    url=$1
    destination=$2
    expected_hash=$3

    if [ ! -f "$destination" ]; then
        curl --fail --location --retry 3 "$url" --output "$destination"
    fi

    actual_hash=$(shasum -a 256 "$destination" | awk '{ print $1 }')
    if [ "$actual_hash" != "$expected_hash" ]; then
        echo "Checksum verification failed for $destination" >&2
        exit 1
    fi
}

fetch_checked \
    "https://nodejs.org/dist/$node_version/node-$node_version-darwin-arm64.tar.gz" \
    "$download_dir/node-arm64.tar.gz" \
    "e1a97e14c99c803e96c7339403282ea05a499c32f8d83defe9ef5ec66f979ed1"
fetch_checked \
    "https://nodejs.org/dist/$node_version/node-$node_version-darwin-x64.tar.gz" \
    "$download_dir/node-x86_64.tar.gz" \
    "dfd0dbd3e721503434df7b7205e719f61b3a3a31b2bcf9729b8b91fea240f080"
tar -xOf "$download_dir/node-arm64.tar.gz" \
    "node-$node_version-darwin-arm64/bin/node" >"$runtime_dir/node-arm64"
tar -xOf "$download_dir/node-x86_64.tar.gz" \
    "node-$node_version-darwin-x64/bin/node" >"$runtime_dir/node-x86_64"
tar -xOf "$download_dir/node-arm64.tar.gz" \
    "node-$node_version-darwin-arm64/LICENSE" >"$runtime_dir/node-LICENSE"

chmod +x \
    "$runtime_dir/node-arm64" \
    "$runtime_dir/node-x86_64"

lipo -create \
    "$runtime_dir/node-arm64" \
    "$runtime_dir/node-x86_64" \
    -output "$runtime_dir/node"
chmod +x "$runtime_dir/node"

"$script_dir/build-ffmpeg-runtime.sh" >/dev/null

for universal_binary in \
    "$runtime_dir/node"
do
    lipo "$universal_binary" -verify_arch arm64 x86_64
done

echo "$runtime_dir"
