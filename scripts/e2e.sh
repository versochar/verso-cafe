#!/usr/bin/env bash
# Faz 1 uçtan uca testi: relay + emülatör/cihaz + integration test.
#
#   ./scripts/e2e.sh
#
# Gereksinim: çalışan bir emülatör veya USB ile bağlı cihaz.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/env.sh" >/dev/null

echo "== Relay =="
"$ROOT/scripts/relay-start.sh"

echo "== Cihaz =="
if ! adb get-state >/dev/null 2>&1; then
  echo "HATA: cihaz yok. Önce ./scripts/emulator-start.sh veya telefonu bağla."
  exit 1
fi
adb devices | grep -E "device$" | head -1

echo "== Relay köprüsü =="
adb reverse tcp:7777 tcp:7777

echo "== Integration test =="
cd "$ROOT/apps/mobile"
flutter test integration_test/phase1_test.dart

echo
echo "Uçtan uca test geçti."
