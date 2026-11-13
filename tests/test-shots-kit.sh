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
expect "vendor copies the source to Scripts/shots-kit.swift" '(cd "$APP" && "$KIT" vendor >/dev/null) && "$KIT" source | cmp -s - "$APP/Scripts/shots-kit.swift"'
expect "vendor --check says it's this copy" '(cd "$APP" && "$KIT" vendor --check) | grep -q "is this copy"'
echo "// changed" >>"$APP/Scripts/shots-kit.swift"
expect "vendor --check fails on another copy" '! (cd "$APP" && "$KIT" vendor --check >/dev/null)'
expect "without its own rules, the project gets product-kit's beside the tool" 'cmp -s "$APP/Scripts/AccessibilityAudit.swift" "$(dirname "$KIT")/../shots/AccessibilityAudit.swift"'
(cd "$APP" && "$KIT" vendor >/dev/null); echo "// changed" >>"$APP/Scripts/AccessibilityAudit.swift"
expect "vendor --check fails on another copy of the rules" '(cd "$APP" && sk vendor --check) | grep -q "AccessibilityAudit.swift isn.t this copy"'
expect "the one file it vendors builds on its own" \
  '"$KIT" source >"$TMP/one.swift" && swiftc -parse-as-library "$TMP/one.swift" "$(dirname "$KIT")/../shots/AccessibilityAudit.swift" -o "$TMP/one" 2>/dev/null && [ "$("$TMP/one" version)" = "$("$KIT" version)" ]'

echo "--- a driver of the project's choosing (#35): the core, with no app and no screen"
DRV="$TMP/driven"; mkdir -p "$DRV/shots" "$DRV/docs/images"
git -C "$DRV" init -q
echo '{"repo": "me/driven", "shots": {"media": "docs/images"}}' >"$DRV/.product-kit.json"
cat >"$DRV/shots/shots.json" <<'EOF'
{"driver": {"command": ["./driver.sh"]},
 "languages": [{"code": "fr", "page": "fr/index.html", "assets": "docs/images/fr/"}],
 "shots": [{"name": "home", "file": "docs/images/home.png",
            "data": [{"from": "AXList"}], "ignore": ["AXStaticText:Syncing"]}],
 "assets": [{"file": "docs/images/tour.gif", "shows": ["home"], "made": "1.0"}]}
EOF
# The screen the stand-in driver shows: a title, a time, a list of rows, a line that comes and goes.
screen() { # time, rows, then an extra button's title or nothing
  local rows="" i; for ((i = 0; i < $2; i++)); do rows+='{"role": "AXStaticText", "value": "Row '"$i"'", "frame": [0, 0, 100, 20]},'; done
  local extra=""; [ -n "${3:-}" ] && extra=', {"role": "AXButton", "title": "'"$3"'", "frame": [0, 0, 80, 30]}'
  cat >"$DRV/screen.json" <<EOF
{"role": "AXWindow", "title": "Home", "frame": [0, 0, 400, 300], "children": [
  {"role": "AXStaticText", "value": "Updated $1", "frame": [0, 0, 120, 17]},
  {"role": "AXStaticText", "value": "Syncing…", "frame": [0, 0, 60, 17]},
  {"role": "AXList", "frame": [0, 0, 380, 200], "children": [${rows%,}]},
  {"role": "AXCheckBox", "title": "Sync", "value": 1, "frame": [0, 0, 60, 20]}$extra]}
EOF
}
cat >"$DRV/driver.sh" <<'EOF'
#!/bin/bash
# A stand-in driver: answers with screen.json, writes a picture for a take, logs each request.
req="$(cat)"; echo "$req" >>requests.log
[ -f fail ] && { echo "the simulator isn't booted" >&2; exit 3; }
[ -f skip ] && { echo '{"skipped": "the screen needs a signed-in account"}'; exit 0; }
pic="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("picture", ""))' "$req")"
[ -n "$pic" ] && echo "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==" | base64 -d >"$pic"
printf '{"window": %s}\n' "$(cat screen.json)"
EOF
chmod +x "$DRV/driver.sh"
d() { (cd "$DRV" && "$KIT" "$@" 2>&1) || true; }
screen "5:51 PM" 3
expect "check, with nothing recorded yet, says so" 'd check | grep -q "home: no tree recorded yet"'
d update >/dev/null
expect "update records the tree and the picture the driver took, in every language" \
  '[ -f "$DRV/shots/trees/home.txt" ] && [ -f "$DRV/shots/trees/fr/home.txt" ] && [ -s "$DRV/docs/images/home.png" ] && [ -s "$DRV/docs/images/fr/home.png" ]'
expect "the driver is told the language and the shot" \
  'grep -q "\"language\":\"fr\"" "$DRV/requests.log" && grep -q "\"shot\":{\"data\"" "$DRV/requests.log"'
expect "the tree is masked as an app's: data, a setting's value, what's ignored" \
  'grep -q "data: AXList AXStaticText" "$DRV/shots/trees/home.txt" && ! grep -q "Syncing" "$DRV/shots/trees/home.txt" && grep -q "value=\"Updated ‹time›\"" "$DRV/shots/trees/home.txt" && ! grep -q "AXCheckBox.*value" "$DRV/shots/trees/home.txt"'
screen "9:02 AM" 7
expect "a new time and more rows change nothing" 'out="$(d check)"; grep -q "home: unchanged" <<<"$out" && grep -q "check: no interface changed" <<<"$out"'
screen "9:02 AM" 7 Share
expect "a new button is a change, with its diff, and the hand-made GIF that shows it is named" \
  'out="$(d check --language en)"; grep -q "home: the interface changed" <<<"$out" && grep -q "+ AXButton title=\"Share\"" <<<"$out" && grep -q "docs/images/tour.gif (shows home)" <<<"$out"'
expect "check exits 1 when something changed" '(cd "$DRV" && "$KIT" check --language en >/dev/null 2>&1); [ $? -eq 1 ]'
expect "tree prints what the screen reads as" 'd tree home --language en | grep -q "AXButton title=\"Share\""'
touch "$DRV/fail"
expect "a driver that fails is named, with what it said" 'd check --language en | grep -q "the driver failed (exit 3):" && d check --language en | grep -q "simulator isn.t booted"'
rm "$DRV/fail"; touch "$DRV/skip"
expect "a screen the driver skips says why" 'd check --language en | grep -q "home: skipped, the screen needs a signed-in account"'
rm "$DRV/skip"
expect "record needs names" 'd record | grep -q "record: name the"'

echo "--- one list, where the site is on the same branch (#36)"
ONE="$TMP/onelist"; mkdir -p "$ONE/site/shots" "$ONE/site/assets" "$ONE/docs"
git -C "$ONE" init -q
cat >"$ONE/.product-kit.json" <<'EOF'
{"repo": "me/one", "shots": {"site": "site", "repo_assets": "docs/assets.json"}}
EOF
echo '<img src="assets/main.png">' >"$ONE/site/index.html"; : >"$ONE/site/assets/main.png"
echo '![Logo](docs/logo.png) ![Tour](docs/tour.gif)' >"$ONE/README.md"; : >"$ONE/docs/logo.png"; : >"$ONE/docs/tour.gif"
cat >"$ONE/site/shots/shots.json" <<'EOF'
{"app": "/Applications/One.app", "bundle": "me.One",
 "shots": [{"name": "main", "file": "assets/main.png", "open": [], "window": "One"}]}
EOF
cat >"$ONE/docs/assets.json" <<'EOF'
{"assets": [{"file": "docs/logo.png", "none": "the app's icon"}, {"file": "docs/tour.gif", "shows": ["main"], "made": "1.0", "how": "hand"}]}
EOF
o() { (cd "$ONE" && "$KIT" "$@" 2>&1) || true; }
expect "two lists pass, before" 'o coverage | grep -q "all accounted for"'
expect "migrate folds the README's list into the manifest" \
  'o migrate | grep -q "folded 2 of docs/assets.json.s 2 entries into site/shots/shots.json (each .\"in\": \"repo\".)"'
expect "and takes out the old list and its key" \
  '[ ! -f "$ONE/docs/assets.json" ] && ! grep -q repo_assets "$ONE/.product-kit.json" && grep -q "\"in\": \"repo\"" "$ONE/site/shots/shots.json"'
expect "one list passes the same check" 'o coverage | grep -q "all accounted for"'
expect "migrate again has nothing to fold in" 'o migrate | grep -q "nothing to fold in"'
python3 - "$ONE/site/shots/shots.json" <<'EOF'
import json, sys
m = json.load(open(sys.argv[1]))
m["assets"].append({"file": "docs/gone.png", "none": "a picture", "in": "repo"})
m["assets"][1]["how"] = "magic"
json.dump(m, open(sys.argv[1], "w"), indent=2)
EOF
expect "a README file the one list names but nobody has is a problem" 'o coverage | grep -q "docs/gone.png is listed in shots/shots.json (\"in\": \"repo\") but doesn.t exist"'
expect "how it's made is one of the known ways" 'o coverage | grep -q "docs/tour.gif in shots/shots.json (\"in\": \"repo\") says it.s made \"magic\""'
# A site in its own checkout (another branch, as gh-pages is): two lists, by design.
APART="$TMP/apart"; mkdir -p "$APART/app/docs" "$APART/app-site/shots"
git -C "$APART/app" init -q
echo '{"repo": "me/apart", "shots": {"site": "../app-site", "repo_assets": "docs/assets.json"}}' >"$APART/app/.product-kit.json"
echo '{"assets": []}' >"$APART/app/docs/assets.json"
echo '{"app": "/Applications/A.app", "bundle": "me.A", "shots": []}' >"$APART/app-site/shots/shots.json"
expect "a site on another branch keeps its own list, and migrate says why" \
  'out="$(cd "$APART/app" && "$KIT" migrate 2>&1)"; [ $? -ne 0 ] || true; grep -q "on another branch or in another repository, so it keeps its own list" <<<"$out" && [ -f "$APART/app/docs/assets.json" ]'

echo "--- alt text, as a packet (#39)"
ALT="$TMP/alt"; mkdir -p "$ALT/shots/trees" "$ALT/docs/images/fr" "$ALT/site/fr"
git -C "$ALT" init -q
echo '{"repo": "me/alt", "shots": {"media": "docs/images"}}' >"$ALT/.product-kit.json"
cat >"$ALT/shots/shots.json" <<'EOF'
{"app": "/Applications/Alt.app", "bundle": "me.Alt",
 "languages": [{"code": "fr", "page": "fr/index.html", "assets": "docs/images/fr/"}],
 "shots": [{"name": "home", "file": "docs/images/home.png", "open": [], "window": "Home"},
           {"name": "settings", "file": "docs/images/settings.png", "open": [], "window": "Settings"}]}
EOF
echo '# Alt ![The Home window, with a Share button](docs/images/home.png) ![Settings](docs/images/settings.png)' >"$ALT/README.md"
echo '# Alt ![La fenêtre Accueil](docs/images/fr/home.png)' >"$ALT/README.fr.md"
echo 'AXWindow title="Home"' >"$ALT/shots/trees/home.txt"
git -C "$ALT" add -A && git -C "$ALT" -c user.name=t -c user.email=t@t commit -q -m start
printf 'AXWindow title="Home"\n  AXButton title="Share"\n' >"$ALT/shots/trees/home.txt"
out="$(cd "$ALT" && "$KIT" alt home --since HEAD 2>&1)"
expect "alt gives each picture's change and its alt text in every language" \
  'grep -q "+ *AXButton title=\"Share\"" <<<"$out" && grep -q "README.md: \"The Home window, with a Share button\"" <<<"$out" && grep -q "README.fr.md: \"La fenêtre Accueil\"" <<<"$out"'
expect "and only that picture's" '! grep -q "Settings" <<<"$out"'

echo "--- videos made by script (#44)"
VID="$TMP/vid"; mkdir -p "$VID/shots/trees" "$VID/assets"
git -C "$VID" init -q
echo '{"repo": "me/vid"}' >"$VID/.product-kit.json"
cat >"$VID/shots/shots.json" <<'EOF'
{"app": "/Applications/Vid.app", "bundle": "me.Vid",
 "languages": [{"code": "fr", "page": "fr/index.html", "assets": "assets/fr/"}],
 "shots": [{"name": "home", "file": "assets/home.png", "open": [], "window": "Home"}],
 "assets": [
  {"file": "assets/tour.mp4", "shows": ["home"], "made": "1.0", "how": "built", "every_language": true,
   "build": {"command": ["sh", "-c", "printf 'a tour in %s' \"$1\" > \"$0\"", "{out}", "{code}"]}},
  {"file": "assets/brag.mp4", "shows": ["home"], "made": "1.0"}]}
EOF
echo '{"home.txt": "1.2"}' >"$VID/shots/trees/versions.json"; : >"$VID/shots/trees/home.txt"
v() { (cd "$VID" && "$KIT" videos "$@" 2>&1) || true; }
expect "--dry-run says which it would make, and makes none" 'v --dry-run | grep -q "would make assets/fr/tour.mp4 (built, fr)" && [ ! -f "$VID/assets/tour.mp4" ]'
out="$(v)"
expect "a built video out of date is made again, in every language" \
  'grep -q "made 2: assets/tour.mp4, assets/fr/tour.mp4" <<<"$out" && [ "$(cat "$VID/assets/fr/tour.mp4")" = "a tour in fr" ] && [ "$(cat "$VID/assets/tour.mp4")" = "a tour in en" ]'
expect "its made is the windows' version now" 'python3 -c "import json,sys; a=json.load(open(sys.argv[1]))[\"assets\"]; sys.exit(a[0][\"made\"] != \"1.2\" or a[1][\"made\"] != \"1.0\")" "$VID/shots/shots.json"'
expect "a video made by hand is named, never remade" 'grep -q "assets/brag.mp4 (made from 1.0, its windows from 1.2)" <<<"$out" && [ ! -f "$VID/assets/brag.mp4" ]'
expect "a recorded one with neither a driver nor an app says what it needs" \
  'python3 -c "import json,sys; m=json.load(open(sys.argv[1])); m[\"assets\"][0].update(how=\"recorded\", made=\"1.0\", record={\"shot\": \"home\"}); m.pop(\"app\"); json.dump(m, open(sys.argv[1], \"w\"))" "$VID/shots/shots.json" && v | grep -q "needs the manifest.s .driver., or its .app."'

[ "$fails" -eq 0 ] && echo "shots-kit: every test passed" || echo "shots-kit: $fails failed"
exit $((fails > 0))
