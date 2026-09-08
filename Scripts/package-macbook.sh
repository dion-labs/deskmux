#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
source_app="$project_root/.build/DeskMux.app"
user_name="$(id -un)"
user_directory="$(dscl . -read "/Users/$user_name" NFSHomeDirectory | awk '{print $2}')"
destination="${1:-$user_directory/Downloads/DeskMux-MacBook.zip}"

if [[ "${DESKMUX_SKIP_BUILD:-0}" != "1" ]]; then
  "$project_root/Scripts/build-app.sh" >/dev/null
fi
codesign --verify --deep --strict "$source_app"
ditto -c -k --sequesterRsrc --keepParent "$source_app" "$destination"

if [[ "${DESKMUX_SKIP_BUILD:-0}" != "1" ]]; then
  mv "$source_app" "$project_root/.build/DeskMux-staging-$(date -u +%Y%m%d%H%M%S).retired"
fi

echo "$destination"
