#!/usr/bin/env bash
# Cloudflare tünellerini durdurur (scripts/tunnel-start.sh).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA="${ROOT}/.data/tunnel"

for name in relay media; do
  pidfile="${DATA}/${name}.pid"
  [[ -f "$pidfile" ]] || continue
  pid="$(cat "$pidfile")"
  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    echo "${name} tüneli durduruldu (pid ${pid})"
  fi
  rm -f "$pidfile"
done
