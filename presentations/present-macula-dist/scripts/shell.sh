#!/usr/bin/env bash
# Launch an interactive mesh_chat shell with dist-over-mesh configured.
#
# Usage:
#   ./scripts/shell.sh alice@host00.lab
#   ./scripts/shell.sh alice@host00.lab DEMO
#
# The first arg is the node name; second (optional) is the cookie.
# If only one arg is given, cookie defaults to DEMO.
#
# -proto_dist macula requires macula_dist.beam on the code path BEFORE
# net_kernel starts. rebar3 shell sets paths AFTER boot — so we inject
# the macula ebin dir via ERL_FLAGS -pa.
set -eu

NODE="${1:?node name required — e.g. alice@host00.lab}"
COOKIE="${2:-DEMO}"

# Ensure deps are present (cheap if already fetched)
rebar3 get-deps >/dev/null

MACULA_EBIN="_build/default/lib/macula/ebin"

if [ ! -d "${MACULA_EBIN}" ]; then
    echo "[shell] ${MACULA_EBIN} not found — running rebar3 compile..."
    rebar3 compile >/dev/null
fi

export MACULA_DIST_MODE=relay
export ERL_FLAGS="-pa ${MACULA_EBIN} -proto_dist macula -no_epmd"

exec rebar3 shell --name "${NODE}" --setcookie "${COOKIE}"
