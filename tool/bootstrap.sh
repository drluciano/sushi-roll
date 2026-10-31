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

python3 tool/patch_platforms.py
echo "Platform folders ready."
