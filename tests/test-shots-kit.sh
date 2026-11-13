#!/bin/bash
#
# shots-kit (#6), offline: it builds, its own cases of where the asset check looks for
# media pass, and the check, the config and vendoring work on a made-up project and
# site; on a made-up project with no site that draws its own pictures (#8),
# check and update too; and a run in a VM (#10) with a stand-in for mac-vm. What needs an app and the screen isn't run here.
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
expect "the masks, in six languages: every case passes" '"$KIT" mask-test | grep -q "cases passed"'

echo "--- the masks, from a project's config (#32)"
MASKED="$TMP/masked"; mkdir -p "$MASKED"
cat >"$MASKED/.product-kit.json" <<'EOF'
{"repo": "me/masked", "languages": {"fr": {"name": "Français"}},
 "shots": {"masks": [{"pattern": "[$€]#", "as": "‹money›"}, {"pattern": "#\\s?%", "as": "‹percent›"}]}}
EOF
expect "French dates are masked once French is one of the project's languages" \
  '[ "$(echo "Mis à jour lundi 3 mars à 17:51" | "$KIT" mask --repo "$MASKED")" = "Mis à jour ‹day› # ‹month› à #" ]'
expect "the project's own masks follow, in order" \
  '[ "$(echo "Total €12.50 and 80 %" | "$KIT" mask --repo "$MASKED")" = "Total ‹money› and ‹percent›" ]'
expect "without them, a project's units aren't masked" \
  '[ "$(echo "12.3 MB/s on Monday" | "$KIT" mask --repo "$TMP")" = "# MB/s on ‹day›" ]'
echo '{"repo": "me/bad", "shots": {"masks": [{"pattern": "[unclosed", "as": "x"}]}}' >"$TMP/bad.json"
mkdir -p "$TMP/bad"; mv "$TMP/bad.json" "$TMP/bad/.product-kit.json"
expect "a mask that isn't a pattern is named, not ignored" \
  'echo x | sk mask --repo "$TMP/bad" | grep -q "shots.masks: \[unclosed"'

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

echo "--- in a VM (#10), with a stand-in for mac-vm that changes files as a run inside would"
FAKE="$TMP/fake"; mkdir -p "$FAKE/bin" "$TMP/App.app/Contents"
echo '<plist><dict/></plist>' >"$TMP/App.app/Contents/Info.plist"
cat >"$FAKE/bin/mac-vm" <<'STUB'
#!/bin/bash
printf '%s\n' "$@" >"$FAKE/args"
share=""
while [ $# -gt 0 ]; do case "$1" in --share) share="$2"; shift 2 ;; --display) shift 2 ;; --) shift; break ;; *) shift ;; esac; done
printf '%s' "${@: -1}" >"$FAKE/script"
(cd "$share" && find . -type f | sort) >"$FAKE/shared"
mkdir -p "$share/site/shots/trees"; echo tree >"$share/site/shots/trees/main.txt"
echo retaken >"$share/site/assets/main.png"
echo "another session's change" >>"$SITE/index.html"
exit "${FAKE_STATUS:-0}"
STUB
chmod +x "$FAKE/bin/mac-vm"
export FAKE SITE
out="$(cd "$APP" && PATH="/usr/bin:/bin" sk check --vm)"
expect "--vm without mac-vm says what it needs" 'grep -q "needs mac-vm on PATH" <<<"$out"'
cp "$SITE/index.html" "$TMP/index.before"
out="$(cd "$APP" && PATH="$FAKE/bin:$PATH" FAKE_STATUS=3 "$KIT" update main --vm --app "$TMP/App.app" 2>&1)"; status=$?
expect "it runs in a clone with a 3200x2000 screen, and exits with the run's status" 'grep -qx -- "--display" "$FAKE/args" && grep -qx 3200x2000 "$FAKE/args" && [ "$status" = 3 ]'
expect "the tool, the zipped app, the site and the project go in" 'grep -qx "./shots-kit" "$FAKE/shared" && grep -qx "./app.zip" "$FAKE/shared" && grep -qx "./site/shots/shots.json" "$FAKE/shared" && grep -qx "./repo/.product-kit.json" "$FAKE/shared" && ! grep -q "/.git/" "$FAKE/shared"'
expect "inside, the app goes where the manifest says, and the run takes the screen whenever, with the site's copy" \
  'grep -q "^app=./Applications/App.app.$" "$FAKE/script" && grep -q "MAC_LANE_IDLE=0 .*SHOTS_KIT_IN_VM=1 .*shots-kit. .update. .main. --repo .*--site" "$FAKE/script"'
expect "what the run changed or added comes back" '[ "$(cat "$SITE/assets/main.png")" = retaken ] && [ "$(cat "$SITE/shots/trees/main.txt")" = tree ] && grep -q "Brought back from the VM" <<<"$out"'
expect "a file it didn't change keeps what changed here meanwhile" 'grep -q "another session.s change" "$SITE/index.html"'
# This run's own folder, as handed to mac-vm: another run's may come and go meanwhile (two CI runs at once).
share_dir="$(grep -A1 -x -- --share "$FAKE/args" | tail -n 1)"
expect "the shared folder is removed afterwards" '[ -n "$share_dir" ] && [ ! -e "$share_dir" ]'
cp "$TMP/index.before" "$SITE/index.html"; : >"$SITE/assets/main.png"; rm -rf "$SITE/shots/trees"
echo data >"$TMP/history.db"
cat >"$APP/.product-kit.json" <<EOF
{"repo": "me/app", "shots": {"site": "../app-site", "repo_assets": "docs/assets.json",
 "vm": {"default": true, "display": "2400x1600", "files": ["$TMP/history.db", "~/no-such-file-here"], "setup": "./first-run.sh",
        "image": "myapp", "prepare": "pwd >\"\$SHOTS_VM_DIR/made-here.txt\""}}}
EOF
out="$(cd "$APP" && PATH="$FAKE/bin:$PATH" sk check --app "$TMP/App.app")"
expect "vm.default runs in a VM without --vm, with the config's display" 'grep -qx 2400x1600 "$FAKE/args"'
expect "vm.files go in and to the same place, and a missing one is said" \
  'grep -qx "./files/0/history.db" "$FAKE/shared" && grep -q "ditto \"\$s\"/files/0/.history.db. .$TMP/history.db.$" "$FAKE/script" && grep -q "no-such-file-here isn.t on this Mac" <<<"$out"'
expect "vm.setup runs inside, from the project, before the pictures" 'grep -q "^SHOTS_APP=\"\$app\" /bin/bash -c .\./first-run.sh.$" "$FAKE/script"'
expect "vm.image clones the project's image (#12)" 'grep -qx -- "--image" "$FAKE/args" && grep -qx myapp "$FAKE/args"'
expect "vm.prepare runs here, in the project, and what it writes goes in" 'grep -qx "./prepared/made-here.txt" "$FAKE/shared"'
expect "inside, setup finds it in SHOTS_VM_DIR" 'grep -q "^export SHOTS_VM_DIR=\"\$s/prepared\"$" "$FAKE/script"'
expect "the same app is kept, the app quit first, and settings read again from the files placed" \
  'grep -q "diff -rq \"\$app\"" "$FAKE/script" && grep -q "to quit" "$FAKE/script" && grep -q "killall -u \"\$USER\" cfprefsd" "$FAKE/script"'
rm -f "$FAKE/args"
(cd "$APP" && PATH="$FAKE/bin:$PATH" "$KIT" check nothing --here --app "$TMP/App.app" >/dev/null 2>&1)
(cd "$APP" && PATH="$FAKE/bin:$PATH" "$KIT" coverage >/dev/null 2>&1)
expect "--here, and the commands that read files only, stay on this Mac" '[ ! -f "$FAKE/args" ]'
cp "$TMP/index.before" "$SITE/index.html"; : >"$SITE/assets/main.png"; rm -rf "$SITE/shots/trees"

echo "--- a project with no site, whose app draws its own pictures (#8)"
DP="$TMP/drawn"
mkdir -p "$DP/docs" "$DP/shots" "$DP/v/old" "$DP/v/new"
git -C "$DP" init -q
echo '{"repo": "me/drawn"}' >"$DP/.product-kit.json"
# A 4×4 PNG of one colour, with a pixel of another, at a compression level.
png() { python3 -I -c 'import sys, zlib, struct
path, rgb, odd, level = sys.argv[1], bytes.fromhex(sys.argv[2]), bytes.fromhex(sys.argv[3]), int(sys.argv[4])
rows = b"".join(b"\0" + b"".join((odd if (x, y) == (1, 1) else rgb) + b"\xff" for x in range(4)) for y in range(4))
chunk = lambda kind, data: struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
open(path, "wb").write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 4, 4, 8, 6, 0, 0, 0))
    + chunk(b"IDAT", zlib.compress(rows, level)) + chunk(b"IEND", b""))' "$@"; }
png "$DP/v/old/main.png" 336699 336699 9; png "$DP/v/old/other.png" ffffff ffffff 9
png "$DP/v/new/main.png" 336699 ff0000 9; png "$DP/v/new/other.png" ffffff ffffff 1
cp "$DP/v/old/main.png" "$DP/docs/main.png"; cp "$DP/v/old/other.png" "$DP/docs/other.png"; : >"$DP/docs/logo.png"
echo old >"$DP/v/which"
printf '![Main](docs/main.png) ![Other](docs/other.png) ![Logo](docs/logo.png)\n' >"$DP/README.md"
echo 'echo built >built.txt' >"$DP/build.sh"
echo 'cp v/$(cat v/which)/*.png "$1"/' >"$DP/draw.sh"
cat >"$DP/shots/shots.json" <<'EOF2'
{"render": {"build": ["sh", "build.sh"], "command": ["sh", "draw.sh", "{out}"]},
 "shots": [{"name": "main", "file": "docs/main.png", "render": "main.png"},
           {"name": "other", "file": "docs/other.png", "render": "other.png"}],
 "assets": [{"file": "docs/logo.png", "none": "the icon"}]}
EOF2
expect "coverage: the README's pictures are the repo's manifest's" '(cd "$DP" && "$KIT" coverage) | grep -q "3 assets in the README and docs, all accounted for"'
: >"$DP/docs/new.png"; echo '![New](docs/new.png)' >>"$DP/README.md"
out="$(cd "$DP" && sk coverage)"
expect "coverage: an unlisted one goes in shots/shots.json, on main" 'grep -q "docs/new.png (README.md) isn.t listed. Add it to shots/shots.json" <<<"$out" && grep -q "^On main (the README, the docs and shots/shots.json)" <<<"$out"'
sed -i '' '$d' "$DP/README.md"; rm "$DP/docs/new.png"
out="$(cd "$DP" && sk check)"; status=$(cd "$DP" && "$KIT" check >/dev/null 2>&1; echo $?)
expect "check builds, draws, and finds every picture as drawn" '[ -f "$DP/built.txt" ] && grep -q "check: all 2 pictures are as drawn" <<<"$out" && [ "$status" = 0 ]'
echo new >"$DP/v/which"
cat >"$DP/shots/shots.json" <<'EOF2'
{"render": {"build": ["sh", "build.sh"], "command": ["sh", "draw.sh", "{out}"]},
 "shots": [{"name": "main", "file": "docs/main.png", "render": "main.png"},
           {"name": "other", "file": "docs/other.png", "render": "other.png"}],
 "assets": [{"file": "docs/logo.png", "none": "the icon"}, {"file": "docs/tour.gif", "shows": ["main"], "made": "1.0"}]}
EOF2
out="$(cd "$DP" && sk check)"; status=$(cd "$DP" && "$KIT" check >/dev/null 2>&1; echo $?)
expect "a pixel that differs is a change, and fails the check" 'grep -q "main: changed: 1 pixels differ, within 1×1 at (1, 1) of 4×4" <<<"$out" && [ "$status" = 1 ]'
expect "the same pixels, written differently, aren't" 'grep -q "^other: unchanged" <<<"$out"'
expect "what's made by hand from a changed window is named" 'grep -q "docs/tour.gif (shows main)" <<<"$out"'
out="$(cd "$DP" && sk update)"
expect "update copies the drawing over the picture" 'grep -q "update: redrew 1 of 2" <<<"$out" && cmp -s "$DP/v/new/main.png" "$DP/docs/main.png"'
expect "then the check passes" '(cd "$DP" && "$KIT" check >/dev/null 2>&1)'
expect "a name that's no shot is refused" '(cd "$DP" && sk check nothing) | grep -q "no shot named nothing"'
expect "tree is for an app's windows only" '(cd "$DP" && sk tree main) | grep -q "not for pictures the project draws itself"'
echo 'exit 3' >"$DP/draw.sh"
out="$(cd "$DP" && sk check)"; status=$(cd "$DP" && "$KIT" check >/dev/null 2>&1; echo $?)
expect "a drawing that fails says so" 'grep -q "the drawing failed (exit 3)" <<<"$out" && [ "$status" = 2 ]'
echo ': "$1"' >"$DP/draw.sh"
expect "a drawing it didn't make is named" '(cd "$DP" && sk check) | grep -q "main: the drawing made no main.png"'
rm "$DP/shots/shots.json"
expect "no manifest and no site: it says where to put one" '(cd "$DP" && sk coverage) | grep -q "put it in the project.s checkout"'

echo "--- vendor"
expect "vendor copies the source to Scripts/shots-kit.swift" '(cd "$APP" && "$KIT" vendor >/dev/null) && cmp -s "$APP/Scripts/shots-kit.swift" "$(dirname "$KIT")/../shots/shots-kit.swift"'
expect "vendor --check says it's this copy" '(cd "$APP" && "$KIT" vendor --check) | grep -q "is this copy"'
echo "// changed" >>"$APP/Scripts/shots-kit.swift"
expect "vendor --check fails on another copy" '! (cd "$APP" && "$KIT" vendor --check >/dev/null)'
expect "without its own rules, the project gets product-kit's beside the tool" 'cmp -s "$APP/Scripts/AccessibilityAudit.swift" "$(dirname "$KIT")/../shots/AccessibilityAudit.swift"'
(cd "$APP" && "$KIT" vendor >/dev/null); echo "// changed" >>"$APP/Scripts/AccessibilityAudit.swift"
expect "vendor --check fails on another copy of the rules" '(cd "$APP" && sk vendor --check) | grep -q "AccessibilityAudit.swift isn.t this copy"'

[ "$fails" -eq 0 ] && echo "shots-kit: every test passed" || echo "shots-kit: $fails failed"
exit $((fails > 0))
