#!/usr/bin/env bash
# Debug APK'yı bağlı telefona kurar ve yerel relay'e köprü kurar.
#
#   ./scripts/install-apk.sh            # derle + kur
#   ./scripts/install-apk.sh --no-build # sadece kur
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/env.sh" >/dev/null

APK="$ROOT/apps/mobile/build/app/outputs/flutter-apk/app-debug.apk"

if [[ ! -f "$APK" || "${1:-}" != "--no-build" ]]; then
  echo "== APK derleniyor =="
  (cd "$ROOT/apps/mobile" && flutter build apk --debug)
fi

if [[ ! -f "$APK" ]]; then
  echo "HATA: APK bulunamadı: $APK"
  exit 1
fi

if ! adb get-state >/dev/null 2>&1; then
  echo "HATA: bağlı cihaz yok. USB hata ayıklamayı aç ve kabloyu tak."
  adb devices
  exit 1
fi

echo "== Yerel relay köprüsü (adb reverse) =="
adb reverse tcp:7777 tcp:7777

echo "== Kuruluyor =="
adb install -r "$APK"

echo
echo "Tamam. Uygulamayı telefondan aç."
echo "Relay çalışmıyorsa: ./scripts/relay-start.sh"
