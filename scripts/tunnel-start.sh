#!/usr/bin/env bash
# Relay, medya ve hesap sunucusunu genel internete açar (Cloudflare tüneli).
#
# sudo, router ayarı veya sabit IP gerekmez: tünel cihazdan dışarı bağlanır.
# Ücretsiz "quick tunnel" adresleri rastgeledir ve tünel yeniden başladığında
# DEĞİŞİR — kalıcı adres için bkz. docs/dev-setup.md → "Genel erişim".
#
# Çıktı: .data/public-urls.env  (RELAY_URL=… MEDIA_URL=… ACCOUNT_URL=…)
# Baskıya hazır derleme:
#   set -a; source .data/public-urls.env; set +a
#   ./scripts/release-apk.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA="${ROOT}/.data/tunnel"
OUT="${ROOT}/.data/public-urls.env"
mkdir -p "$DATA"

if ! command -v cloudflared >/dev/null 2>&1; then
  echo "HATA: cloudflared yok. Kurulum (sudo gerekmez):"
  echo "  mkdir -p ~/.local/bin && curl -L -o ~/.local/bin/cloudflared \\"
  echo "    https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
  echo "  chmod +x ~/.local/bin/cloudflared"
  exit 1
fi

start_one() { # start_one <ad> <yerel-port>
  local name="$1"
  local port="$2"
  local pidfile="${DATA}/${name}.pid"
  local log="${DATA}/${name}.log"
  if [[ -f "$pidfile" ]] && kill -0 "$(cat "$pidfile")" 2>/dev/null; then
    echo "${name}: tünel zaten çalışıyor (pid $(cat "$pidfile"))"
    return 0
  fi
  if ! curl -sf "http://127.0.0.1:${port}/" >/dev/null 2>&1 &&
     ! curl -sf "http://127.0.0.1:${port}/healthz" >/dev/null 2>&1; then
    echo "HATA: 127.0.0.1:${port} yanıt vermiyor — önce ${name} sunucusunu başlat."
    exit 1
  fi
  setsid cloudflared tunnel --no-autoupdate --url "http://127.0.0.1:${port}" \
    >"$log" 2>&1 < /dev/null &
  echo $! >"$pidfile"
  echo "${name}: tünel kuruluyor…"
}

start_one relay 7777
start_one media "${PORT:-8080}"
start_one account "${ACCOUNT_PORT:-8090}"

# Adresler logda belirir (quick tunnel birkaç saniye sürer).
url_of() {
  local name="$1"
  for _ in $(seq 1 30); do
    local u
    # Günlekte ANSI renk/çizgi karakterleri var: yerelden bağımsız eşleşme için LC_ALL=C.
    u="$(LC_ALL=C grep -aohE 'https://[a-z0-9-]+\.trycloudflare\.com' "${DATA}/${name}.log" | tail -1 || true)"
    [[ -n "$u" ]] && { echo "$u"; return 0; }
    sleep 2
  done
  return 1
}

relay="$(url_of relay)" || { echo "HATA: relay tünel adresi alınamadı (${DATA}/relay.log)"; exit 1; }
media="$(url_of media)" || { echo "HATA: medya tünel adresi alınamadı (${DATA}/media.log)"; exit 1; }
account="$(url_of account)" || { echo "HATA: hesap tünel adresi alınamadı (${DATA}/account.log)"; exit 1; }

cat >"$OUT" <<EOF
# scripts/tunnel-start.sh tarafından üretildi — elle düzenleme.
# Uyarı: quick tunnel adresleri tünel yeniden başladığında değişir.
RELAY_URL=wss://${relay#https://}
MEDIA_URL=${media}
ACCOUNT_URL=${account}
EOF

echo
echo "Genel adresler (dışarıdan erişilebilir):"
echo "  relay : wss://${relay#https://}"
echo "  medya : ${media}"
echo "  hesap : ${account}"
echo "Yazıldı: $OUT"
