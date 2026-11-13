#!/bin/bash
#
# The proof (#47): a new Mac app from nothing, set up by `product-kit init` with a second
# language and a website folder, its plan, docs, README, site and pictures (drawn by the app,
# out of sight), every check passing, and `product-kit status` saying all is current, in one
# run. GitHub's part (the plan's board) is the one thing left out (`--offline`).
# Usage: tests/test-prove.sh

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PK="$ROOT/bin/product-kit"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fails=0
ok() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; fails=$((fails + 1)); }
expect() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
export PATH="$ROOT/bin:$PATH"

echo "--- a Mac app, nothing of product-kit's yet"
A="$TMP/tally"; mkdir -p "$A/Resources/en.lproj" "$A/Resources/fr.lproj"
git -C "$A" init -q; git -C "$A" remote add origin https://github.com/me/tally.git
cp "$ROOT/tests/fixtures/mac-app/Tally.swift" "$A/Tally.swift"
printf '#!/bin/bash\n# Builds Tally: a Mac app, its Info.plist written by this script.\nset -e\nswiftc -parse-as-library Tally.swift -o tally 2>/dev/null\n# LSMinimumSystemVersion 14.0\n' >"$A/build.sh"
chmod +x "$A/build.sh"
printf '"Count" = "Count";\n"Today" = "Today";\n' >"$A/Resources/en.lproj/Localizable.strings"
printf '"Count" = "Compter";\n"Today" = "Aujourd’hui";\n' >"$A/Resources/fr.lproj/Localizable.strings"
git -C "$A" add -A && git -C "$A" commit -q -m "Tally"
run() { (cd "$A" && "$@" 2>&1) || true; }

echo "--- one command"
out="$(run python3 -I "$PK" init --name Tally --pitch "Count what you count, every day." --languages en,fr --site folder:site)"
expect "init sets it up: a Mac app, two languages, a website folder" \
  'grep -q "init: Tally (mac)" <<<"$out" && [ -f "$A/site/index.html" ] && [ -f "$A/README.fr.md" ] && [ -f "$A/docs/PLAN.md" ] && grep -q "Resources/{code}.lproj/Localizable.strings" "$A/.product-kit.json"'

echo "--- what the owner and Claude write"
# The pictures the app draws, listed with the site's pages that show them.
cat >"$A/site/shots/shots.json" <<'EOF'
{"render": {"build": ["./build.sh"], "command": ["./tally", "--snapshot", "{out}"]},
 "shots": [{"name": "home", "file": "assets/home.png", "render": "home.png"},
           {"name": "home-fr", "file": "assets/fr/home.png", "render": "home-fr.png"}],
 "assets": []}
EOF
python3 - "$A/site/index.html" <<'EOF'
import sys
p = sys.argv[1]; s = open(p).read()
s = s.replace("</body>", '<img src="assets/home.png" alt="Tally\'s window"></body>')
open(p, "w").write(s)
EOF
mkdir -p "$A/site/fr" "$A/docs/fr"
printf '<!doctype html><html lang="fr"><head><meta name="viewport" content="width=device-width"><style>img { max-width: 100%; height: auto; }</style></head><body><h1>Tally</h1><img src="../assets/fr/home.png" alt="La fenêtre de Tally"><a href="../index.html">English</a></body></html>\n' >"$A/site/fr/index.html"
printf '# Tally\n\n<!-- product-kit: pitch --><!-- /product-kit -->\n' >"$A/README.fr.md"
python3 - "$A/.product-kit.json" <<'EOF'
import json, sys
c = json.load(open(sys.argv[1]))
c["languages"]["fr"] = {"name": "Français", "site": "fr"}
c["facts"]["pitch"] = {"en": "Count what you count, every day.", "fr": "Comptez ce que vous comptez, chaque jour."}
json.dump(c, open(sys.argv[1], "w"), indent=2, ensure_ascii=False)
EOF
printf '# La documentation de Tally\n' >"$A/docs/fr/README.md"
out="$(run shots-kit update)"
expect "the app draws its pictures, out of sight, in both languages" '[ -s "$A/site/assets/home.png" ] && [ -s "$A/site/assets/fr/home.png" ]'
git -C "$A" add -A && git -C "$A" commit -q -m "first version" && git -C "$A" tag v1.0.0
run python3 -I "$PK" facts --write >/dev/null
git -C "$A" add -A && git -C "$A" commit -q -m "facts"

echo "--- every check"
expect "the pictures are as drawn" 'run shots-kit check | grep -q "all 2 pictures are as drawn"'
expect "every picture on the site is listed" 'run shots-kit coverage | grep -q "all accounted for"'
expect "every language's text is whole" 'run python3 -I "$ROOT/bin/lang-kit" strings | grep -q "Français (fr): all 2 pieces of text"'
expect "every fact is the same everywhere, in each page's language" \
  'run python3 -I "$PK" facts | grep -q "spots are current" && grep -q "Comptez ce que vous comptez" "$A/README.fr.md" && grep -q "1.0.0" "$A/site/index.html"'
expect "the site's pages open, their pictures load, nothing spills out" \
  'out="$(run python3 -I "$PK" site check)"; grep -q "every picture loads" <<<"$out" || grep -q "skipped" <<<"$out" || ! ls ~/Library/Caches/ms-playwright/chromium_headless_shell-*/ >/dev/null 2>&1'
expect "the doctor finds nothing unaccounted for" 'run python3 -I "$PK" doctor | grep -q "nothing unaccounted for"'
expect "and status says it's all current" 'run python3 -I "$PK" status --offline --base HEAD | grep -q "status: tally: all current"'

[ "$fails" -eq 0 ] && echo "prove: every test passed" || { echo "prove: $fails failed"; }
exit $((fails > 0))
