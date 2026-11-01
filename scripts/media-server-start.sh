#!/usr/bin/env bash
# Medya sunucusunu başlatır (arka planda, sudo gerekmez).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "${ROOT}/scripts/env.sh" >/dev/null   # dart/yolunu bulmak için
LOG="${ROOT}/.data/media/media-server.log"
PIDFILE="${ROOT}/.data/media/media-server.pid"
mkdir -p "$(dirname "$LOG")"

if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
  echo "medya sunucusu zaten çalışıyor (pid $(cat "$PIDFILE"))"
  exit 0
fi

cd "${ROOT}/apps/media-server"
nohup dart run bin/server.dart >"$LOG" 2>&1 &
echo $! >"$PIDFILE"

# `dart run` ilk seferde derleme yapar; sağlık yanıtı birkaç saniye gecikebilir.
ok=0
for _ in $(seq 1 30); do
  if curl -sf "http://127.0.0.1:${PORT:-8080}/healthz" >/dev/null; then ok=1; break; fi
  sleep 2
done

if [[ "$ok" == 1 ]]; then
  echo "medya sunucusu hazır: :${PORT:-8080} (log: $LOG)"
else
  echo "medya sunucusu yanıt vermiyor; loga bakın: $LOG" >&2
  exit 1
fi
