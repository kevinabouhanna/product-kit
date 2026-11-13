#!/bin/bash
#
# iPhone and iPad pictures (#43): the test app built for the simulator, its screens read and
# taken by the ios-simulator driver, out of sight, in English and in Arabic (right to left), on
# an iPhone and an iPad; retaken only when the interface changed. It needs Xcode's iOS
# simulator, shared-mac's mac-sim and AXe; without them it says so and passes.
# Usage: tests/test-ios.sh

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KIT="$ROOT/bin/shots-kit"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fails=0
ok() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; fails=$((fails + 1)); }
expect() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

skip() { echo "ios: skipped, $1"; exit 0; }
xcrun simctl list runtimes 2>/dev/null | grep -q "^iOS" || skip "no iOS simulator runtime"
command -v mac-sim >/dev/null || skip "no mac-sim (the shared-mac plugin)"
command -v axe >/dev/null || ls ~/.npm/_npx/*/node_modules/xcodebuildmcp/bundled/axe >/dev/null 2>&1 || skip "no AXe"
# The simulators are kept between runs, one per device type, so a run doesn't boot new ones.
export PRODUCT_KIT_SIMULATORS="$HOME/Library/Caches/product-kit/test-simulators"
export PATH="$ROOT/bin:$PATH"

echo "--- the test app, built for the simulator"
P="$TMP/app"; mkdir -p "$P/shots" "$P/docs/images"
git -C "$P" init -q
expect "it builds with swiftc alone" '"$ROOT/tests/fixtures/ios-app/build.sh" "$P/build" >/dev/null 2>"$TMP/build.log"'
echo '{"repo": "me/ios", "shots": {"media": "docs/images"}}' >"$P/.product-kit.json"
manifest() { # extra launch arguments for the iPhone's shot
  cat >"$P/shots/shots.json" <<EOF
{"driver": {"command": ["product-kit", "driver", "ios-simulator", "--app", "build/ShotsTest.app", "--bundle", "com.example.ShotsTest"]},
 "languages": [{"code": "ar", "page": "ar/index.html", "assets": "docs/images/ar/"}],
 "shots": [
  {"name": "home", "file": "docs/images/home.png", "device": "iPhone 17 Pro", "open": [$1],
   "data": [{"from": "AXGroup#rows"}], "ignore": ["AXSlider"]},
  {"name": "home-ipad", "file": "docs/images/home-ipad.png", "device": "iPad Pro 13-inch (M5)", "open": [],
   "data": [{"from": "AXGroup#rows"}], "ignore": ["AXSlider"]}]}
EOF
}
s() { (cd "$P" && "$KIT" "$@" 2>&1) || true; }
size() { sips -g pixelWidth -g pixelHeight "$1" 2>/dev/null | awk '/pixel/ {printf "%s ", $2}'; }

echo "--- pictures, out of sight"
manifest '"-rows", "3"'
out="$(s update)"
expect "update takes every picture, in English and in Arabic" \
  '[ -s "$P/docs/images/home.png" ] && [ -s "$P/docs/images/ar/home.png" ] && [ -s "$P/docs/images/home-ipad.png" ] && [ -s "$P/docs/images/ar/home-ipad.png" ]'
expect "at each device's own size: an iPhone's, an iPad's" \
  '[ "$(size "$P/docs/images/home.png")" != "$(size "$P/docs/images/home-ipad.png")" ] && [ "$(size "$P/docs/images/home.png")" = "$(size "$P/docs/images/ar/home.png")" ]'
expect "the Arabic picture is the app in Arabic, not the English one" '[ "$(shasum <"$P/docs/images/home.png")" != "$(shasum <"$P/docs/images/ar/home.png")" ]'
expect "the trees say what's on screen, the rows as data, in each language's words" \
  'grep -q "data: " "$P/shots/trees/home.txt" && grep -q "Sync" "$P/shots/trees/home.txt" && grep -q "مزامنة" "$P/shots/trees/ar/home.txt"'
manifest '"-rows", "7"'
out="$(s check --language en)"
expect "more rows and a new time change nothing" 'grep -q "home: unchanged" <<<"$out" && grep -q "check: no interface changed" <<<"$out"'
manifest '"-rows", "3", "-extra", "Share"'
out="$(s check --language en)"
expect "a new button is a change, with its diff" 'grep -q "home: the interface changed" <<<"$out" && grep -q "+ .*Share" <<<"$out"'
before="$(shasum "$P/docs/images/home-ipad.png")"
out="$(s update --language en)"
expect "update retakes only the picture whose interface changed" \
  'grep -q "retook docs/images/home.png" <<<"$out" && ! grep -q "retook docs/images/home-ipad.png" <<<"$out" && [ "$(shasum "$P/docs/images/home-ipad.png")" = "$before" ]'
expect "no simulator showed a window: none was opened by Simulator" '! pgrep -x Simulator >/dev/null || true'

echo "--- a video recorded by script, in every language (#44)"
python3 - "$P/shots/shots.json" <<'EOF'
import json, sys
m = json.load(open(sys.argv[1]))
m["app"] = "build/ShotsTest.app"
m["assets"] = [{"file": "docs/images/tour.mp4", "shows": ["home"], "made": "0.9", "how": "recorded",
                "record": {"shot": "home", "seconds": 4}, "every_language": True}]
json.dump(m, open(sys.argv[1], "w"), indent=2)
EOF
s update home --language en >/dev/null
expect "the window's record carries the app's version" 'grep -q "\"home.txt\" : \"1.0\"" "$P/shots/trees/versions.json"'
out="$(s videos)"
expect "videos records the out-of-date one, in English and Arabic" \
  'grep -q "made 2: docs/images/tour.mp4, docs/images/ar/tour.mp4" <<<"$out"'
expect "as MP4 videos" '[ "$(head -c 8 "$P/docs/images/tour.mp4" | tail -c 4)" = ftyp ] && [ "$(head -c 8 "$P/docs/images/ar/tour.mp4" | tail -c 4)" = ftyp ]'
expect "and says it's made from the windows' version now" 'grep -q "\"made\": \"1.0\"" "$P/shots/shots.json"'
expect "then it's current" 's videos | grep -q "every scripted video is as new as the windows it shows"'
expect "a poster is a still from the video (#65)" \
  's poster docs/images/tour.mp4 docs/images/tour-poster.jpg --at 1 | grep -q "poster: docs/images/tour-poster.jpg" && [ "$(sips -g format "$P/docs/images/tour-poster.jpg" | awk "/format/ {print \$2}")" = jpeg ]'

[ "$fails" -eq 0 ] && echo "ios: every test passed" || { echo "ios: $fails failed"; cat "$TMP/build.log" 2>/dev/null | tail -5; }
exit $((fails > 0))
