#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
app_bundle="$project_root/.build/DeskMux.app"
contents="$app_bundle/Contents"
macos_dir="$contents/MacOS"
helpers_dir="$contents/Helpers"
launch_agents_dir="$contents/Library/LaunchAgents"
agent_bundle="$contents/Library/LoginItems/DeskMux Agent.app"
agent_contents="$agent_bundle/Contents"
agent_macos_dir="$agent_contents/MacOS"

cd "$project_root"
build_configuration="${DESKMUX_CONFIGURATION:-debug}"
swift build -c "$build_configuration" --product DeskMux
swift build -c "$build_configuration" --product DeskMuxRelauncher
swift build -c "$build_configuration" --product DeskMuxService
if [[ -d "$app_bundle" ]]; then
  mv "$app_bundle" "$project_root/.build/DeskMux-prebuild-$(date -u +%Y%m%d%H%M%S).retired"
fi
mkdir -p "$macos_dir" "$helpers_dir" "$launch_agents_dir" "$agent_macos_dir"
cp "$project_root/.build/$build_configuration/DeskMux" "$macos_dir/DeskMux"
cp "$project_root/.build/$build_configuration/DeskMuxRelauncher" "$helpers_dir/DeskMuxRelauncher"
cp "$project_root/.build/$build_configuration/DeskMuxService" "$agent_macos_dir/DeskMuxService"
mkdir -p "$contents/Resources"
cp "$project_root/App/Resources/DeskMux.icns" "$contents/Resources/DeskMux.icns"
cp "$project_root/App/Agent-Info.plist" "$agent_contents/Info.plist"
cp "$project_root/App/dev.deskmux.agent.plist" "$launch_agents_dir/dev.deskmux.agent.plist"
cp "$project_root/App/Info.plist" "$contents/Info.plist"
build_number="${DESKMUX_BUILD_NUMBER:-$(date -u +%Y%m%d%H%M%S)}"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" "$contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" "$agent_contents/Info.plist"
if [[ -n "${DESKMUX_STUDIO_MOUSE_HOST:-}" && -n "${DESKMUX_MACBOOK_MOUSE_HOST:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Add :DeskMuxLogitechHosts dict" "$contents/Info.plist"
  /usr/libexec/PlistBuddy -c \
    "Add :DeskMuxLogitechHosts:studio integer $DESKMUX_STUDIO_MOUSE_HOST" \
    "$contents/Info.plist"
  /usr/libexec/PlistBuddy -c \
    "Add :DeskMuxLogitechHosts:macbook integer $DESKMUX_MACBOOK_MOUSE_HOST" \
    "$contents/Info.plist"
fi
if [[ -n "${DESKMUX_STUDIO_MOUSE_EDGE:-}" && -n "${DESKMUX_MACBOOK_MOUSE_EDGE:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Add :DeskMuxLogitechEdges dict" "$contents/Info.plist"
  /usr/libexec/PlistBuddy -c \
    "Add :DeskMuxLogitechEdges:studio string $DESKMUX_STUDIO_MOUSE_EDGE" \
    "$contents/Info.plist"
  /usr/libexec/PlistBuddy -c \
    "Add :DeskMuxLogitechEdges:macbook string $DESKMUX_MACBOOK_MOUSE_EDGE" \
    "$contents/Info.plist"
  /usr/libexec/PlistBuddy -c \
    "Add :DeskMuxLogitechEdgeEnabled bool ${DESKMUX_MOUSE_EDGE_ENABLED:-false}" \
    "$contents/Info.plist"
  /usr/libexec/PlistBuddy -c \
    "Add :DeskMuxLogitechEdgeDwellMilliseconds integer ${DESKMUX_MOUSE_EDGE_DWELL_MS:-200}" \
    "$contents/Info.plist"
fi

signing_identity="${DESKMUX_SIGNING_IDENTITY:-}"
if [[ -z "$signing_identity" ]]; then
  available_identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"
  signing_identity="$(print -r -- "$available_identities" | awk -F'"' '/Developer ID Application:/ { print $2; exit }')"
  if [[ -z "$signing_identity" ]]; then
    signing_identity="$(print -r -- "$available_identities" | awk -F'"' '/Apple Development:/ { print $2; exit }')"
  fi
fi

if [[ -n "$signing_identity" ]]; then
  codesign --force --options runtime --sign "$signing_identity" \
    --identifier dev.deskmux.relauncher "$helpers_dir/DeskMuxRelauncher"
  codesign --force --options runtime --sign "$signing_identity" \
    --identifier dev.deskmux.agent "$agent_bundle"
  codesign --force --options runtime --sign "$signing_identity" \
    --identifier dev.deskmux.app "$app_bundle"
  echo "Signed with a stable ${signing_identity%%:*} identity." >&2
else
  codesign --force --sign - --identifier dev.deskmux.relauncher \
    "$helpers_dir/DeskMuxRelauncher"
  codesign --force --sign - --identifier dev.deskmux.agent "$agent_bundle"
  codesign --force --sign - --identifier dev.deskmux.app "$app_bundle"
  echo "Warning: no stable signing identity found; privacy grants may reset after rebuilds." >&2
fi
echo "$app_bundle"
