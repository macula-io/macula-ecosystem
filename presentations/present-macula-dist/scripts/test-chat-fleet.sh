#!/bin/bash
# Automated multi-participant chat fleet test — reproduces 3-country
# style scenarios fully headless.
#
# Each participant runs src/dist_chat_fleet.erl:participant/1 and exits
# 0 on PASS (received a chat message from every peer) or 1 on FAIL.
#
# Usage:
#   ./scripts/test-chat-fleet.sh                         # 3 nodes, de-nuremberg
#   ./scripts/test-chat-fleet.sh 5                       # 5 nodes
#   ./scripts/test-chat-fleet.sh 3 it-milan              # different relay identity
#   DIST_RELAY_URL=quic://localhost:14434 \
#       ./scripts/test-chat-fleet.sh 3                   # local relay
#   REMOTE_LOG_HOST=178.104.198.89 \
#       ./scripts/test-chat-fleet.sh 3                   # tail server logs
#
# Exit codes: 0 if all participants PASS, 1 otherwise.

set -euo pipefail

N="${1:-3}"
IDENTITY="${2:-de-nuremberg}"
RELAY_URL="${DIST_RELAY_URL:-quic://dist-${IDENTITY}.macula.io:4434}"
DIR="$(cd "$(dirname "$0")/.." && pwd)"
COOKIE="fleet-chat-$$"
HOST=$(cat /etc/hostname 2>/dev/null | cut -d. -f1 || uname -n | cut -d. -f1)
ROOM="${ROOM:-fleet}"
QUORUM_MS="${QUORUM_MS:-60000}"
LOG_DIR="/tmp/fleet-chat-$$"
REMOTE_LOG_HOST="${REMOTE_LOG_HOST:-}"

mkdir -p "$LOG_DIR"

# Dev-mode TLS: one shared cert dir for all participants on this host
export MACULA_TLS_MODE=development
# Must be set BEFORE erl boots so net_kernel:listen picks dist_relay mode
# (the participant module sets it too, but that's after -proto_dist fires)
export MACULA_DIST_MODE=dist_relay
SYSCONFIG="$LOG_DIR/sys.config"
cat > "$SYSCONFIG" <<EOF
[
  {macula, [
    {cert_path, "${LOG_DIR}/cert.pem"},
    {key_path,  "${LOG_DIR}/key.pem"}
  ]},
  {kernel, [
    {macula_dist_cert_dir, "${LOG_DIR}"},
    {logger_level, info}
  ]}
].
EOF

# Build the participant node name list: p1@host, p2@host, ...
NODE_NAMES=()
for i in $(seq 1 "$N"); do
    NODE_NAMES+=("p${i}@${HOST}")
done
PEERS_LIST=$(IFS=','; echo "${NODE_NAMES[*]}" | sed "s/,/',/g; s/^/['/; s/$/']/")
# peers atoms list like: ['p1@host','p2@host','p3@host']
# shell-escape: use the list as a single eval arg

SEED="${NODE_NAMES[0]}"

cleanup() {
    echo ""
    echo "━━━ cleanup ━━━"
    for pid in "${PIDS[@]:-}"; do
        [ -n "$pid" ] && kill "$pid" 2>/dev/null || true
    done
    pkill -9 -f "fleet-chat-$$" 2>/dev/null || true
    wait 2>/dev/null || true
    [ -n "$REMOTE_TAIL_PID" ] && kill "$REMOTE_TAIL_PID" 2>/dev/null || true
    echo "  [info] logs preserved at $LOG_DIR"
}
trap cleanup EXIT

echo "━━━ dist chat fleet test (N=$N) ━━━"
echo "  relay:    $RELAY_URL"
echo "  seed:     $SEED"
echo "  peers:    ${NODE_NAMES[*]}"
echo "  room:     #$ROOM"
echo "  quorum:   ${QUORUM_MS}ms"
echo "  logs:     $LOG_DIR"
[ -n "$REMOTE_LOG_HOST" ] && echo "  remote:   $REMOTE_LOG_HOST (tailing macula-dist-relay)"
echo ""

cd "$DIR"
rebar3 compile 2>&1 | tail -1

# ── Optional: start tailing the remote relay log ──────────────────
REMOTE_TAIL_PID=""
if [ -n "$REMOTE_LOG_HOST" ]; then
    ssh "$REMOTE_LOG_HOST" 'sudo docker logs -f --tail 0 macula-dist-relay 2>&1' \
        > "$LOG_DIR/relay-remote.log" 2>&1 &
    REMOTE_TAIL_PID=$!
    sleep 1
fi

# ── Launch participants in parallel ───────────────────────────────
PIDS=()
for i in "${!NODE_NAMES[@]}"; do
    IDX=$((i + 1))
    NODE="${NODE_NAMES[$i]}"
    LOG="$LOG_DIR/p${IDX}.log"

    OPTS="#{url => <<\"${RELAY_URL}\">>, seed => '${SEED}', room => \"${ROOM}\", peers => [$(IFS=','; for n in "${NODE_NAMES[@]}"; do echo -n "'${n}',"; done | sed 's/,$//')], quorum_ms => ${QUORUM_MS}}"

    erl -config "$SYSCONFIG" \
        -pa _build/default/lib/*/ebin -pa _build/default/checkouts/*/ebin \
        -proto_dist macula \
        -name "${NODE}" \
        -setcookie "$COOKIE" \
        -noshell \
        -eval "dist_chat_fleet:participant(${OPTS})." \
        > "$LOG" 2>&1 &
    PIDS+=($!)
    echo "  [launch] p${IDX} (${NODE}) pid=${PIDS[-1]}"
    # Tiny stagger so the seed identifies first — not strictly required,
    # but makes log timelines easier to read.
    if [ "$IDX" -eq 1 ]; then
        sleep 2
    fi
done

# ── Wait for every participant and collect exit codes ─────────────
echo ""
echo "━━━ waiting for quorum (deadline ${QUORUM_MS}ms + startup) ──"
OVERALL=0
for i in "${!PIDS[@]}"; do
    IDX=$((i + 1))
    PID="${PIDS[$i]}"
    if wait "$PID"; then
        echo "  [p${IDX}] PASS"
    else
        echo "  [p${IDX}] FAIL (exit $?)"
        OVERALL=1
    fi
done

# ── Summary ───────────────────────────────────────────────────────
echo ""
echo "━━━ per-node tails ━━━"
for i in "${!NODE_NAMES[@]}"; do
    IDX=$((i + 1))
    LOG="$LOG_DIR/p${IDX}.log"
    echo ""
    echo "── p${IDX} (${NODE_NAMES[$i]}) ──"
    grep -E "RESULT:|received chat|joined|seed|waiting|NOT RUNNING|client status|pang|Error|CRASH|warning|failed" "$LOG" | tail -15 || true
done

if [ -n "$REMOTE_LOG_HOST" ]; then
    echo ""
    echo "━━━ relay server tail (last 30 lines) ━━━"
    tail -30 "$LOG_DIR/relay-remote.log" 2>/dev/null | grep -vE "PROGRESS|started_at|SUPERVISOR" || true
fi

echo ""
if [ "$OVERALL" -eq 0 ]; then
    echo "━━━ RESULT: PASS (all $N participants) ━━━"
else
    echo "━━━ RESULT: FAIL ━━━"
fi
exit "$OVERALL"
