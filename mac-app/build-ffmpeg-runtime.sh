#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
download_dir="$repo_dir/.build-tools/distribution"
runtime_dir="$repo_dir/.build-tools/runtime"
source_root="$repo_dir/.build-tools/source-build"

ffmpeg_version="8.1.2"
lame_version="3.101"
marker="$runtime_dir/ffmpeg-$ffmpeg_version-lame-$lame_version"

mkdir -p "$download_dir" "$runtime_dir" "$source_root"

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
    "https://ffmpeg.org/releases/ffmpeg-$ffmpeg_version.tar.xz" \
    "$download_dir/ffmpeg-$ffmpeg_version.tar.xz" \
    "464beb5e7bf0c311e68b45ae2f04e9cc2af88851abb4082231742a74d97b524c"
fetch_checked \
    "https://downloads.sourceforge.net/project/lame/lame/$lame_version/lame-$lame_version.tar.gz" \
    "$download_dir/lame-$lame_version.tar.gz" \
    "7578af6eebd578b2bd64e468fac4ae1f03670a7e028166e67f855674b9b6aeac"

if [ -f "$marker" ]; then
    lipo "$runtime_dir/ffmpeg" -verify_arch arm64 x86_64
    lipo "$runtime_dir/ffprobe" -verify_arch arm64 x86_64
    echo "$runtime_dir"
    exit 0
fi

build_root=$(mktemp -d "$source_root/build.XXXXXX")
cleanup() {
    rm -rf "$build_root"
}
trap cleanup EXIT

jobs=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)

build_architecture() {
    architecture=$1
    host=$2
    architecture_root="$build_root/$architecture"
    lame_source="$architecture_root/lame-$lame_version"
    lame_prefix="$architecture_root/lame-prefix"
    ffmpeg_source="$architecture_root/ffmpeg-$ffmpeg_version"
    ffmpeg_prefix="$architecture_root/ffmpeg-prefix"
    common_flags="-arch $architecture -mmacosx-version-min=13.0 -O2"

    mkdir -p "$architecture_root"
    tar -xzf "$download_dir/lame-$lame_version.tar.gz" -C "$architecture_root"
    tar -xJf "$download_dir/ffmpeg-$ffmpeg_version.tar.xz" -C "$architecture_root"

    (
        cd "$lame_source"
        ./configure \
            --prefix="$lame_prefix" \
            --host="$host" \
            --disable-shared \
            --enable-static \
            --disable-frontend \
            --disable-decoder \
            --disable-analyzer-hooks \
            CFLAGS="$common_flags" \
            LDFLAGS="-arch $architecture -mmacosx-version-min=13.0"
        make -j"$jobs"
        make install
    )

    (
        cd "$ffmpeg_source"
        PKG_CONFIG_PATH="$lame_prefix/lib/pkgconfig" \
            ./configure \
            --prefix="$ffmpeg_prefix" \
            --target-os=darwin \
            --arch="$architecture" \
            --cc=clang \
            --disable-autodetect \
            --disable-shared \
            --enable-static \
            --disable-doc \
            --disable-debug \
            --disable-ffplay \
            --disable-x86asm \
            --enable-ffmpeg \
            --enable-ffprobe \
            --enable-libmp3lame \
            --enable-audiotoolbox \
            --enable-videotoolbox \
            --enable-securetransport \
            --extra-cflags="$common_flags -I$lame_prefix/include" \
            --extra-ldflags="-arch $architecture -mmacosx-version-min=13.0 -L$lame_prefix/lib"
        make -j"$jobs"
        make install
    )

    cp "$ffmpeg_prefix/bin/ffmpeg" "$runtime_dir/ffmpeg-$architecture"
    cp "$ffmpeg_prefix/bin/ffprobe" "$runtime_dir/ffprobe-$architecture"
}

build_architecture arm64 arm-apple-darwin
build_architecture x86_64 x86_64-apple-darwin

lipo -create \
    "$runtime_dir/ffmpeg-arm64" \
    "$runtime_dir/ffmpeg-x86_64" \
    -output "$runtime_dir/ffmpeg"
lipo -create \
    "$runtime_dir/ffprobe-arm64" \
    "$runtime_dir/ffprobe-x86_64" \
    -output "$runtime_dir/ffprobe"
chmod +x "$runtime_dir/ffmpeg" "$runtime_dir/ffprobe"

cp "$build_root/arm64/ffmpeg-$ffmpeg_version/COPYING.LGPLv2.1" \
    "$runtime_dir/ffmpeg-LICENSE-LGPLv2.1"
cp "$build_root/arm64/ffmpeg-$ffmpeg_version/COPYING.LGPLv3" \
    "$runtime_dir/ffmpeg-LICENSE-LGPLv3"
cp "$build_root/arm64/lame-$lame_version/COPYING" \
    "$runtime_dir/lame-LICENSE"

lipo "$runtime_dir/ffmpeg" -verify_arch arm64 x86_64
lipo "$runtime_dir/ffprobe" -verify_arch arm64 x86_64

if "$runtime_dir/ffmpeg" -version 2>&1 | grep -q -- "--enable-nonfree"; then
    echo "Refusing to package a non-redistributable ffmpeg build." >&2
    exit 1
fi
if ! "$runtime_dir/ffmpeg" -hide_banner -encoders 2>/dev/null |
    grep -q "libmp3lame"
then
    echo "The redistributable ffmpeg build is missing MP3 support." >&2
    exit 1
fi

touch "$marker"
echo "$runtime_dir"
