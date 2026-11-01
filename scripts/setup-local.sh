#!/usr/bin/env bash
# Yerel test ortamını kurar (idempotent). sudo gerektirmez.
set -euo pipefail

FLUTTER_VERSION="3.47.9"
CMDTOOLS_BUILD="16111833"
JDK_MAJOR="21"

HOME_DIR="$HOME"
FLUTTER_DIR="$HOME_DIR/flutter"
JDK_DIR="$HOME_DIR/.local/opt/jdk21"
SDK_DIR="$HOME_DIR/Android/Sdk"
DL="/tmp/opencode/dl"
mkdir -p "$DL"

echo "== Flutter =="
if [[ ! -x "$FLUTTER_DIR/bin/flutter" ]]; then
  curl -L -o "$DL/flutter.tar.xz" \
    "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
  tar xf "$DL/flutter.tar.xz" -C "$HOME_DIR"
else
  echo "zaten kurulu"
fi

echo "== JDK $JDK_MAJOR =="
if [[ ! -x "$JDK_DIR/bin/java" ]]; then
  curl -L -o "$DL/jdk.tar.gz" \
    "https://api.adoptium.net/v3/binary/latest/${JDK_MAJOR}/ga/linux/x64/jdk/hotspot/normal/eclipse?project=jdk"
  mkdir -p "$JDK_DIR"
  tar xzf "$DL/jdk.tar.gz" -C "$JDK_DIR" --strip-components=1
else
  echo "zaten kurulu"
fi

echo "== Android cmdline-tools =="
if [[ ! -x "$SDK_DIR/cmdline-tools/latest/bin/sdkmanager" ]]; then
  curl -L -o "$DL/cmdtools.zip" \
    "https://dl.google.com/android/repository/commandlinetools-linux-${CMDTOOLS_BUILD}_latest.zip"
  rm -rf "$DL/cmdtools" && mkdir -p "$DL/cmdtools" "$SDK_DIR/cmdline-tools/latest"
  unzip -q "$DL/cmdtools.zip" -d "$DL/cmdtools"
  mv "$DL/cmdtools/cmdline-tools/"* "$SDK_DIR/cmdline-tools/latest/"
else
  echo "zaten kurulu"
fi

echo "== Android SDK paketleri =="
source "$(dirname "$0")/env.sh" >/dev/null
yes | sdkmanager --licenses >/dev/null || true
sdkmanager "platform-tools" "platforms;android-36" "build-tools;36.0.0" >/dev/null

echo "== Yerel relay =="
if ! command -v nostr-rs-relay >/dev/null 2>&1; then
  cargo install nostr-rs-relay --locked
else
  echo "zaten kurulu"
fi

echo "== Flutter yapılandırması =="
flutter config --no-analytics >/dev/null || true
flutter config --android-sdk "$SDK_DIR" >/dev/null || true
flutter config --jdk-dir "$JDK_DIR" >/dev/null || true
flutter doctor

echo
echo "Kurulum tamam. 'source scripts/env.sh' ile ortamı yükle."
