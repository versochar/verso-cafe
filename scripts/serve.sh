#!/usr/bin/env bash
# Ev sunucusunu tek komutla ayağa kaldırır: relay + medya + tüneller.
#
#   ./scripts/serve.sh
#
# Tünel adresi değiştiyse `network.json`'u günceller ve push'lar; böylece
# kurulu uygulamalar bir sonraki açılışta yeni adrese geçer (ADR-014).
# Durdurmak için: ./scripts/tunnel-stop.sh && ./scripts/media-server-stop.sh
#                 && ./scripts/relay-stop.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"${ROOT}/scripts/relay-start.sh"
"${ROOT}/scripts/media-server-start.sh"
"${ROOT}/scripts/tunnel-start.sh"

# publish-network.sh değişiklik yoksa hiçbir şey yapmaz.
"${ROOT}/scripts/publish-network.sh"
