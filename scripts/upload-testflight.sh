#!/usr/bin/env bash
# Upload an existing archive of Caffeine to TestFlight (default build/Caffeine.xcarchive)
# with the App Store Connect API key. The shared fleet script does the work; see
# ~/ios/release/testflight.sh for flags and credentials.
cd "$(dirname "$0")/.." || exit 1
exec "$HOME/ios/release/testflight.sh" --project Caffeine.xcodeproj --scheme Caffeine --upload-only "$@"
