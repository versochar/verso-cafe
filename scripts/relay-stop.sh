#!/usr/bin/env bash
# Yerel relay'i durdurur.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PIDFILE="$ROOT/.data/relay.pid"

if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
  kill "$(cat "$PIDFILE")"
  rm -f "$PIDFILE"
  echo "Relay durduruldu."
else
  echo "Çalışan relay bulunamadı."
  rm -f "$PIDFILE"
fi
