#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
dist_dir="$repo_dir/dist"
app_name="FetchDeck"
app_bundle="$dist_dir/$app_name.app"
dmg_path="$dist_dir/$app_name.dmg"
notary_profile=${NOTARY_PROFILE:-fetchdeck}
mode=${1:-distribution}

if [ "$mode" = "--local" ]; then
    signing_identity="-"
else
    signing_identity=${DEVELOPER_ID_APPLICATION:-}
    if [ -z "$signing_identity" ]; then
        signing_identity=$(
            security find-identity -v -p codesigning |
                sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' |
                head -1
        )
    fi
    if [ -z "$signing_identity" ]; then
        echo "No Developer ID Application identity is installed." >&2
        echo "Install one in Xcode, then rerun this script." >&2
        exit 1
    fi
fi

SIGNING_IDENTITY="$signing_identity" "$script_dir/build-app.sh"

staging_dir=$(mktemp -d "$repo_dir/.build-tools/dmg.XXXXXX")
cleanup() {
    rm -rf "$staging_dir"
}
trap cleanup EXIT

cp -R "$app_bundle" "$staging_dir/"
ln -s /Applications "$staging_dir/Applications"

hdiutil create \
    -volname "$app_name" \
    -srcfolder "$staging_dir" \
    -format UDZO \
    -ov \
    "$dmg_path"

if [ "$mode" = "--local" ]; then
    echo "Created local test DMG (not notarized): $dmg_path"
    exit 0
fi

codesign \
    --force \
    --timestamp \
    --sign "$signing_identity" \
    "$dmg_path"
xcrun notarytool submit \
    "$dmg_path" \
    --keychain-profile "$notary_profile" \
    --wait
xcrun stapler staple "$dmg_path"
xcrun stapler validate "$dmg_path"

codesign --verify --deep --strict --verbose=2 "$app_bundle"
spctl --assess --type execute --verbose=2 "$app_bundle"
spctl \
    --assess \
    --type open \
    --context context:primary-signature \
    --verbose=2 \
    "$dmg_path"

echo "$dmg_path"
