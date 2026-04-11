#!/bin/bash
# Launch the Erlang Distribution over Relay Mesh presentation.
#
# Usage:
#   ./present.sh              # Build slides and open in browser
#   ./present.sh --watch      # Rebuild on file changes (live editing)
#   ./present.sh --pdf        # Export to PDF
#   ./present.sh --demo       # Skip slides, open two chat terminals
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PRES_DIR="${SCRIPT_DIR}/presentation"
SLIDES="${PRES_DIR}/SLIDES.md"
OUTPUT="${PRES_DIR}/slides.html"
PDF_OUTPUT="${PRES_DIR}/slides.pdf"

# Colors
G='\033[32m' C='\033[36m' Y='\033[33m' R='\033[0m'

ensure_deps() {
    if ! command -v npx >/dev/null 2>&1; then
        echo -e "${Y}npx not found. Install Node.js: https://nodejs.org${R}"
        exit 1
    fi
    # Compile the Erlang project (for interactive demo)
    if [ ! -d "${SCRIPT_DIR}/_build" ]; then
        echo -e "${C}[present]${R} Compiling demo project..."
        cd "${SCRIPT_DIR}" && rebar3 compile
    fi
}

build_slides() {
    echo -e "${C}[present]${R} Building slides..."
    npx @marp-team/marp-cli "${SLIDES}" -o "${OUTPUT}" --allow-local-files --theme-set "${PRES_DIR}" 2>/dev/null
    echo -e "${G}[present]${R} Slides ready: ${OUTPUT}"
}

open_slides() {
    if command -v xdg-open >/dev/null 2>&1; then
        xdg-open "${OUTPUT}" 2>/dev/null &
    elif command -v open >/dev/null 2>&1; then
        open "${OUTPUT}"
    else
        echo -e "${Y}[present]${R} Open manually: ${OUTPUT}"
    fi
}

watch_slides() {
    echo -e "${C}[present]${R} Watching for changes (Ctrl+C to stop)..."
    npx @marp-team/marp-cli "${SLIDES}" -o "${OUTPUT}" --allow-local-files --watch 2>/dev/null
}

export_pdf() {
    echo -e "${C}[present]${R} Exporting to PDF..."
    npx @marp-team/marp-cli "${SLIDES}" -o "${PDF_OUTPUT}" --allow-local-files --pdf 2>/dev/null
    echo -e "${G}[present]${R} PDF ready: ${PDF_OUTPUT}"
}

launch_demo() {
    echo ""
    echo -e "${G}╔══════════════════════════════════════════════════════╗${R}"
    echo -e "${G}║  Erlang Distribution Over Relay Mesh — Live Demo    ║${R}"
    echo -e "${G}╚══════════════════════════════════════════════════════╝${R}"
    echo ""
    echo -e "${C}Open two terminals and run:${R}"
    echo ""
    echo -e "  ${Y}Terminal 1 (Alice):${R}"
    echo -e "    cd ${SCRIPT_DIR}"
    echo -e "    MACULA_DIST_MODE=relay ERL_FLAGS=\"-proto_dist macula -no_epmd\" rebar3 shell --name alice@127.0.0.1 --setcookie DEMO"
    echo -e "    mesh_chat:connect(\"relay-cz-prague.macula.io\")."
    echo -e "    mesh_chat:join(\"lobby\")."
    echo -e "    mesh_chat:say(\"lobby\", \"Hello from Alice!\")."
    echo ""
    echo -e "  ${Y}Terminal 2 (Bob):${R}"
    echo -e "    cd ${SCRIPT_DIR}"
    echo -e "    MACULA_DIST_MODE=relay ERL_FLAGS=\"-proto_dist macula -no_epmd\" rebar3 shell --name bob@127.0.0.1 --setcookie DEMO"
    echo -e "    mesh_chat:connect(\"relay-dk-copenhagen.macula.io\")."
    echo -e "    mesh_chat:join(\"lobby\")."
    echo -e "    net_adm:ping('alice@127.0.0.1')."
    echo -e "    mesh_chat:say(\"lobby\", \"Hello from Bob!\")."
    echo ""
    echo -e "${C}Commands:${R}"
    echo -e "  mesh_chat:say(\"room\", \"msg\").           ${G}%% say in a room${R}"
    echo -e "  mesh_chat:say(\"msg\").                   ${G}%% say (if in one room)${R}"
    echo -e "  mesh_chat:whisper('node@...', \"msg\").   ${G}%% private message${R}"
    echo -e "  mesh_chat:who(\"room\").                  ${G}%% list room members${R}"
    echo -e "  mesh_chat:rooms().                      ${G}%% list your rooms${R}"
    echo -e "  mesh_chat:peers().                      ${G}%% list connected nodes${R}"
    echo -e "  mesh_chat:ping('node@...').              ${G}%% RTT + relay endpoints${R}"
    echo -e "  mesh_chat:relays().                     ${G}%% show relay connection${R}"
    echo -e "  mesh_chat:leave(\"room\").                ${G}%% leave a room${R}"
    echo -e "  mesh_chat:disconnect().                 ${G}%% disconnect from mesh${R}"
    echo ""
}

# ── Main ──────────────────────────────────────────────

ensure_deps

case "${1:-}" in
    --watch)
        build_slides
        open_slides
        watch_slides
        ;;
    --pdf)
        build_slides
        export_pdf
        ;;
    --demo)
        launch_demo
        ;;
    *)
        build_slides
        open_slides
        echo ""
        echo -e "${C}Tip:${R} Run ${Y}./present.sh --demo${R} for interactive chat instructions"
        ;;
esac
