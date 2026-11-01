#!/usr/bin/env bash
# Android emülatörünü (AVD) oluşturur ve başlatır.
#
#   ./scripts/emulator-start.sh            # pencereli
#   ./scripts/emulator-start.sh --headless # pencere yok (otomasyon)
#
# Kapatmak için: adb emu kill
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/env.sh" >/dev/null

AVD_NAME="sosyal_api36"
IMAGE="system-images;android-36;google_apis;x86_64"
DEVICE="pixel_6"

if ! avdmanager list avd 2>/dev/null | grep -q "Name: $AVD_NAME"; then
  echo "== AVD oluşturuluyor: $AVD_NAME =="
  if [[ ! -d "$ANDROID_HOME/system-images/android-36/google_apis/x86_64" ]]; then
    yes | sdkmanager --licenses >/dev/null 2>&1 || true
    sdkmanager "emulator" "$IMAGE"
  fi
  echo no | avdmanager create avd -n "$AVD_NAME" -k "$IMAGE" -d "$DEVICE"
fi

if adb devices | grep -q "emulator-"; then
  echo "Zaten çalışan bir emülatör var:"
  adb devices | grep emulator-
  exit 0
fi

ARGS=(-avd "$AVD_NAME" -no-snapshot-save -no-boot-anim -gpu auto)
if [[ "${1:-}" == "--headless" ]]; then
  ARGS+=(-no-window -no-audio)
fi

echo "== Emülatör başlatılıyor (ilk açılış 1-2 dk sürebilir) =="
nohup "$ANDROID_HOME/emulator/emulator" "${ARGS[@]}" >"$ROOT/.data/emulator.log" 2>&1 &
echo $! >"$ROOT/.data/emulator.pid"

adb wait-for-device
until [[ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == "1" ]]; do
  sleep 2
done

echo "Emülatör hazır."
adb devices | grep emulator-

echo
echo "Yerel relay köprüsü:"
adb reverse tcp:7777 tcp:7777
