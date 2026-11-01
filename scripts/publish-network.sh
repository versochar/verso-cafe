#!/usr/bin/env bash
# Çalışan tünellerin adreslerini `network.json`'a yazar, commit'ler ve push'lar.
#
# Kurulu uygulamalar açılışta bu dosyayı okur (ADR-014); yani tünel yeniden
# başlayıp adres değiştiğinde APK yayınlamak gerekmez — bu betik yeter:
#
#   ./scripts/tunnel-start.sh      # (adres değiştiyse)
#   ./scripts/publish-network.sh   # herkese duyur
#
# Adresler `.data/public-urls.env` dosyasından (tunnel-start.sh üretir) ya da
# RELAY_URL / MEDIA_URL ortam değişkenlerinden alınır.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="https://github.com/versochar/verso-cafe.git"
OUT="${ROOT}/network.json"

if [[ -f "${ROOT}/.data/public-urls.env" ]]; then
  # shellcheck disable=SC1091
  source "${ROOT}/.data/public-urls.env"
fi

RELAY="${RELAY_URL:?RELAY_URL yok — önce ./scripts/tunnel-start.sh çalıştır.}"
MEDIA="${MEDIA_URL:?MEDIA_URL yok — önce ./scripts/tunnel-start.sh çalıştır.}"

case "$RELAY" in wss://*) ;; *)
  echo "HATA: relay adresi wss:// olmalı (gelen: $RELAY)" >&2; exit 1;;
esac
case "$MEDIA" in https://*) ;; *)
  echo "HATA: medya adresi https:// olmalı (gelen: $MEDIA)" >&2; exit 1;;
esac

python3 - "$OUT" "$RELAY" "$MEDIA" <<'PY'
import json, sys, datetime
out, relay, media = sys.argv[1:4]
data = {
    "relay": relay,
    "media": media,
    "updatedAt": datetime.date.today().isoformat(),
}
with open(out, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
    f.write("\n")
PY

echo "network.json güncellendi:"
echo "  relay : $RELAY"
echo "  medya : $MEDIA"

cd "$ROOT"
if [[ -z "$(git status --porcelain -- network.json)" ]]; then
  echo "Değişiklik yok — push atlandı."
  exit 0
fi

git add network.json
git commit -q -m "Ağ adresleri: relay/medya tünelleri güncellendi

$(date '+%Y-%m-%d %H:%M') itibarıyla çalışan tünellerin adresleri.
Kurulu uygulamalar açılışta bu dosyayı okuyup yeni adrese geçer (ADR-014)."

TOKEN="${GITHUB_TOKEN:-$(cat "$HOME/Masaüstü/Yeni Klasör/git tokens/trhs.txt" 2>/dev/null | tr -d '[:space:]' || true)}"
if [[ -n "$TOKEN" ]]; then
  git push "https://x-access-token:${TOKEN}@${REPO#https://}" HEAD:main 2>&1 | tail -2
else
  echo "UYARI: GitHub token yok — commit yerel kaldı, elle push'la." >&2
fi

echo ""
echo "Yayında: https://raw.githubusercontent.com/versochar/verso-cafe/main/network.json"
