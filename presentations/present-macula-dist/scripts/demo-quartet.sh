#!/usr/bin/env bash
# Launch the four-nick geographic quartet in a tmux 2×2 grid.
#
# Layout:
#   ┌───────────────┬───────────────┐
#   │ alice @ 🇵🇹    │ charlie @ 🇩🇪  │
#   │  pt-lisbon    │  de-berlin    │
#   ├───────────────┼───────────────┤
#   │ bob   @ 🇮🇹    │ diane  @ 🇫🇷  │
#   │  it-palermo   │  fr-lyon      │
#   └───────────────┴───────────────┘
#
# All four nodes connect to different EU relay identities — so even
# though every beam runs on this machine, inter-node chat routes across
# the real macula mesh (Helsinki ↔ Nuremberg ↔ Paris physical peers).
#
# Each pane opens into an interactive mesh_chat shell already joined
# to the shared room. The operator types `mesh_chat:say("...").` in
# any pane to drive the demo.
#
# Usage:
#   ./scripts/demo-quartet.sh            # room defaults to "beatles"
#   ./scripts/demo-quartet.sh mesh
set -eu

ROOM="${1:-beatles}"
SESSION="macula-quartet"

if ! command -v tmux >/dev/null 2>&1; then
  echo "tmux not installed. apt/brew install tmux." >&2
  exit 1
fi

# Fail early if a session already exists so we don't double up.
if tmux has-session -t "${SESSION}" 2>/dev/null; then
  echo "tmux session '${SESSION}' already running."
  echo "Attach:  tmux attach -t ${SESSION}"
  echo "Or kill: tmux kill-session -t ${SESSION}"
  exit 1
fi

# 2×2 grid.
tmux new-session -d -s "${SESSION}" -x 220 -y 60 -n demo
tmux split-window -h  -t "${SESSION}:demo"
tmux split-window -v  -t "${SESSION}:demo.0"
tmux split-window -v  -t "${SESSION}:demo.2"

# Send each quadrant into its own geographic shell.
tmux send-keys -t "${SESSION}:demo.0" \
  "./scripts/shell.sh alice@host00.lab   pt-lisbon   ${ROOM}" C-m
tmux send-keys -t "${SESSION}:demo.1" \
  "./scripts/shell.sh bob@host00.lab     it-palermo  ${ROOM}" C-m
tmux send-keys -t "${SESSION}:demo.2" \
  "./scripts/shell.sh charlie@host00.lab de-berlin   ${ROOM}" C-m
tmux send-keys -t "${SESSION}:demo.3" \
  "./scripts/shell.sh diane@host00.lab   fr-lyon     ${ROOM}" C-m

tmux select-pane -t "${SESSION}:demo.0"
exec tmux attach -t "${SESSION}"
