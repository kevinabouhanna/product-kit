#!/bin/bash
# product-kit's own command: each part reaches its tool. Usage: tests/test-product-kit.sh
set -uo pipefail
KIT="$(cd "$(dirname "$0")/.." && pwd)/bin/product-kit"
fails=0
expect() { if eval "$2"; then printf '  ok    %s\n' "$1"; else printf '  FAIL  %s\n' "$1"; fails=$((fails + 1)); fi; }
expect "help names each part" '"$KIT" help | grep -q "product-kit docs" && "$KIT" help | grep -q "product-kit shots"'
expect "docs runs docs-kit" '"$KIT" docs help | grep -q "docs-kit site"'
expect "lang runs lang-kit" '"$KIT" lang help | grep -q "lang-kit review"'
expect "shots runs shots-kit" '"$KIT" shots help | grep -q "shots-kit vendor"'
expect "version names each tool's" '"$KIT" version | grep -Eq "docs [0-9.]+, lang [0-9.]+, shots [0-9.]+$"'
expect "an unknown command fails" '! "$KIT" nope 2>/dev/null'
expect "the plugin is named product-kit" 'grep -q "\"name\": \"product-kit\"" "$(dirname "$KIT")/../.claude-plugin/plugin.json"'
[ "$fails" -eq 0 ] && echo "product-kit: every test passed" || echo "product-kit: $fails failed"
exit $((fails > 0))
