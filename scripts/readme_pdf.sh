#!/usr/bin/env sh
# Build README.pdf from README.md, diagrams included. Runs inside the pinned pandoc/extra
# image (pandoc, lualatex, rsvg-convert); the workflow readme-pdf.yml calls it.
#
# Usage: scripts/readme_pdf.sh [out.pdf]     (from the repository root)
set -eu
OUT="${1:-README.pdf}"
FONTCONFIG_FILE="$(pwd)/scripts/fonts.conf"; export FONTCONFIG_FILE
pandoc README.md \
  --from gfm+raw_html --lua-filter scripts/readme_pdf.lua \
  --pdf-engine=lualatex \
  -V geometry:margin=2.2cm -V papersize=a4 -V fontsize=11pt \
  -V colorlinks=true -V linkcolor=blue -V urlcolor=blue \
  -V title="Macula" -M title="Macula" -V subtitle="What it is, why it matters, what is built" \
  -V date="$(date -u +%Y-%m-%d)" \
  -o "$OUT"
rm -f assets/*.pdf
echo "built $OUT"
