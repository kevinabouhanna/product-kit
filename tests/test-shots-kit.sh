#!/bin/bash
#
# shots-kit (#6), offline: it builds, its own cases of where the asset check looks for
# media pass, and the check, the config and vendoring work on a made-up project and
# site. What needs an app and the screen (check, update, audit) isn't run here.
# Usage: tests/test-shots-kit.sh

set -uo pipefail
KIT="$(cd "$(dirname "$0")/.." && pwd)/bin/shots-kit"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fails=0
ok() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; fails=$((fails + 1)); }
expect() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }
sk() { "$KIT" "$@" 2>&1 || true; }   # its output, whatever its status

echo "--- builds, and its own cases"
expect "it builds and says its version" '"$KIT" version 2>/dev/null | grep -Eq "^[0-9]+\.[0-9]+\.[0-9]+$"'
expect "where the asset check looks for media: every case passes" '"$KIT" coverage-test | grep -q "cases passed"'

echo "--- the asset check, on a made-up project"
APP="$TMP/app"; SITE="$TMP/app-site"
mkdir -p "$APP/docs" "$SITE/assets" "$SITE/shots"
git -C "$APP" init -q
cat >"$APP/.product-kit.json" <<'EOF'
{"repo": "me/app", "site": {"url": "https://me.github.io/app/"},
 "shots": {"site": "../app-site", "repo_assets": "docs/assets.json"}}
EOF
echo '![Main](docs/main.png)' >"$APP/README.md"; : >"$APP/docs/main.png"
echo '{"assets": [{"file": "docs/main.png", "copy": "main"}]}' >"$APP/docs/assets.json"
cat >"$SITE/index.html" <<'EOF'
<img src="assets/main.png"><meta property="og:image" content="https://me.github.io/app/assets/card.png">
EOF
: >"$SITE/assets/main.png"; : >"$SITE/assets/card.png"
cat >"$SITE/shots/shots.json" <<'EOF'
{"app": "/Applications/App.app", "bundle": "me.App",
 "shots": [{"name": "main", "file": "assets/main.png", "open": [], "window": "App"}]}
EOF
out="$(cd "$APP" && sk coverage)"
expect "the site comes from shots.site, from the main checkout" '! grep -q "no site" <<<"$out"'
expect "an asset linked on the site's own address must be listed" 'grep -q "assets/card.png (index.html) isn.t listed" <<<"$out"'
cat >"$SITE/shots/shots.json" <<'EOF'
{"app": "/Applications/App.app", "bundle": "me.App",
 "shots": [{"name": "main", "file": "assets/main.png", "open": [], "window": "App"}],
 "assets": [{"file": "assets/card.png", "none": "the social card"}]}
EOF
expect "with it listed, all accounted for" '(cd "$APP" && "$KIT" coverage | grep -q "all accounted for")'
echo '![New](docs/new.png)' >>"$APP/README.md"; : >"$APP/docs/new.png"
out="$(cd "$APP" && sk coverage)"
expect "the README's list is the config's repo_assets" 'grep -q "docs/new.png (README.md) isn.t listed. Add it to docs/assets.json" <<<"$out"'
expect "problems are grouped by the config's branches" 'grep -q "^On main (the README, the docs and docs/assets.json)" <<<"$out"'
expect "--site overrides the config" '(cd "$TMP" && sk coverage --site "$SITE" --repo "$APP") | grep -q "isn.t listed"'

echo "--- vendor"
expect "vendor copies the source to Scripts/shots-kit.swift" '(cd "$APP" && "$KIT" vendor >/dev/null) && cmp -s "$APP/Scripts/shots-kit.swift" "$(dirname "$KIT")/../shots/shots-kit.swift"'
expect "vendor --check says it's this copy" '(cd "$APP" && "$KIT" vendor --check) | grep -q "is this copy"'
echo "// changed" >>"$APP/Scripts/shots-kit.swift"
expect "vendor --check fails on another copy" '! (cd "$APP" && "$KIT" vendor --check >/dev/null)'

[ "$fails" -eq 0 ] && echo "shots-kit: every test passed" || echo "shots-kit: $fails failed"
exit $((fails > 0))
