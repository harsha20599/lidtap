#!/bin/bash
# Exercise real Bundle.main language selection, interpolation and stable identifiers.
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/test.sh localization
APP="build/LocalizationTests.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp build/LidTapTests "$APP/Contents/MacOS/LocalizationTests"
cp Resources/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleExecutable LocalizationTests' "$APP/Contents/Info.plist"
cp -R Resources/*.lproj "$APP/Contents/Resources/"
for language in en zh-Hans; do
  LIDTAP_TEST_LANGUAGE="$language" "$APP/Contents/MacOS/LocalizationTests" localization -AppleLanguages "($language)"
done
