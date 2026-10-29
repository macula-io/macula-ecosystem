#!/usr/bin/env sh
# Refuse a copy of the security register in this repository. The register's public edition is
# delivered only to macula-codex, signed, by macula-architecture's export job; a copy here goes
# stale the day it is written (macula-ecosystem#6). The workflow register-link.yml calls it.
#
# Usage: scripts/check_register_link.sh [repository root]
set -eu
cd "${1:-.}"
CODEX_PDF="https://github.com/macula-io/macula-codex/blob/register-pdf/SECURITY_FEATURES.pdf"
fail=0
copies="$(git ls-files | grep -i 'SECURITY_FEATURES' || true)"
if [ -n "$copies" ]; then
  echo "REFUSED: a copy of the security register is tracked here; link the signed PDF in macula-codex instead:" >&2
  echo "$copies" >&2
  fail=1
fi
links="$(git ls-files -z '*.md' | xargs -0 grep -noE '\]\([^)]*SECURITY_FEATURES[^)]*\)' || true)"
stray="$(printf '%s\n' "$links" | grep -v "($CODEX_PDF)" | grep . || true)"
if [ -n "$stray" ]; then
  echo "REFUSED: a link to the security register that is not the signed PDF in macula-codex ($CODEX_PDF):" >&2
  echo "$stray" >&2
  fail=1
fi
grep -qF "($CODEX_PDF)" README.md || { echo "REFUSED: README.md does not link the register's signed PDF ($CODEX_PDF)" >&2; fail=1; }
[ "$fail" -eq 0 ] && echo "register link: README points at the signed PDF in macula-codex, no copy here"
exit "$fail"
