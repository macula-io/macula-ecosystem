#!/bin/bash
# Local dist-relay end-to-end test using the local SDK checkout.
# Spins up a dist-relay listener on 14434 + two test nodes, pings.

set -euo pipefail

RELAY_URL="${DIST_RELAY_URL:-quic://127.0.0.1:14434}"
DIR="$(cd "$(dirname "$0")/.." && pwd)"
RELAY_DIR="${RELAY_DIR:-/home/rl/work/github.com/macula-io/macula-dist-relay}"
COOKIE="dist-relay-local-$$"
HOST=$(cat /etc/hostname 2>/dev/null | cut -d. -f1 || uname -n | cut -d. -f1)

ALICE="alice_test@${HOST}"
BOB="bob_test@${HOST}"

export MACULA_DIST_MODE=dist_relay
export MACULA_TLS_MODE=development
export MACULA_DIST_PORT=14434

TLS_DIR="/tmp/macula_dist_test_$$"
mkdir -p "$TLS_DIR"

# Write a sys.config that points macula/kernel cert paths into TLS_DIR
SYSCONFIG="${TLS_DIR}/sys.config"
cat > "$SYSCONFIG" <<EOF
[
  {macula, [
    {cert_path, "${TLS_DIR}/cert.pem"},
    {key_path,  "${TLS_DIR}/key.pem"}
  ]},
  {kernel, [
    {macula_dist_cert_dir, "${TLS_DIR}"},
    {logger_level, info}
  ]}
].
EOF

RELAY_PID=""
ALICE_PID=""
BOB_PID=""

cleanup() {
    for p in "$BOB_PID" "$ALICE_PID" "$RELAY_PID"; do
        [ -n "$p" ] && kill "$p" 2>/dev/null || true
    done
    pkill -9 -f "dist_relay_local_$$" 2>/dev/null || true
    wait 2>/dev/null || true
    # Keep TLS_DIR for inspection; caller removes if desired
    echo "  [info] logs preserved at $TLS_DIR" >&2
}
trap cleanup EXIT

echo "━━━ local dist-relay test ━━━"
echo "  relay:   ${RELAY_URL}"
echo "  alice:   ${ALICE}"
echo "  bob:     ${BOB}"
echo "  tls dir: ${TLS_DIR}"
echo ""

# Compile dist-relay + demo
(cd "$RELAY_DIR" && rebar3 compile 2>&1 | tail -1)
cd "$DIR"
rebar3 compile 2>&1 | tail -1

RELAY_LOG="${TLS_DIR}/relay.log"
ALICE_LOG="${TLS_DIR}/alice.log"
BOB_LOG="${TLS_DIR}/bob.log"

# Start relay in background — keep erl alive with infinity receive
(cd "$RELAY_DIR" && \
    erl -config "$SYSCONFIG" \
        -pa _build/default/lib/*/ebin -pa _build/default/checkouts/*/ebin \
        -noshell \
        -sname "dist_relay_local_$$" \
        -setcookie "$COOKIE" \
        -eval 'application:ensure_all_started(macula), {ok, _} = application:ensure_all_started(macula_dist_relay), io:format("[relay] up on UDP 14434~n"), receive _ -> ok end.' \
        >> "$RELAY_LOG" 2>&1) &
RELAY_PID=$!

# Wait for relay to actually be listening before starting nodes
for i in $(seq 1 30); do
    if ss -uln 2>/dev/null | grep -q ":14434 "; then
        echo "  [relay] port 14434 is open"
        break
    fi
    sleep 0.5
done

# Alice
erl -config "$SYSCONFIG" \
    -pa _build/default/lib/*/ebin -pa _build/default/checkouts/*/ebin \
    -proto_dist macula \
    -sname alice_test \
    -setcookie "$COOKIE" \
    -noshell \
    -eval "dist_relay_test:alice(<<\"${RELAY_URL}\">>)." \
    >> "$ALICE_LOG" 2>&1 &
ALICE_PID=$!

sleep 4

# Bob
erl -config "$SYSCONFIG" \
    -pa _build/default/lib/*/ebin -pa _build/default/checkouts/*/ebin \
    -proto_dist macula \
    -sname bob_test \
    -setcookie "$COOKIE" \
    -noshell \
    -eval "dist_relay_test:bob(<<\"${RELAY_URL}\">>, <<\"${ALICE}\">>)." \
    >> "$BOB_LOG" 2>&1
BOB_EXIT=$?

# Give alice/relay a moment to flush
sleep 1
echo ""
echo "━━━ RELAY LOG ━━━"
sed 's/^/  [relay] /' "$RELAY_LOG" 2>/dev/null || true
echo ""
echo "━━━ ALICE LOG ━━━"
sed 's/^/  [alice] /' "$ALICE_LOG" 2>/dev/null || true
echo ""
echo "━━━ BOB LOG ━━━"
sed 's/^/  [bob]   /' "$BOB_LOG" 2>/dev/null || true

echo ""
exit $BOB_EXIT
