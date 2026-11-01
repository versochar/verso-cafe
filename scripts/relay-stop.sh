#!/usr/bin/env bash
# Yerel relay'i durdurur (relay-start.sh'nin pid dosyasıyla).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PIDFILE="$ROOT/.data/relay.pid"

if [[ ! -f "$PIDFILE" ]]; then
  echo "Relay çalışmıyor (pid dosyası yok)."
  exit 0
fi

PID="$(cat "$PIDFILE")"
if kill -0 "$PID" 2>/dev/null; then
  kill "$PID"
  sleep 1
  kill -0 "$PID" 2>/dev/null && kill -9 "$PID" 2>/dev/null || true
  echo "Relay durduruldu (pid $PID)."
else
  echo "Relay zaten kapalıymış (pid $PID yok)."
fi
rm -f "$PIDFILE"
