#!/bin/bash
# Automated dist-relay test — two nodes, connect, ping, report.
#
# Usage:
#   ./scripts/test-dist-relay.sh                    # default: de-nuremberg
#   ./scripts/test-dist-relay.sh it-milan            # specific identity
#   DIST_RELAY_URL=quic://localhost:14434 ./scripts/test-dist-relay.sh

set -euo pipefail

IDENTITY="${1:-de-nuremberg}"
RELAY_URL="${DIST_RELAY_URL:-quic://dist-${IDENTITY}.macula.io:4434}"
DIR="$(cd "$(dirname "$0")/.." && pwd)"
COOKIE="dist-relay-test-$$"
# -sname uses the SHORT hostname (no domain). Match it.
HOST=$(cat /etc/hostname 2>/dev/null | cut -d. -f1 || uname -n | cut -d. -f1)

ALICE="alice_test@${HOST}"
BOB="bob_test@${HOST}"

export MACULA_DIST_MODE=dist_relay
export MACULA_TLS_MODE=development

ALICE_PID=""
BOB_PID=""

cleanup() {
    [ -n "$ALICE_PID" ] && kill "$ALICE_PID" 2>/dev/null || true
    [ -n "$BOB_PID" ] && kill "$BOB_PID" 2>/dev/null || true
    wait 2>/dev/null || true
}
trap cleanup EXIT

echo "━━━ dist-relay end-to-end test ━━━"
echo "  relay:  ${RELAY_URL}"
echo "  alice:  ${ALICE}"
echo "  bob:    ${BOB}"
echo ""

cd "$DIR"
rebar3 compile 2>&1 | tail -1

# Alice: connect + wait
erl -pa _build/default/lib/*/ebin \
    -proto_dist macula \
    -sname alice_test \
    -setcookie "$COOKIE" \
    -noshell \
    -eval "dist_relay_test:alice(<<\"${RELAY_URL}\">>)." \
    2>&1 | sed 's/^/  [alice] /' &
ALICE_PID=$!

sleep 4

# Bob: connect + ping alice + report
erl -pa _build/default/lib/*/ebin \
    -proto_dist macula \
    -sname bob_test \
    -setcookie "$COOKIE" \
    -noshell \
    -eval "dist_relay_test:bob(<<\"${RELAY_URL}\">>, <<\"${ALICE}\">>)." \
    2>&1 | sed 's/^/  [bob]  /'
BOB_EXIT=$?

echo ""
exit $BOB_EXIT
