#!/usr/bin/env bash
# Hesap sunucusunu durdurur.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PIDFILE="${ROOT}/.data/account/account-server.pid"
if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
  kill "$(cat "$PIDFILE")"
  rm -f "$PIDFILE"
  echo "hesap sunucusu durduruldu"
else
  pkill -f "apps/account-server/bin/server.dart" 2>/dev/null || true
  echo "çalışan hesap sunucusu yok"
fi
