#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

destination="$1"
cache="$2"
version=1.27.0
asset="deskflow-$version-macos-arm64.dmg"
digest=dd21e79e566314394214906d3338c505d337af536fc580c022ee3fadffad0c97
mkdir -p "$cache"
image="$cache/$asset"
temporary="$(mktemp -d)"
mount="$temporary/image"
cleanup() {
    hdiutil detach "$mount" -quiet 2>/dev/null || true
    rm -rf "$temporary"
}
trap cleanup EXIT

verify() {
    [[ "$(shasum -a 256 "$1" | awk '{print $1}')" == "$digest" ]]
}
if [[ ! -f "$image" ]] || ! verify "$image"; then
    curl --fail --location --retry 3 --output "$temporary/$asset" \
        "https://github.com/deskflow/deskflow/releases/download/v$version/$asset"
    verify "$temporary/$asset"
    mv "$temporary/$asset" "$image"
fi

hdiutil attach -nobrowse -readonly -mountpoint "$mount" "$image" >/dev/null
source="$mount/Deskflow.app"
test -x "$source/Contents/MacOS/deskflow-core"
codesign --verify --deep --strict "$source"
ditto "$source" "$destination"
