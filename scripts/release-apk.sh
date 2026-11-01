#!/usr/bin/env bash
# İmzalı release APK üretir ve depo köküne kopyalar.
#
# Gereksinim: android/key.properties (bkz. docs/dev-setup.md → Yayın).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "${ROOT}/scripts/env.sh" >/dev/null

RELAY="${RELAY_URL:-ws://192.168.1.109:7777}"
MEDIA="${MEDIA_URL:-http://192.168.1.109:8080}"

cd "${ROOT}/apps/mobile"
flutter build apk --release --split-per-abi \
  --dart-define=RELAY_URL="${RELAY}" \
  --dart-define=MEDIA_URL="${MEDIA}"

OUT="${ROOT}/apps/mobile/build/app/outputs/flutter-apk"
cp "${OUT}/app-arm64-v8a-release.apk"   "${ROOT}/verso-cafe-release-arm64.apk"
cp "${OUT}/app-armeabi-v7a-release.apk" "${ROOT}/verso-cafe-release-armv7.apk"

# Keystore yoksa uyar: imza debug anahtarla atılmış olabilir.
if [[ -f "${ROOT}/apps/mobile/android/key.properties" ]]; then
  "${ANDROID_HOME}/build-tools/36.0.0/apksigner" verify --print-certs \
    "${ROOT}/verso-cafe-release-arm64.apk" 2>/dev/null | grep "certificate DN" || true
else
  echo "UYARI: android/key.properties yok — APK debug anahtarla imzalandı!" >&2
fi
ls -la "${ROOT}"/sosyal-release-*.apk
