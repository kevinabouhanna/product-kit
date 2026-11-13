#!/bin/bash
#
# Web pages and apps built on web views (#46): a made-up page served for the run (`serve`),
# read and pictured by the web driver in a headless Chrome; and the site check on a made-up
# site. It needs Playwright's headless Chrome; without it, it says so and passes.
# Usage: tests/test-web.sh

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KIT="$ROOT/bin/shots-kit"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fails=0
ok() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; fails=$((fails + 1)); }
expect() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }
ls ~/Library/Caches/ms-playwright/chromium_headless_shell-*/chrome-headless-shell-*/chrome-headless-shell >/dev/null 2>&1 \
  || { echo "web: skipped, no headless Chrome"; exit 0; }
export PATH="$ROOT/bin:$PATH"

echo "--- a page served for the run, read and pictured"
P="$TMP/app"; mkdir -p "$P/web" "$P/shots" "$P/docs/images"
git -C "$P" init -q
echo '{"repo": "me/web", "shots": {"media": "docs/images"}}' >"$P/.product-kit.json"
page() { # the page, with one more button when given its title
  cat >"$P/web/index.html" <<EOF
<!doctype html><html lang="en"><head><meta charset="utf-8"><title>Lights</title></head>
<body><main><h1>Lights</h1><p>Updated at 9:41 AM</p>
<label><input type="checkbox" checked> Night mode</label>
<ul aria-label="Rooms">$(for i in $(seq 1 "$1"); do printf '<li>Room %s</li>' "$i"; done)</ul>
${2:+<button>$2</button>}</main></body></html>
EOF
}
cat >"$P/shots/shots.json" <<'EOF'
{"driver": {"command": ["product-kit", "driver", "web"],
            "serve": ["python3", "-I", "-m", "http.server", "{port}", "--bind", "127.0.0.1", "--directory", "web"],
            "ready": "http://127.0.0.1:{port}/"},
 "shots": [{"name": "lights", "file": "docs/images/lights.png", "url": "/index.html", "viewport": [400, 300],
            "data": [{"from": "AXList:Rooms"}]}]}
EOF
w() { (cd "$P" && "$KIT" "$@" 2>&1) || true; }
page 3
out="$(w update)"
expect "update serves the page, reads it and takes its picture at twice its size" \
  'grep -q "serving: python3" <<<"$out" && grep -q "retook docs/images/lights.png (800×600)" <<<"$out"'
expect "the tree is the page's, in the Mac's names, the rooms as data" \
  'grep -q "AXHeading description=\"Lights\"" "$P/shots/trees/lights.txt" && grep -q "AXCheckBox" "$P/shots/trees/lights.txt" && grep -q "data: " "$P/shots/trees/lights.txt"'
page 5
expect "more rooms and another time change nothing" 'w check | grep -q "lights: unchanged"'
page 3 "Turn all off"
out="$(w check)"
expect "a new button is a change, with its diff" 'grep -q "lights: the interface changed" <<<"$out" && grep -q "+ .*AXButton description=\"Turn all off\"" <<<"$out"'
expect "the server is stopped once the run ends" '! pgrep -f "http.server.*--directory web" >/dev/null'

echo "--- the site check"
S="$TMP/site"; mkdir -p "$S/zh"
printf '<!doctype html><html><head><meta name="viewport" content="width=device-width"></head><body><img src="logo.png"><a href="zh/index.html">中文</a></body></html>' >"$S/index.html"
printf '<!doctype html><html lang="zh"><head><meta name="viewport" content="width=device-width"></head><body><div style="width:900px">很宽</div><a href="../gone.html">x</a></body></html>' >"$S/zh/index.html"
out="$(python3 -I "$ROOT/drivers/web" --check-site "$S" --languages en,zh-Hans --sites zh-Hans=zh 2>&1)"
expect "a picture that doesn't load is named" 'grep -q "index.html (en, 390px wide): a picture doesn.t load: logo.png" <<<"$out"'
expect "a page that spills out at a phone's width, and only there" 'grep -q "zh/index.html (zh-Hans, 390px wide): it spills out sideways" <<<"$out" && ! grep -q "zh/index.html (zh-Hans, 1280px wide): it spills" <<<"$out"'
expect "a link that goes nowhere" 'grep -q "zh/index.html (zh-Hans): a link goes nowhere: /gone.html" <<<"$out"'
python3 -c 'import base64,sys; open(sys.argv[1],"wb").write(base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="))' "$S/logo.png"
printf '<!doctype html><html lang="zh"><head><meta name="viewport" content="width=device-width"></head><body><p>好</p><a href="../index.html">English</a></body></html>' >"$S/zh/index.html"
expect "then it passes" 'python3 -I "$ROOT/drivers/web" --check-site "$S" --languages en,zh-Hans --sites zh-Hans=zh | grep -q "every picture loads, every link goes somewhere, nothing spills out"'

[ "$fails" -eq 0 ] && echo "web: every test passed" || echo "web: $fails failed"
exit $((fails > 0))
