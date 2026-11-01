#!/usr/bin/env bash
# version.json'u depodaki imzalı APK'lardan üretir.
#
#   ./scripts/update-version-json.sh 0.2.0 "Kısa yenilik metni"
#
# Sürüm/versionCode `apps/mobile/pubspec.yaml`'dan doğrulanır, sha256'lar
# dosyalardan hesaplanır (elle yazılan özetler güncellemeyi bozuyordu).
# Yayından sonra: ./scripts/publish-release.sh v0.2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:?kullanım: update-version-json.sh <sürüm> [\"notlar\"]}"
NOTES="${2:-Verso Cafe güncellemesi.}"

PUB="$(grep -E '^version:' "${ROOT}/apps/mobile/pubspec.yaml" | awk '{print $2}')"
PUB_NAME="${PUB%%+*}"
PUB_CODE="${PUB##*+}"
[[ "$PUB_NAME" == "$VERSION" ]] || {
  echo "HATA: pubspec sürümü ${PUB_NAME}, verilen ${VERSION} ile uyuşmuyor." >&2
  exit 1
}
[[ "$PUB_CODE" != "$PUB" ]] || {
  echo "HATA: pubspec'te versionCode yok (biçim: 0.2.0+3)." >&2
  exit 1
}

for f in verso-cafe-release-arm64.apk verso-cafe-release-armv7.apk; do
  [[ -f "${ROOT}/${f}" ]] || {
    echo "HATA: ${f} yok — önce ./scripts/release-apk.sh çalıştır." >&2
    exit 1
  }
done

# Gerçek versionCode/versionName APK'dan okunur: split APK'larda Flutter
# mimari başına 1000 ekler (arm64 = 2000 + pubspec, armv7 = 1000 + pubspec).
source "${ROOT}/scripts/env.sh" >/dev/null
AAPT2="$(command -v aapt2 || echo "${ANDROID_HOME}/build-tools/36.0.0/aapt2")"
# `head -1` boruyu erken kapatıp SIGPIPE üretir; pipefail + set -e betiği
# sessizce düşürüyordu. sed tüm çıktıyı okuyup ilk satırı alır.
BADGING="$("${AAPT2}" dump badging "${ROOT}/verso-cafe-release-arm64.apk" 2>/dev/null | sed -n '1p')"
APK_CODE="$(sed -nE "s/.*versionCode='([0-9]+)'.*/\1/p" <<<"$BADGING")"
APK_NAME="$(sed -nE "s/.*versionName='([^']+)'.*/\1/p" <<<"$BADGING")"
[[ "$APK_NAME" == "$VERSION" ]] || {
  echo "HATA: APK sürümü '${APK_NAME}', verilen ${VERSION} ile uyuşmuyor —" >&2
  echo "      APK'lar bayat olabilir; ./scripts/release-apk.sh ile yeniden derle." >&2
  exit 1
}
CODE="${APK_CODE:-$((1000 * 2 + PUB_CODE))}"

python3 - "$ROOT" "$VERSION" "$CODE" "$NOTES" <<'PY'
import datetime, hashlib, json, os, sys

root, version, code, notes = sys.argv[1:5]
tag = f"v{version}"
base = f"https://github.com/versochar/verso-cafe/releases/download/{tag}"
files = {
    "arm64-v8a": "verso-cafe-release-arm64.apk",
    "armeabi-v7a": "verso-cafe-release-armv7.apk",
}


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


data = {
    "version": version,
    "versionCode": int(code),
    "notes": notes,
    "publishedAt": datetime.date.today().isoformat(),
    "assets": {abi: f"{base}/{name}" for abi, name in files.items()},
    "sha256": {abi: sha256(os.path.join(root, name)) for abi, name in files.items()},
}
out = os.path.join(root, "version.json")
with open(out, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
    f.write("\n")
print(json.dumps(data, ensure_ascii=False, indent=2))
PY

echo ""
echo "Yazıldı: ${ROOT}/version.json — yayın: ./scripts/publish-release.sh v${VERSION}"
