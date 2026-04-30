#!/bin/bash
# Fleet chat test against a LOCALLY-run dist-relay build. Used to
# validate relay-side fixes before pushing + waiting for CI/Watchtower
# to roll out to Hetzner.
#
# Boots a dist-relay from /home/rl/work/codeberg.org/macula-io/macula-dist-relay
# on 127.0.0.1:14434, then runs test-chat-fleet.sh against it with N
# participants.
set -euo pipefail

N="${1:-3}"
RELAY_DIR="${RELAY_DIR:-/home/rl/work/codeberg.org/macula-io/macula-dist-relay}"
DIR="$(cd "$(dirname "$0")/.." && pwd)"
COOKIE="local-fleet-$$"
PORT=14434
LOG_DIR="/tmp/local-fleet-$$"
mkdir -p "$LOG_DIR"

# Dev TLS config for the relay
export MACULA_TLS_MODE=development
export MACULA_DIST_PORT=$PORT

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

RELAY_PID=""
cleanup() {
    [ -n "$RELAY_PID" ] && kill "$RELAY_PID" 2>/dev/null || true
    pkill -9 -f "local-fleet-$$" 2>/dev/null || true
    wait 2>/dev/null || true
    echo "  [info] relay log: $LOG_DIR/relay.log"
}
trap cleanup EXIT

echo "━━━ local fleet test (N=$N) ━━━"
echo "  relay dir: $RELAY_DIR"
echo "  port:      $PORT"
echo "  cookie:    $COOKIE"
echo ""

(cd "$RELAY_DIR" && rebar3 compile 2>&1 | tail -1)

(cd "$RELAY_DIR" && \
    erl -config "$SYSCONFIG" \
        -pa _build/default/lib/*/ebin \
        -noshell \
        -sname "dist_relay_local_$$" \
        -setcookie "$COOKIE" \
        -eval 'application:ensure_all_started(macula), {ok, _} = application:ensure_all_started(macula_dist_relay), io:format("[relay] up on UDP ~p~n", [application:get_env(macula_dist_relay, port, 4434)]), receive _ -> ok end.' \
        > "$LOG_DIR/relay.log" 2>&1) &
RELAY_PID=$!

# Wait for port
for _ in $(seq 1 30); do
    if ss -uln 2>/dev/null | grep -q ":$PORT "; then
        echo "  [relay] listening on UDP :$PORT"
        break
    fi
    sleep 0.5
done

export DIST_RELAY_URL="quic://127.0.0.1:$PORT"
"$DIR/scripts/test-chat-fleet.sh" "$N"
