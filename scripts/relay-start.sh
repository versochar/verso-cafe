#!/usr/bin/env bash
# Yerel Nostr relay'ini başlatır (nostr-rs-relay).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/env.sh" >/dev/null

CONFIG="$ROOT/infra/relay/local.toml"
DATA="$ROOT/.data/relay"
LOG="$ROOT/.data/relay.log"
PIDFILE="$ROOT/.data/relay.pid"

mkdir -p "$DATA" "$ROOT/.data"

if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
  echo "Relay zaten çalışıyor (pid $(cat "$PIDFILE"))."
  exit 0
fi

if ! command -v nostr-rs-relay >/dev/null 2>&1; then
  echo "HATA: nostr-rs-relay bulunamadı. Kurulum: cargo install nostr-rs-relay --locked"
  exit 1
fi

nohup setsid nostr-rs-relay --config "$CONFIG" >"$LOG" 2>&1 &
echo $! >"$PIDFILE"

sleep 2
if kill -0 "$(cat "$PIDFILE")" 2>/dev/null && ss -lnt 2>/dev/null | grep -q ":7777"; then
  echo "Relay çalışıyor: ws://127.0.0.1:7777  (log: $LOG)"
else
  echo "Relay başlatılamadı. Log:"
  tail -20 "$LOG"
  exit 1
fi
