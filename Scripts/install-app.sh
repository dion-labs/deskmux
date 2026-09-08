#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
source_app="$project_root/.build/DeskMux.app"
user_name="$(id -un)"
user_directory="$(dscl . -read "/Users/$user_name" NFSHomeDirectory | awk '{print $2}')"
applications_directory="$user_directory/Applications"
installed_app="$applications_directory/DeskMux.app"

if [[ "${DESKMUX_SKIP_BUILD:-0}" != "1" ]]; then
  "$project_root/Scripts/build-app.sh" >/dev/null
fi

# `open` does not launch the newly installed bundle while an older DeskMux
# process is still alive. Quit it first so the menu app can migrate the bundled
# background agent and the reported app/agent versions cannot drift.
if pgrep -x DeskMux >/dev/null; then
  osascript -e 'tell application id "dev.deskmux.app" to quit' 2>/dev/null || true
  for attempt in {1..20}; do
    if ! pgrep -x DeskMux >/dev/null; then break; fi
    sleep 0.25
  done
  if pgrep -x DeskMux >/dev/null; then
    echo "DeskMux did not quit; installation stopped before replacing the running app." >&2
    exit 1
  fi
fi

mkdir -p "$applications_directory"
if [[ -d "$installed_app" ]]; then
  previous_app="$applications_directory/DeskMux-previous-$(date -u +%Y%m%d%H%M%S).retired"
  mv "$installed_app" "$previous_app"
fi
ditto "$source_app" "$installed_app"
codesign --verify --deep --strict "$installed_app"
mv "$source_app" "$project_root/.build/DeskMux-staging-$(date -u +%Y%m%d%H%M%S).retired"
open "$installed_app"
echo "$installed_app"
