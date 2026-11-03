#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
app_dir="$repo_root/iosApp"
output_dir="${1:-$repo_root/build/tvos-export}"
archive_path="$repo_root/build/SiloTV.xcarchive"

if [[ -z "${DEVELOPMENT_TEAM:-}" ]]; then
  echo "DEVELOPMENT_TEAM must contain the Apple Developer team identifier." >&2
  exit 2
fi

mkdir -p "$repo_root/build" "$output_dir"
cd "$app_dir"
xcodegen generate
xcodebuild \
  -project Silo.xcodeproj \
  -scheme SiloTV \
  -configuration Release \
  -destination 'generic/platform=tvOS' \
  -archivePath "$archive_path" \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  -allowProvisioningUpdates \
  clean archive
xcodebuild \
  -exportArchive \
  -archivePath "$archive_path" \
  -exportPath "$output_dir" \
  -exportOptionsPlist "$app_dir/ExportOptions-tvOS.plist" \
  -allowProvisioningUpdates

find "$output_dir" -maxdepth 1 -name '*.ipa' -print
