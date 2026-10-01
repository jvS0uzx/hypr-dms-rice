#!/usr/bin/env bash
# Linhas de estado do ambiente de desenvolvimento para o fastfetch.
# Fora daqui, o escape dentro do JSONC vira ilegível.
set -uo pipefail
SNAP="${XDG_RUNTIME_DIR:-/tmp}/ricestat.json"

case "${1:-}" in
docker)
    n=$(docker ps -q 2>/dev/null | wc -l | tr -d ' ')
    p=$(docker ps -aq -f status=exited 2>/dev/null | wc -l | tr -d ' ')
    echo "$n no ar, $p parados"
    ;;
deploys)
    python3 - "$SNAP" <<'PY' 2>/dev/null || echo "ricestat fora"
import json, sys
d = json.load(open(sys.argv[1]))["deploys"]
extra = f", {d['running']} rodando" if d["running"] else ""
print(f"{d['ok']} ok, {d['failing']} falhando{extra}")
PY
    ;;
agents)
    python3 - "$SNAP" <<'PY' 2>/dev/null || echo "ricestat fora"
import json, sys
q = json.load(open(sys.argv[1]))["quota"]
if not q["active"]:
    print("janela fechada")
else:
    m = q["minutes_left"]
    print(f"{q['block_tokens']/1e6:.1f}M na janela · reseta em {m//60}h{m%60:02d}")
PY
    ;;
frota)
    python3 - "$SNAP" <<'PY' 2>/dev/null || echo "ricestat fora"
import json, sys
h = json.load(open(sys.argv[1]))["hosts"]
print(f"{h['up']} máquinas, {h['databases']} bancos, {h['databases_down']} fora")
PY
    ;;
*) echo "uso: devinfo.sh {docker|deploys|agents|frota}" >&2; exit 1 ;;
esac
