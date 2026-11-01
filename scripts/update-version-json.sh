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

python3 - "$ROOT" "$VERSION" "$PUB_CODE" "$NOTES" <<'PY'
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
