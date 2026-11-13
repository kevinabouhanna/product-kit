#!/bin/bash
# product-kit's own command: each part reaches its tool; one version for every tool; the
# projects that use it, and their copies brought up to date (#33), on made-up projects with a
# stand-in for gh. Usage: tests/test-product-kit.sh
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KIT="$ROOT/bin/product-kit"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fails=0
expect() { if eval "$2"; then printf '  ok    %s\n' "$1"; else printf '  FAIL  %s\n' "$1"; fails=$((fails + 1)); fi; }
pk() { python3 -I "$KIT" "$@" 2>&1 || true; }

echo "--- the parts"
expect "help names each part" '"$KIT" help | grep -q "product-kit docs" && "$KIT" help | grep -q "product-kit shots"'
expect "docs runs docs-kit" '"$KIT" docs help | grep -q "docs-kit site"'
expect "lang runs lang-kit" '"$KIT" lang help | grep -q "lang-kit review"'
expect "shots runs shots-kit" '"$KIT" shots help | grep -q "shots-kit vendor"'
expect "an unknown command fails" '! "$KIT" nope 2>/dev/null'
expect "the plugin is named product-kit" 'grep -q "\"name\": \"product-kit\"" "$ROOT/.claude-plugin/plugin.json"'
# Every session in every project reads a skill's description, so it stays short (#34).
expect "one skill, its description under 60 words" \
  '[ "$(ls "$ROOT/skills")" = product-kit ] && [ "$(sed -n "s/^description: //p" "$ROOT/skills/product-kit/SKILL.md" | wc -w)" -lt 60 ]'
expect "every reference the skill names is there" \
  '( for f in $(grep -o "docs/[a-z-]*\.md" "$ROOT/skills/product-kit/SKILL.md" | sort -u); do [ -f "$ROOT/$f" ] || exit 1; done )'

echo "--- one version"
V="$("$KIT" version)"
expect "version is one version" '[[ "$V" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]'
expect "every tool carries it" \
  '[ "$(python3 -I "$ROOT/bin/docs-kit" version)" = "$V" ] && [ "$(python3 -I "$ROOT/bin/lang-kit" version)" = "$V" ] && grep -q "^let shotsKitVersion = \"$V\"" "$ROOT/shots/core.swift"'
expect "bump takes only a version" 'pk bump 2.x | grep -q "three numbers"'

echo "--- the projects, and their copies"
export PRODUCT_KIT_PROJECTS="$TMP/work" GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
mkdir -p "$TMP/work/me" "$TMP/origins"
# A stand-in for gh: an issue is #7, a pull request #8, and every call is logged.
cat >"$TMP/gh" <<'EOF'
#!/bin/bash
echo "$*" >>"$(dirname "$0")/gh.log"
case "$1 $2" in
  "issue create") echo "https://github.com/me/app/issues/7" ;;
  "pr create") echo "https://github.com/me/app/pull/8" ;;
  "api graphql")
    if [[ "$*" == *addProjectV2DraftIssue* ]]; then echo '{"data": {"addProjectV2DraftIssue": {"projectItem": {"id": "D1"}}}}'
    elif [[ "$*" == *mutation* ]]; then echo '{"data": {}}'
    elif [[ "$*" == *"projectV2(number"* ]]; then echo '{"data": {"user": {"projectV2": {"id": "P1", "url": "https://github.com/users/me/projects/1", "field": {"id": "K1", "options": [{"id": "F1", "name": "Feature"}]}}}}}'
    else echo '{"data": {"repository": {"a": {"id": "I_up"}, "b": {"id": "I_new"}}}}'; fi ;;
  *) echo '{}' ;;
esac
EOF
chmod +x "$TMP/gh"
export PRODUCT_KIT_GH="$TMP/gh"

# One project with an old docs-kit, an old shots-kit for an app's windows, and an upkeep item.
make_project() { # name, then config
  git init -q --bare "$TMP/origins/$1.git"
  git clone -q "$TMP/origins/$1.git" "$TMP/work/me/$1" 2>/dev/null
  printf '%s\n' "$2" >"$TMP/work/me/$1/.product-kit.json"
}
make_project app '{"repo": "me/app", "upkeep": 3, "shots": {"vendor": "Scripts/site-shots.swift"}}'
APP="$TMP/work/me/app"
mkdir -p "$APP/Scripts" "$APP/shots"
printf 'VERSION = "1.5.0"\n' >"$APP/Scripts/docs-kit"
printf 'let shotsKitVersion = "1.3.0"\n' >"$APP/Scripts/site-shots.swift"
echo '{"app": "/Applications/App.app", "bundle": "me.App", "shots": []}' >"$APP/shots/shots.json"
git -C "$APP" add -A && git -C "$APP" -c user.name=t -c user.email=t@t commit -q -m start && git -C "$APP" push -q origin HEAD:main 2>/dev/null
git -C "$APP" remote set-head origin main >/dev/null 2>&1
# And one already up to date.
make_project current '{"repo": "me/current"}'
CUR="$TMP/work/me/current"
mkdir -p "$CUR/Scripts"; cp "$ROOT/bin/docs-kit" "$CUR/Scripts/docs-kit"
git -C "$CUR" add -A && git -C "$CUR" -c user.name=t -c user.email=t@t commit -q -m start && git -C "$CUR" push -q origin HEAD:main 2>/dev/null

expect "projects lists each project's copies, and which are behind" \
  'out="$(pk projects)"; grep -q "app: docs-kit 1.5.0 (behind), shots-kit 1.3.0 (behind)" <<<"$out" && grep -q "current: docs-kit $V: up to date" <<<"$out"'
expect "projects --json says the same for scripts" \
  'pk projects --json | python3 -c "import json,sys; d=json.load(sys.stdin); a=[p for p in d[\"projects\"] if p[\"project\"]==\"app\"][0]; sys.exit(a[\"behind\"]!=[\"docs-kit\",\"shots-kit\"])"'
expect "vendor without --all says how to use it" 'pk vendor | grep -q "usage: product-kit vendor --all"'
expect "vendor --all --dry-run says what it would do, and does nothing" \
  'pk vendor --all --dry-run | grep -q "app: would open an issue and a pull request in me/app" && [ ! -f "$TMP/gh.log" ]'

out="$(pk vendor --all)"
pushed="$TMP/pushed"; git clone -q -b product-kit-${V//./-}-7 "$TMP/origins/app.git" "$pushed" 2>/dev/null
expect "it opens a pull request for the project that's behind" 'grep -q "app: https://github.com/me/app/pull/8 (docs-kit 1.5.0 → $V, shots-kit 1.3.0 → $V)" <<<"$out"'
expect "and leaves the one that's up to date alone" 'grep -q "current: up to date" <<<"$out"'
expect "the branch it pushed holds this version's copies" \
  'cmp -s "$pushed/Scripts/docs-kit" "$ROOT/bin/docs-kit" && "$ROOT/bin/shots-kit" source | cmp -s - "$pushed/Scripts/site-shots.swift" && [ -f "$pushed/Scripts/AccessibilityAudit.swift" ]'
expect "an app's windows keep what shots-kit masked before 1.4.0, in the config" \
  'python3 -c "import json,sys; s=json.load(open(sys.argv[1]))[\"shots\"]; sys.exit(not (s[\"keep_width\"]==[\"AXMenuBarItem\"] and \"MB\" not in s[\"masks\"][0][\"pattern\"] and \"B/s\" in s[\"masks\"][0][\"pattern\"]))" "$pushed/.product-kit.json"'
expect "the issue goes under the project's upkeep item, and the pull request closes it" \
  'grep -q "issue create -R me/app --title Update product-kit" "$TMP/gh.log" && grep -q "addSubIssue(input: { issueId: \"I_up\", subIssueId: \"I_new\"" "$TMP/gh.log" && grep -q "pr create -R me/app --head product-kit-${V//./-}-7 --base main" "$TMP/gh.log" && grep -q "Closes #7" "$TMP/gh.log"'
expect "no worktree or local branch is left behind" \
  '[ "$(git -C "$APP" worktree list | wc -l | tr -d " ")" = 1 ] && ! git -C "$APP" rev-parse -q --verify product-kit-${V//./-}-7 >/dev/null'

# A project with a plan and no upkeep item: its issue would be outside the plan.
make_project planned '{"repo": "me/planned", "plan": {"pages": "docs/phases"}}'
PLANNED="$TMP/work/me/planned"
mkdir -p "$PLANNED/Scripts"; printf 'VERSION = "1.5.0"\n' >"$PLANNED/Scripts/docs-kit"
git -C "$PLANNED" add -A && git -C "$PLANNED" -c user.name=t -c user.email=t@t commit -q -m start && git -C "$PLANNED" push -q origin HEAD:main 2>/dev/null
git -C "$PLANNED" remote set-head origin main >/dev/null 2>&1
expect "a project with a plan and no upkeep item isn't done, and says why" \
  'pk vendor --all --only planned | grep -q "planned: not done: it has a plan, so the issue needs an item to go under: give --upkeep"'
expect "--upkeep goes with one project" 'pk vendor --all --upkeep 5 | grep -q "goes with --only <one project>"'
out="$(pk vendor --all --only planned --upkeep 5)"
git clone -q -b product-kit-${V//./-}-7 "$TMP/origins/planned.git" "$TMP/planned-pushed" 2>/dev/null
expect "given once, the upkeep item takes the issue and stays in the project's config" \
  'grep -q "planned: https://github.com/me/app/pull/8" <<<"$out" && grep -q "names #5 as the item" <<<"$out" && grep -q "\"upkeep\": 5" "$TMP/planned-pushed/.product-kit.json"'

echo "--- the doctor, a gap, publishing (#37)"
DOC="$TMP/doc"; mkdir -p "$DOC/Resources/en.lproj" "$DOC/Resources/fr.lproj" "$DOC/docs"
git -C "$DOC" init -q
cat >"$DOC/.product-kit.json" <<'EOF'
{"repo": "me/doc", "languages": {"fr": {"name": "Français"}},
 "lang": {"strings": {"format": "strings", "path": "Resources/{code}.lproj/Localizable.strings"}},
 "checks": [{"name": "the app's links", "run": ["sh", "-c", "echo 2 links go nowhere; exit 1"], "fix": "make links"}],
 "publish": [{"name": "the store's text", "run": ["sh", "-c", "echo published > published.txt"]}]}
EOF
for c in en fr; do : >"$DOC/Resources/$c.lproj/Localizable.strings"; : >"$DOC/Resources/$c.lproj/InfoPlist.strings"; done
echo '![Main](docs/main.png) <img src="docs/tour.gif"> ![Badge](https://example.com/b.svg)' >"$DOC/README.md"
echo "How to use it" >"$DOC/docs/using.md"
out="$(cd "$DOC" && python3 -I "$KIT" doctor 2>&1)"
expect "the doctor names a project with no plan" 'grep -q "no plan" <<<"$out"'
expect "and text nothing checks, the table lang-kit has left out" 'grep -q "text lang-kit doesn.t check: Resources/en.lproj/InfoPlist.strings, Resources/fr.lproj/InfoPlist.strings" <<<"$out"'
expect "and pictures in no list, not counting another site's" 'grep -q "2 pictures or videos in the README and docs, in no list" <<<"$out"'
expect "and a language's missing README and docs" 'grep -q "fr has no README.fr.md, docs/fr/" <<<"$out"'
expect "and the project's own check, with its fix" 'grep -q "the app.s links fails: 2 links go nowhere" <<<"$out" && grep -q "→ make links" <<<"$out"'
expect "the doctor exits 1 when there's something to look at" '(cd "$DOC" && python3 -I "$KIT" doctor >/dev/null 2>&1); [ $? -eq 1 ]'
expect "--json says the same for scripts" 'json="$(cd "$DOC" && python3 -I "$KIT" doctor --json)"; python3 -c "import json,sys; sys.exit(len(json.loads(sys.argv[1])) != 5)" "$json"'
CLEAN="$TMP/clean"; mkdir -p "$CLEAN"; git -C "$CLEAN" init -q
echo '{"repo": "me/clean", "plan": {"pages": "docs/phases"}}' >"$CLEAN/.product-kit.json"
expect "a project with nothing unaccounted for says so in a line" '(cd "$CLEAN" && python3 -I "$KIT" doctor) | grep -q "doctor: clean: nothing unaccounted for"'
expect "publish runs the project's own steps" '(cd "$DOC" && python3 -I "$KIT" publish) | grep -q "publish: the store.s text" && grep -q published "$DOC/published.txt"'
: >"$TMP/gh.log"
out="$(cd "$DOC" && pk gap "reading .properties tables" --why "a Java tool's text")"
expect "a gap goes in product-kit's Inbox, as a draft with the project's name" \
  'grep -q "is in product-kit.s Inbox" <<<"$out" && grep -q "addProjectV2DraftIssue" "$TMP/gh.log" && grep -q "Gap (doc): reading .properties tables" "$TMP/gh.log"'
expect "gap needs to say what" 'pk gap | grep -q "usage: product-kit gap"'

echo "--- status: what's out of date (#38)"
ST="$TMP/st"; mkdir -p "$ST/Resources/en.lproj" "$ST/Resources/fr.lproj" "$ST/shots" "$ST/docs/fr"
git -C "$ST" init -q
cat >"$ST/.product-kit.json" <<'EOF'
{"repo": "me/st", "languages": {"fr": {"name": "Français"}},
 "lang": {"strings": {"format": "strings", "path": "Resources/{code}.lproj/Localizable.strings",
                      "source_path": "Resources/en.lproj/Localizable.strings"}}}
EOF
printf '"Quit" = "Quit";\n"Open" = "Open";\n' >"$ST/Resources/en.lproj/Localizable.strings"
printf '"Quit" = "Quitter";\n' >"$ST/Resources/fr.lproj/Localizable.strings"
echo '{"render": {"command": ["true"]}, "shots": []}' >"$ST/shots/shots.json"
echo "# St" >"$ST/README.md"; echo "# St" >"$ST/README.fr.md"
git -C "$ST" add -A && git -C "$ST" commit -q -m start
out="$(cd "$ST" && python3 -I "$KIT" status --release --base HEAD 2>&1)"; code=$?
expect "status names a translation missing, as Claude's to write, and fails" \
  'grep -q "✗ claude: the app.s text isn.t whole in every language" <<<"$out" && [ $code -eq 1 ]'
expect "and what's only to look at, which doesn't fail" 'grep -q "· claude: no plan" <<<"$out"'
expect "--release adds the release's steps: the review, and pictures the app draws" \
  'grep -q "post .lang-kit review" <<<"$out" && grep -q "the pictures the app draws" <<<"$out"'
printf '"Quit" = "Quitter";\n"Open" = "Ouvrir";\n' >"$ST/Resources/fr.lproj/Localizable.strings"
expect "with nothing failing, it exits 0, whatever's left to look at" \
  '(cd "$ST" && python3 -I "$KIT" status --base HEAD >/dev/null 2>&1)'
expect "--json says who does each, and whether it fails" \
  'json="$(cd "$ST" && python3 -I "$KIT" status --json --base HEAD)"; python3 -c "import json,sys; d=json.loads(sys.argv[1]); sys.exit(not d or any(set(i) != {\"what\",\"do\",\"who\",\"fails\"} for i in d))" "$json"'

echo "--- the facts, written once (#40)"
FA="$TMP/facts"; mkdir -p "$FA/app/docs/fr" "$FA/app-site/fr"
git -C "$FA/app" init -q
cat >"$FA/app/.product-kit.json" <<'EOF'
{"repo": "me/fa", "languages": {"fr": {"name": "Français", "site": "fr"}},
 "shots": {"site": "../app-site"},
 "facts": {"version": {"from": "tag"}, "size": {"from": "command", "run": ["echo", "14.9 MB"]},
           "requires": {"en": "macOS 13 or later", "fr": "macOS 13 ou plus récent"},
           "features": {"en": ["Live speed", "Which app used your data"], "fr": ["Le débit en direct", "Quelle app a utilisé vos données"]}}}
EOF
printf '# Fa\n\nFor <!-- product-kit: requires -->macOS 12<!-- /product-kit -->.\n\n<!-- product-kit: features --><!-- /product-kit -->\n' >"$FA/app/README.md"
printf '# Fa\n\nPour <!-- product-kit: requires -->macOS 12<!-- /product-kit -->.\n' >"$FA/app/README.fr.md"
echo '<span>Version <!-- product-kit: version -->1.29.0<!-- /product-kit --></span> <span><!-- product-kit: size -->9 MB<!-- /product-kit --></span>' >"$FA/app-site/index.html"
echo '<ul><!-- product-kit: features --><!-- /product-kit --></ul>' >"$FA/app-site/fr/index.html"
git -C "$FA/app" add -A && git -C "$FA/app" -c user.name=t -c user.email=t@t commit -q -m start && git -C "$FA/app" tag v1.30.2
f() { (cd "$FA/app" && python3 -I "$KIT" facts "$@" 2>&1) || true; }
expect "facts says which spots are out of date, and fails" \
  'out="$(f)"; grep -q "6 of 6 spots are out of date" <<<"$out" && grep -q "index.html: version is .1.29.0., should be .1.30.2." <<<"$out"'
f --write >/dev/null
expect "--write fills each spot, in each page's language, from the tag and a command" \
  'grep -q "Version <!-- product-kit: version -->1.30.2<!--" "$FA/app-site/index.html" && grep -q "14.9 MB" "$FA/app-site/index.html" && grep -q "Pour <!-- product-kit: requires -->macOS 13 ou plus récent<!--" "$FA/app/README.fr.md"'
expect "a list is Markdown's in a page, HTML's on the site" \
  'grep -q "^- Which app used your data$" "$FA/app/README.md" && grep -q "<li>Quelle app a utilisé vos données</li>" "$FA/app-site/fr/index.html"'
expect "then every spot is current" 'f | grep -q "all 6 spots are current"'
echo '<!-- product-kit: price -->Free<!-- /product-kit -->' >>"$FA/app/README.md"
expect "a spot naming a fact the config hasn't is named" 'f | grep -q "names a fact the config hasn.t: .*README.md: price"'

[ "$fails" -eq 0 ] && echo "product-kit: every test passed" || echo "product-kit: $fails failed"
exit $((fails > 0))
