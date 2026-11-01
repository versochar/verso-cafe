#!/usr/bin/env bash
# GitHub sürümü yayınlar: versochar/verso-cafe üzerinde tag + APK asset'leri.
#
# Kullanım:
#   GITHUB_TOKEN=ghp_... ./scripts/publish-release.sh v0.1.1
# Token yoksa masaüstündeki varsayılan dosyayı dener (kişisel kurulum).
#
# Ön koşul: ./scripts/release-apk.sh ile APK'lar üretilmiş olmalı.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="versochar/verso-cafe"
TAG="${1:?kullanım: publish-release.sh v<semver>  (ör. v0.1.1)}"

TOKEN="${GITHUB_TOKEN:-$(cat "$HOME/Masaüstü/Yeni Klasör/git tokens/trhs.txt" 2>/dev/null | tr -d '[:space:]' || true)}"
[[ -n "$TOKEN" ]] || { echo "HATA: GITHUB_TOKEN ver ve ya token dosyası olsun." >&2; exit 1; }

for f in verso-cafe-release-arm64.apk verso-cafe-release-armv7.apk version.json; do
  [[ -f "${ROOT}/${f}" ]] || { echo "HATA: ${f} yok — önce ./scripts/release-apk.sh çalıştır." >&2; exit 1; }
done

# version.json ile tag tutarlı olmalı
VJ_VER=$(python3 -c "import json; print(json.load(open('${ROOT}/version.json'))['version'])")
[[ "v${VJ_VER}" == "$TAG" ]] || { echo "HATA: version.json (${VJ_VER}) ile tag (${TAG}) uyuşmuyor." >&2; exit 1; }

api() { curl -s -H "Authorization: Bearer ${TOKEN}" -H "Accept: application/vnd.github+json" "$@"; }

# Tag'ı işaretleyecek commit: main'in ucu
SHA=$(git -C "${ROOT}" rev-parse origin/main 2>/dev/null || git -C "${ROOT}" rev-parse HEAD)

echo "→ release ${TAG} oluşturuluyor…"
REL=$(api -X POST "https://api.github.com/repos/${REPO}/releases" -d "{
  \"tag_name\": \"${TAG}\",
  \"name\": \"Verso Cafe ${TAG}\",
  \"body\": \"Android 8+ — arm64 (yeni telefonlar) veya armv7 (eski telefonlar) APKsını kur.\",
  \"draft\": false, \"prerelease\": false,
  \"target_commitish\": \"main\"
}")
REL_ID=$(echo "$REL" | python3 -c "import json,sys; d=json.load(sys.stdin); m=d.get('message'); print(d.get('id') or '')" )
[[ -n "$REL_ID" ]] || { echo "HATA: $(echo "$REL" | head -c 300)" >&2; exit 1; }

for f in verso-cafe-release-arm64.apk verso-cafe-release-armv7.apk version.json; do
  case "$f" in *.apk) CT="application/vnd.android.package-archive";; *) CT="application/json";; esac
  echo "→ yükleniyor: ${f}"
  curl -s -X POST -H "Authorization: Bearer ${TOKEN}" -H "Content-Type: ${CT}" \
    --data-binary "@${ROOT}/${f}" \
    "https://uploads.github.com/repos/${REPO}/releases/${REL_ID}/assets?name=${f}" \
    | python3 -c "import json,sys; d=json.load(sys.stdin); print('  ✓', d.get('name'), d.get('size'), 'bayt') if d.get('name') else (print('HATA:', d.get('message')), sys.exit(1))"
done

echo ""
echo "Yayın hazır: https://github.com/${REPO}/releases/tag/${TAG}"
