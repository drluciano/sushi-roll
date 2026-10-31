#!/usr/bin/env bash
# Generates the native platform folders (ios/, windows/) with `flutter create`
# and applies Sushi Roll's settings to them. Safe to run repeatedly: existing
# files are left alone, and the patches are idempotent.
set -euo pipefail
cd "$(dirname "$0")/.."

flutter create --org com.drluciano --project-name sushi_roll \
  --platforms ios,windows --no-pub . >/dev/null

# flutter create drops a counter-app smoke test that doesn't apply to us.
if [ -f test/widget_test.dart ] && grep -q "MyApp" test/widget_test.dart; then
  rm test/widget_test.dart
fi

# pub get writes ios/Podfile (needed for the deployment-target patch).
flutter pub get >/dev/null
python3 tool/patch_platforms.py
# If pub get didn't create the Podfile, let a config-only build do it (macOS
# only), then patch again so CocoaPods sees the right minimum iOS version.
if [ "$(uname)" = "Darwin" ] && [ ! -f ios/Podfile ]; then
  flutter build ios --config-only --no-codesign >/dev/null 2>&1 || true
  python3 tool/patch_platforms.py
fi
echo "Platform folders ready."
