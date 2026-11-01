#!/usr/bin/env bash
# İmzalı release APK'ları üretir ve depo köküne kopyalar.
#
# Gereksinim: android/key.properties (bkz. docs/dev-setup.md → Yayın).
#
# Hedef adresler (relay/medya/hesap) APK'nın içine gömülür:
#   1) açıkça verilen RELAY_URL / MEDIA_URL / ACCOUNT_URL ortam değişkenleri,
#   2) yoksa .data/public-urls.env (scripts/tunnel-start.sh üretir),
#   3) o da yoksa yerel geliştirme varsayılanları.
# Yayınlanmadan önce hedeflerin gerçekten erişilebilir olduğu denenir; APK
# ölü bir adrese bakıyorsa derleme durur (SKIP_TARGET_CHECK=1 ile geçilebilir).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "${ROOT}/scripts/env.sh" >/dev/null

if [[ ( -z "${RELAY_URL:-}" || -z "${MEDIA_URL:-}" || -z "${ACCOUNT_URL:-}" ) && -f "${ROOT}/.data/public-urls.env" ]]; then
  # shellcheck disable=SC1091
  source "${ROOT}/.data/public-urls.env"
  echo "Hedefler .data/public-urls.env'den alındı."
fi

RELAY="${RELAY_URL:-ws://192.168.1.109:7777}"
MEDIA="${MEDIA_URL:-http://192.168.1.109:8080}"
ACCOUNT="${ACCOUNT_URL:-http://192.168.1.109:8090}"

if [[ "${SKIP_TARGET_CHECK:-0}" != 1 ]]; then
  echo "Hedefler deneniyor: relay=${RELAY} medya=${MEDIA} hesap=${ACCOUNT}"
  media_probe="${MEDIA}/healthz"
  account_probe="${ACCOUNT}/healthz"
  relay_probe="${RELAY#wss:}"; relay_probe="https:${relay_probe#ws:}/"
  if ! curl -sf --max-time 15 "$media_probe" >/dev/null; then
    echo "HATA: medya sunucusuna ulaşılamadı: $media_probe" >&2
    echo "      (kasten kapalıysa: SKIP_TARGET_CHECK=1 ./scripts/release-apk.sh)" >&2
    exit 1
  fi
  if ! curl -sf --max-time 15 "$account_probe" >/dev/null; then
    echo "HATA: hesap sunucusuna ulaşılamadı: $account_probe" >&2
    exit 1
  fi
  if ! curl -sf --max-time 15 -o /dev/null "$relay_probe"; then
    echo "HATA: relay'e ulaşılamadı: $relay_probe" >&2
    exit 1
  fi
  echo "  üç hedef de erişilebilir."
fi

cd "${ROOT}/apps/mobile"
flutter build apk --release --split-per-abi \
  --dart-define=RELAY_URL="${RELAY}" \
  --dart-define=MEDIA_URL="${MEDIA}" \
  --dart-define=ACCOUNT_URL="${ACCOUNT}"

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

ls -la "${ROOT}"/verso-cafe-release-*.apk
