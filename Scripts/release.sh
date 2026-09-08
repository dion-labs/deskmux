#!/bin/zsh
set -euo pipefail
project_root="${0:A:h:h}"
cd "$project_root"
export DESKMUX_CONFIGURATION=release
Scripts/build-app.sh
mkdir -p dist
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' .build/DeskMux.app/Contents/Info.plist)
archive="dist/DeskMux-${version}-macOS-arm64.zip"
[[ ! -e "$archive" ]] || { print -u2 'Release archive already exists; preserve it or choose a new version.'; exit 1; }
codesign --verify --deep --strict .build/DeskMux.app
ditto -c -k --keepParent .build/DeskMux.app "$archive"
(cd dist && shasum -a 256 "${archive:t}") > dist/SHA256SUMS.txt
print -r -- "$archive"
