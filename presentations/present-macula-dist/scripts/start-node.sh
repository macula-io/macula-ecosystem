#!/bin/bash
# Start a mesh chat node connected to a virtual relay identity.
#
# Usage:
#   ./scripts/start-node.sh alice munich
#   ./scripts/start-node.sh bob copenhagen
#   ./scripts/start-node.sh carol prague
#
# Auto-connects to the nearest relay for that city, joins #lobby,
# and shows an interactive Erlang REPL with mesh_chat commands.
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "${SCRIPT_DIR}"

# ── Node name ──────────────────────────────────────────

NODE_NAME="${1:-}"
if [ -z "${NODE_NAME}" ]; then
    echo "Usage: $0 <name> [city]"
    echo "  e.g.: $0 alice munich"
    echo "        $0 bob copenhagen"
    exit 1
fi

# ── City → relay mapping ──────────────────────────────

CITY="${2:-}"

# Map city names to relay hostnames (relay-{cc}-{city}.macula.io)
resolve_relay() {
    local city="$1"
    case "$(echo "$city" | tr '[:upper:]' '[:lower:]')" in
        # Germany
        munich|muenchen)    echo "relay-de-munich.macula.io" ;;
        berlin)             echo "relay-de-berlin.macula.io" ;;
        nuremberg|nurnberg) echo "relay-de-nuremberg.macula.io" ;;
        hamburg)            echo "relay-de-hamburg.macula.io" ;;
        frankfurt)          echo "relay-de-frankfurt.macula.io" ;;
        dortmund)           echo "relay-de-dortmund.macula.io" ;;
        bonn)               echo "relay-de-bonn.macula.io" ;;
        # Central Europe
        prague|praha)       echo "relay-cz-prague.macula.io" ;;
        vienna|wien)        echo "relay-at-vienna.macula.io" ;;
        zurich)             echo "relay-ch-zurich.macula.io" ;;
        budapest)           echo "relay-hu-budapest.macula.io" ;;
        bratislava)         echo "relay-sk-bratislava.macula.io" ;;
        ljubljana)          echo "relay-si-ljubljana.macula.io" ;;
        # Benelux
        amsterdam)          echo "relay-nl-amsterdam.macula.io" ;;
        brussels|brussel)   echo "relay-be-brussels.macula.io" ;;
        antwerp|antwerpen)  echo "relay-be-antwerp.macula.io" ;;
        luxembourg)         echo "relay-lu-luxembourg.macula.io" ;;
        # Nordic
        copenhagen|kobenhavn) echo "relay-dk-copenhagen.macula.io" ;;
        stockholm)          echo "relay-se-stockholm.macula.io" ;;
        oslo)               echo "relay-no-oslo.macula.io" ;;
        helsinki)            echo "relay-fi-helsinki.macula.io" ;;
        # Baltic
        tallinn)            echo "relay-ee-tallinn.macula.io" ;;
        riga)               echo "relay-lv-riga.macula.io" ;;
        # France
        paris)              echo "relay-fr-paris.macula.io" ;;
        lyon)               echo "relay-fr-lyon.macula.io" ;;
        # UK/Ireland
        london)             echo "relay-gb-london.macula.io" ;;
        edinburgh)          echo "relay-gb-edinburgh.macula.io" ;;
        dublin)             echo "relay-ie-dublin.macula.io" ;;
        # South
        milan|milano)       echo "relay-it-milan.macula.io" ;;
        rome|roma)          echo "relay-it-rome.macula.io" ;;
        barcelona)          echo "relay-es-barcelona.macula.io" ;;
        madrid)             echo "relay-es-madrid.macula.io" ;;
        lisbon|lisboa)      echo "relay-pt-lisbon.macula.io" ;;
        # East
        warsaw|warszawa)    echo "relay-pl-warsaw.macula.io" ;;
        bucharest|bucuresti) echo "relay-ro-bucharest.macula.io" ;;
        zagreb)             echo "relay-hr-zagreb.macula.io" ;;
        # Direct relay hostname (relay-xx-city format)
        relay-*)            echo "${city}.macula.io" ;;
        # Unknown — try constructing it
        *)
            echo >&2 "Warning: unknown city '${city}' — trying relay-xx-${city}.macula.io"
            echo "relay-xx-${city}.macula.io"
            ;;
    esac
}

if [ -z "${CITY}" ]; then
    # Pick a random city for demo variety
    CITIES=("munich" "prague" "vienna" "amsterdam" "copenhagen" "zurich" "milan" "brussels")
    CITY="${CITIES[$((RANDOM % ${#CITIES[@]}))]}"
fi

RELAY=$(resolve_relay "${CITY}")
PORT="${MACULA_QUIC_PORT:-4433}"
RELAY_URL="https://${RELAY}:${PORT}"

# ── Compile if needed ─────────────────────────────────

if [ ! -d "_build" ]; then
    echo "Compiling..."
    rebar3 compile
fi

# ── Launch ────────────────────────────────────────────

export MACULA_RELAY="${RELAY_URL}"

exec env MACULA_DIST_MODE=relay \
    ERL_FLAGS="-proto_dist macula -no_epmd" \
    rebar3 shell \
        --name "${NODE_NAME}@127.0.0.1" \
        --setcookie DEMO \
        --apps dist_test \
        --eval "mesh_chat:boot()"
