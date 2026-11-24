#!/usr/bin/env bash
# Builds OnePercentTestApp.app for docs/MANUAL-TEST.md and zips it the way OnePercent expects.
#
#   TestApp/make-app.sh VERSION BUILD OWNER/REPO [--adhoc] [--notarize PROFILE] [--padding MB] [--min-macos VERSION]
#
#   VERSION BUILD   CFBundleShortVersionString and CFBundleVersion (for example 1.1 2)
#   OWNER/REPO      the public test repository the app checks
#   --adhoc         sign ad-hoc instead of with Developer ID (case 10: wrong signer)
#   --notarize P    submit to Apple's notary service with the notarytool keychain profile P, then staple
#   --padding MB    add MB of random bytes so the download takes a while (cases 5 and 6)
#   --min-macos V   LSMinimumSystemVersion (default 14.0) — case 14: a version this Mac cannot open
#
# Output: TestApp/dist/VERSION/OnePercentTestApp.app and TestApp/dist/VERSION/OnePercentTestApp_VERSION.zip
#
# 2026-11-22: 오너 결정 A(전용 시험 앱). 개인 값은 이 파일에 적지 않는다 — 팀 ID 는 키체인의 "Developer ID Application" 이름에서
# 읽고, 저장소는 인자로 받는다. 문구 묶음(OnePercent_OnePercent.bundle)을 Contents/Resources 에 복사한다(README "알아 둘 것").
set -euo pipefail
cd "$(dirname "$0")"

[ $# -ge 3 ] || { sed -n '3,13p' "$0"; exit 2; }
VERSION="$1"; BUILD="$2"; REPOSITORY="$3"; shift 3
ADHOC=0; PROFILE=""; PADDING=0; MIN_MACOS=14.0
while [ $# -gt 0 ]; do
  case "$1" in
    --adhoc) ADHOC=1; shift ;;
    --notarize) PROFILE="${2:?--notarize needs a keychain profile name}"; shift 2 ;;
    --padding) PADDING="${2:?--padding needs a size in MB}"; shift 2 ;;
    --min-macos) MIN_MACOS="${2:?--min-macos needs a macOS version}"; shift 2 ;;
    *) echo "unknown option $1"; exit 2 ;;
  esac
done
# 2026-11-22 (#21): 무엇이든 지우기 전에 값을 검사한다. VERSION 은 rm -rf 경로(dist/$VERSION)에 들어간다 —
# 예전엔 검사가 없어 '../..' 한 번이면 저장소 폴더가 지워질 수 있었다.
version_pattern='^[0-9][0-9A-Za-z._-]*$'
build_pattern='^[0-9]+(\.[0-9]+){0,3}$'
number_pattern='^[0-9]+$'
[[ $VERSION =~ $version_pattern && $VERSION != *..* ]] || { echo "✗ VERSION must look like 1.2 or 2026.11.17 (got: $VERSION)"; exit 2; }
[[ $BUILD =~ $build_pattern ]] || { echo "✗ BUILD must be a build number such as 2 or 1.10 (got: $BUILD)"; exit 2; }
[[ $PADDING =~ $number_pattern ]] || { echo "✗ --padding needs a whole number of MB (got: $PADDING)"; exit 2; }
[[ $MIN_MACOS =~ $build_pattern ]] || { echo "✗ --min-macos must look like 14.0 (got: $MIN_MACOS)"; exit 2; }
NAME=OnePercentTestApp
BUNDLE_ID="${BUNDLE_ID:-com.example.OnePercentTestApp}"

IDENTITY="$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/ {print $2; exit}')"
[ -n "$IDENTITY" ] || { echo "✗ No Developer ID Application identity in the keychain"; exit 1; }
TEAM="$(printf '%s' "$IDENTITY" | sed -E 's/.*\(([A-Z0-9]{10})\)$/\1/')"

echo "▸ Building (release)…"
swift build -c release --product "$NAME" >/dev/null
BIN="$(swift build -c release --show-bin-path)"

OUT="dist/$VERSION"
APP="$OUT/$NAME.app"
[ "$(dirname "$OUT")" = dist ] || { echo "✗ refusing to replace $OUT (not directly inside dist/)"; exit 1; }
rm -rf "$OUT"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/$NAME" "$APP/Contents/MacOS/$NAME"
cp -R "$BIN/OnePercent_OnePercent.bundle" "$APP/Contents/Resources/"
# Random, so the ZIP cannot shrink it.
[ "$PADDING" -gt 0 ] && dd if=/dev/urandom of="$APP/Contents/Resources/padding.bin" bs=1048576 count="$PADDING" 2>/dev/null

LANGUAGES=(cs da de el en es fi fil fr hu id it ja ko ms nb nl pl pt-BR pt-PT ro ru sv th tr uk vi zh-Hans zh-Hant)
PLIST="$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy \
  -c "Add :CFBundleIdentifier string $BUNDLE_ID" \
  -c "Add :CFBundleName string $NAME" \
  -c "Add :CFBundleExecutable string $NAME" \
  -c "Add :CFBundlePackageType string APPL" \
  -c "Add :CFBundleShortVersionString string $VERSION" \
  -c "Add :CFBundleVersion string $BUILD" \
  -c "Add :CFBundleDevelopmentRegion string en" \
  -c "Add :LSMinimumSystemVersion string $MIN_MACOS" \
  -c "Add :NSPrincipalClass string NSApplication" \
  -c "Add :NSHighResolutionCapable bool true" \
  -c "Add :OPRepository string $REPOSITORY" \
  -c "Add :OPTeamIdentifier string $TEAM" \
  -c "Add :CFBundleLocalizations array" \
  "$PLIST" >/dev/null
for language in "${LANGUAGES[@]}"; do /usr/libexec/PlistBuddy -c "Add :CFBundleLocalizations: string $language" "$PLIST"; done

if [ "$ADHOC" = 1 ]; then
  echo "▸ Signing ad-hoc (wrong signer on purpose)…"
  codesign --force --sign - "$APP"
else
  echo "▸ Signing with Developer ID (hardened runtime, secure timestamp)…"
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
fi
codesign --verify --deep --strict "$APP"

if [ -n "$PROFILE" ]; then
  echo "▸ Notarizing with profile $PROFILE (waits for Apple)…"
  ditto -c -k --norsrc --keepParent "$APP" "$OUT/notary.zip"
  xcrun notarytool submit "$OUT/notary.zip" --keychain-profile "$PROFILE" --wait
  rm -f "$OUT/notary.zip"
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
fi

ditto -c -k --norsrc --keepParent "$APP" "$OUT/${NAME}_$VERSION.zip"
echo "✓ $APP"
echo "✓ $OUT/${NAME}_$VERSION.zip ($(stat -f %z "$OUT/${NAME}_$VERSION.zip") bytes)"
codesign -dv "$APP" 2>&1 | grep -E "^(Identifier|Authority|TeamIdentifier|Timestamp)=" | head -4 || true
