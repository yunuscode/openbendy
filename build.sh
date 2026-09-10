#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h}"
openbendy_build_dir="${OPENBENDY_BUILD_DIR:-${TMPDIR:-/tmp}/openbendy-build}"
action="${1:-build}"
if [[ "$action" != build && "$action" != test ]]; then
  print -u2 'Usage: ./build.sh [build|test]'
  exit 2
fi
configuration=Release
if [[ "$action" == test ]]; then configuration=Debug; fi
signing_args=()
if [[ -n "${OPENBENDY_SIGNING_IDENTITY:-}" ]]; then
  signing_args+=("CODE_SIGN_IDENTITY=$OPENBENDY_SIGNING_IDENTITY")
fi
xcodebuild -project "$project_dir/OpenBendy.xcodeproj" -scheme OpenBendy \
  -configuration "$configuration" -destination 'platform=macOS' \
  -derivedDataPath "$openbendy_build_dir" "${signing_args[@]}" "$action"
print "App: $openbendy_build_dir/Build/Products/$configuration/OpenBendy.app"
