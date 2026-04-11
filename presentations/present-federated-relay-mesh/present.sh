#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SLIDES="${SCRIPT_DIR}/SLIDES.md"
HTML="${SCRIPT_DIR}/slides.html"
PORT="${1:-8080}"

# Build HTML from Marp markdown
echo "Building slides..."
npx @marp-team/marp-cli "$SLIDES" -o "$HTML" --html

# Serve with live preview (auto-reloads on file changes)
echo ""
echo "Presenting at http://localhost:${PORT}"
echo "Press F for fullscreen, arrow keys to navigate"
echo ""
npx @marp-team/marp-cli --server "$SCRIPT_DIR" --port "$PORT" --html
