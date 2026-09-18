#!/bin/sh
set -eu
repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
snapshot_tmp=$(mktemp -d)
trap 'rm -rf "$snapshot_tmp"' EXIT
cd "$repo_root"
xcrun swiftc -parse-as-library -target arm64-apple-macosx26.0 \
  ios/RecordingActivity/SwiftUIView.swift \
  ios/RecordingActivity/RecordingTimerView.swift \
  test/recording/native/render_activity_snapshot.swift \
  -o "$snapshot_tmp/render"
"$snapshot_tmp/render" "$snapshot_tmp/recording_activity.png"
if [ "${1:-}" = "--update" ]; then
  cp "$snapshot_tmp/recording_activity.png" test/recording/native/goldens/recording_activity.png
else
  cmp "$snapshot_tmp/recording_activity.png" test/recording/native/goldens/recording_activity.png
fi
