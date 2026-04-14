#!/usr/bin/env bash
# Launch an interactive mesh_chat shell with dist-over-mesh configured.
#
# Usage:
#   ./scripts/shell.sh <node>
#   ./scripts/shell.sh <node> <relay-city>
#   ./scripts/shell.sh <node> <relay-city> <room>
#   ./scripts/shell.sh <node> <relay-city> <room> <cookie>
#
# Examples:
#   ./scripts/shell.sh alice@host00.lab
#   ./scripts/shell.sh alice@host00.lab pt-lisbon
#   ./scripts/shell.sh alice@host00.lab pt-lisbon beatles
#
# When <relay-city> is given the shell auto-runs mesh_chat:tour/2 so the
# node is connected, joined, and ready for interactive chat as soon as
# the prompt appears. When <room> is omitted, tour joins "lobby".
#
# -proto_dist macula requires macula_dist.beam on the code path BEFORE
# net_kernel starts. rebar3 shell sets paths AFTER boot, so we inject
# the macula ebin dir via ERL_FLAGS -pa.
set -eu

NODE="${1:?node name required — e.g. alice@host00.lab}"
RELAY="${2:-}"
ROOM="${3:-lobby}"
COOKIE="${4:-VERY_SECRET_DEMO_COOKIE}"

rebar3 get-deps >/dev/null

MACULA_EBIN="_build/default/lib/macula/ebin"

if [ ! -d "${MACULA_EBIN}" ]; then
  echo "[shell] ${MACULA_EBIN} not found — running rebar3 compile..."
  rebar3 compile >/dev/null
fi

export MACULA_DIST_MODE=relay
export ERL_FLAGS="-pa ${MACULA_EBIN} -proto_dist macula -no_epmd"

if [ -n "${RELAY}" ]; then
  exec rebar3 shell \
    --name "${NODE}" \
    --setcookie "${COOKIE}" \
    --eval "mesh_chat:tour(\"${RELAY}\", \"${ROOM}\")."
else
  exec rebar3 shell --name "${NODE}" --setcookie "${COOKIE}"
fi
