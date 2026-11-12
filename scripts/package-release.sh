#!/bin/bash
# Build MacDroid.app + the macdroid CLI (Release), sign with Developer ID, notarize with
# Apple and staple the ticket — the app opens with a normal double-click, no Gatekeeper warning.
#   ./scripts/package-release.sh            → dist/MacDroid-<version>-macos-arm64.zip, dist/macdroid-cli-<version>-macos-arm64.zip
#   ./scripts/package-release.sh --publish  → also creates the GitHub release v<version> with those files (needs gh)
#
# Notarization needs a keychain profile (app-specific password, team 4N5S7KDZ56):
#   xcrun notarytool store-credentials wonjin --apple-id <apple-id> --team-id 4N5S7KDZ56
# Override the profile with NOTARY_PROFILE=<name> if needed.
#
# 변경 전: 자체 서명 빌드를 zip으로만 배포 — Gatekeeper 경고(우클릭 → 열기) 필요.
# 변경 후: Developer ID 재서명 + Apple 공증 + 스테이플 후 배포.
# 이유: 대장님 요청으로 정식 공증 릴리즈 전환. vendor 바이너리(adb/scrcpy/aapt2/dylib)는
#   postBuildScript 단계에서 bundle에 들어가 Xcode 서명 각인 이후 추가되고 adhoc 서명이라
#   공증이 거부된다 — 그래서 Mach-O 전부 재서명 후 outer bundle을 마지막에 다시 봉인한다.
# 영향: Release 배포 아티팩트 전부. Debug 로컬 빌드는 그대로.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="$(awk -F'"' '/MARKETING_VERSION:/ {print $2; exit}' project.yml)"
[[ -n "$VERSION" ]] || { echo "MARKETING_VERSION not found in project.yml" >&2; exit 1; }
NOTARY_PROFILE="${NOTARY_PROFILE:-wonjin}"
IDENTITY="Developer ID Application: Wonjin Choi (4N5S7KDZ56)"
DERIVED="$ROOT/build/DerivedData"
PRODUCTS="$DERIVED/Build/Products/Release"
DIST="$ROOT/dist"
APP="$PRODUCTS/MacDroid.app"
CLI="$PRODUCTS/macdroid"

xcodegen generate >/dev/null
for scheme in MacDroid macdroid; do
  xcodebuild -project MacDroid.xcodeproj -scheme "$scheme" -configuration Release build \
    -derivedDataPath "$DERIVED" -quiet
done

# ── Re-sign pass ─────────────────────────────────────────────────────────────
# Apple 공증은 nested 실행 파일에도 hardened runtime을 요구한다(실측 거부: adb/aapt2/scrcpy가
# 'does not have the hardened runtime enabled'). Mach-O 전부 runtime+timestamp로 재서명하고
# outer .app과 bare CLI는 마지막에 다시 봉인한다. dylib의 runtime 플래그는 무해하다.
while IFS= read -r bin; do
  file "$bin" | grep -q "Mach-O" || continue
  echo "  signing $bin"
  codesign --force --sign "$IDENTITY" --options runtime --timestamp "$bin"
done < <(find "$APP/Contents/Resources" -type f)
codesign --force --sign "$IDENTITY" --options runtime --timestamp "$APP"
codesign --force --sign "$IDENTITY" --options runtime --timestamp "$CLI"
codesign --verify --deep --strict "$APP"
echo "signature OK"

rm -rf "$DIST"
mkdir -p "$DIST"
APP_ZIP="$DIST/MacDroid-$VERSION-macos-arm64.zip"
CLI_ZIP="$DIST/macdroid-cli-$VERSION-macos-arm64.zip"

# ── Notarize the app ─────────────────────────────────────────────────────────
# Submit the unstapled zip first (stapler needs an accepted submission for this
# exact CDHash), then staple the .app and zip THAT — the ticket travels inside.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$DIST/.notary-app.zip"
app_out="$(xcrun notarytool submit "$DIST/.notary-app.zip" --keychain-profile "$NOTARY_PROFILE" --wait)"
echo "$app_out"
grep -q "status: Accepted" <<<"$app_out" || { echo "app notarization rejected" >&2; exit 1; }
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$APP_ZIP"
rm -f "$DIST/.notary-app.zip"

# ── Notarize the CLI zip (bare binary — no stapling possible, online ticket) ─
STAGE="$(mktemp -d)"
cp "$CLI" "$STAGE/macdroid"
ditto -c -k "$STAGE" "$CLI_ZIP"
rm -rf "$STAGE"
cli_out="$(xcrun notarytool submit "$CLI_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait)"
echo "$cli_out"
grep -q "status: Accepted" <<<"$cli_out" || { echo "cli notarization rejected" >&2; exit 1; }

(cd "$DIST" && shasum -a 256 ./*.zip > SHA256SUMS.txt)

echo "MacDroid $VERSION (notarized, profile: $NOTARY_PROFILE)"
ls -lh "$DIST"
cat "$DIST/SHA256SUMS.txt"

if [[ "${1:-}" == "--publish" ]]; then
  NOTES="$ROOT/scripts/release-notes.md"
  [[ -f "$NOTES" ]] || { echo "missing $NOTES" >&2; exit 1; }
  sed "s/<version>/$VERSION/g" "$NOTES" > "$DIST/release-notes.md"
  gh release create "v$VERSION" "$APP_ZIP" "$CLI_ZIP" "$DIST/SHA256SUMS.txt" \
    --title "MacDroid $VERSION" --notes-file "$DIST/release-notes.md"
fi
