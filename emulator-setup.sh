#!/usr/bin/env bash
# Sosyal — Android emülatör kurulumu (Linux, sudo'lu kendi bilgisayarın)
# Kullanım:  bash emulator-setup.sh
# Gerekir:  x86_64 CPU + KVM (/dev/kvm), ~4 GB boş yer, Java 17+
set -euo pipefail

SDK="$HOME/Android/Sdk"
TOOLS="$HOME/Android/cmdline-tools"
JDK="$HOME/.local/opt/jdk21"

echo "== 1/5 KVM kontrolü =="
if [[ ! -e /dev/kvm ]]; then
  echo "!! /dev/kvm yok. BIOS'ta sanallaştırmayı (VT-x/AMD-V) aç, sonra:"
  echo "   sudo apt install cpu-checker && kvm-ok"
  exit 1
fi
if [[ ! -r /dev/kvm || ! -w /dev/kvm ]]; then
  echo "!! /dev/kvm erişimi yok. Şunu çalıştır ve oturumu yeniden aç:"
  echo "   sudo usermod -aG kvm \$USER"
  exit 1
fi
echo "ok: /dev/kvm erişilebilir"

echo "== 2/5 Java =="
if command -v java >/dev/null && java -version 2>&1 | grep -qE '"(1[7-9]|2[0-9])'; then
  echo "ok: $(java -version 2>&1 | head -1)"
elif [[ -x "$JDK/bin/java" ]]; then
  export JAVA_HOME="$JDK"; echo "ok: yerel JDK 21 ($JDK)"
else
  echo "!! Java 17+ bulamadım. Örnek: sudo apt install openjdk-21-jdk"
  echo "   ya da Adoptium JDK 21'i $JDK altına kur."
  exit 1
fi

echo "== 3/5 Android command-line tools =="
if [[ ! -x "$TOOLS/latest/cmdline-tools/sdkmanager" ]]; then
  mkdir -p "$TOOLS"
  tmp=$(mktemp -d)
  curl -fL -o "$tmp/clt.zip" \
    https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip
  unzip -q "$tmp/clt.zip" -d "$tmp"
  mkdir -p "$TOOLS/latest"
  mv "$tmp/cmdline-tools" "$TOOLS/latest/cmdline-tools"
  rm -rf "$tmp"
fi
SDKM="$TOOLS/latest/cmdline-tools/sdkmanager"
yes | "$SDKM" --sdk_root="$SDK" --licenses >/dev/null 2>&1 || true
"$SDKM" --sdk_root="$SDK" "platform-tools" "emulator" \
  "platforms;android-34" "system-images;android-34;google_apis;x86_64"

echo "== 4/5 AVD (sosyal_test) =="
AVDMGR="$TOOLS/latest/cmdline-tools/avdmanager"
if ! "$AVDMGR" list avd 2>/dev/null | grep -q "sosyal_test"; then
  echo "no" | "$AVDMGR" create avd -n sosyal_test -k "system-images;android-34;google_apis;x86_64" -d pixel_7
fi

echo "== 5/5 APK'yı bul =="
APK=""
for c in "$(dirname "$0")/app-debug.apk" ./app-debug.apk; do
  [[ -f "$c" ]] && APK="$c" && break
done
if [[ -z "$APK" ]]; then
  echo "!! app-debug.apk bulunamadı. APK'yı bu betiğin yanına koy."
else
  echo "ok: $APK"
fi

cat <<'EOF'

Kurulum bitti. Şimdi iki terminal gerekli:

Terminal 1 — emülatörü başlat (pencere açılacak):
  ~/Android/Sdk/emulator/emulator -avd sosyal_test -no-snapshot-save

Terminal 2 — emülatör açıldıktan 20-30 sn sonra:
  ~/Android/Sdk/platform-tools/adb wait-for-device
  ~/Android/Sdk/platform-tools/adb install -r app-debug.apk
  ~/Android/Sdk/platform-tools/adb shell am start -n com.sosyal.app/.MainActivity

Uygulama ws://192.168.1.109:7777 adresindeki relay'e bağlanacak
(sunucu açık olmalı: o makinede `bash scripts/relay-start.sh`).

İpucu: emülatör penceresini büyütmek için -gpu host -skin 1080x2400 ekleyebilirsin.
EOF
