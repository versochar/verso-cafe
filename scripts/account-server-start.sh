#!/usr/bin/env bash
# Hesap sunucusunu başlatır (arka planda, sudo gerekmez).
#
# Veri: ${ACCOUNT_DB:-$HOME/sosyal-accounts/accounts.json}
# Port: ${PORT:-8090}
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "${ROOT}/scripts/env.sh" >/dev/null   # dart yolunu bulmak için

PORT="${PORT:-8090}"
export ACCOUNT_DB="${ACCOUNT_DB:-$HOME/sosyal-accounts/accounts.json}"
LOG="${ROOT}/.data/account/account-server.log"
PIDFILE="${ROOT}/.data/account/account-server.pid"
mkdir -p "$(dirname "$LOG")" "$(dirname "$ACCOUNT_DB")"

if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
  echo "hesap sunucusu zaten çalışıyor (pid $(cat "$PIDFILE"))"
  exit 0
fi

cd "${ROOT}/apps/account-server"
nohup dart run bin/server.dart >"$LOG" 2>&1 &
echo $! >"$PIDFILE"

# `dart run` ilk seferde derleme yapar; sağlık yanıtı birkaç saniye gecikebilir.
ok=0
for _ in $(seq 1 30); do
  if curl -sf "http://127.0.0.1:${PORT}/healthz" >/dev/null; then ok=1; break; fi
  sleep 2
done

if [[ "$ok" == 1 ]]; then
  echo "hesap sunucusu hazır: :${PORT} (veri: ${ACCOUNT_DB}, log: ${LOG})"
else
  echo "hesap sunucusu yanıt vermiyor; loga bakın: ${LOG}" >&2
  exit 1
fi
