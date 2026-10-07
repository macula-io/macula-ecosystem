#!/usr/bin/env bash
# Build an A4 PDF from one Markdown file (pandoc + xelatex, Liberation fonts).
#
# Usage: scripts/md_to_pdf.sh <input.md> [title] [date]     -> dist/<input-basename>.pdf
# e.g.   scripts/md_to_pdf.sh FEATURES.md "What Macula does today"
#
# Strips pandoc's unconditional \usepackage{lmodern} so xelatex does not need the Latin
# Modern .tfm files (texlive-fontsrecommended).
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 <input.md> [title] [date]" >&2
  exit 1
fi
INPUT="$(realpath "$1")"
TITLE="${2:-$(basename "$INPUT" .md)}"
DATE="${3:-$(date +%Y-%m-%d)}"
DIST="$(pwd)/dist"
mkdir -p "$DIST"

BASE="$(basename "$INPUT" .md)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pandoc --standalone --pdf-engine=xelatex \
  -V geometry:margin=2.5cm -V papersize=a4 -V fontsize=11pt \
  -V colorlinks=true -V linkcolor=blue -V urlcolor=blue --highlight-style=tango \
  -V mainfont="Liberation Sans" -V monofont="Liberation Mono" -V sansfont="Liberation Sans" \
  -V title="$TITLE" -V date="$DATE" --toc --toc-depth=2 -V toc-title="Contents" \
  --resource-path="$(dirname "$INPUT"):$(dirname "$INPUT")/assets" \
  -o "$TMP/$BASE.tex" "$INPUT"
sed -i '/^\\usepackage{lmodern}$/d' "$TMP/$BASE.tex"

cd "$TMP"
for _ in 1 2; do xelatex -interaction=nonstopmode -halt-on-error "$BASE.tex" >/dev/null 2>&1 || true; done
[ -f "$BASE.pdf" ] || { echo "PDF build failed: inspect $TMP/$BASE.tex" >&2; trap - EXIT; exit 1; }
cp "$BASE.pdf" "$DIST/$BASE.pdf"
echo "Done: $DIST/$BASE.pdf"
