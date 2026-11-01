#!/usr/bin/env bash
# Medya sunucusunu durdurur.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PIDFILE="${ROOT}/.data/media/media-server.pid"
if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
  kill "$(cat "$PIDFILE")"
  rm -f "$PIDFILE"
  echo "medya sunucusu durduruldu"
else
  pkill -f "apps/media-server/bin/server.dart" 2>/dev/null || true
  echo "çalışan medya sunucusu yok"
fi
