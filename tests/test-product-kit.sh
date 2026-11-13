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

echo "--- one version"
V="$("$KIT" version)"
expect "version is one version" '[[ "$V" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]'
expect "every tool carries it" \
  '[ "$(python3 -I "$ROOT/bin/docs-kit" version)" = "$V" ] && [ "$(python3 -I "$ROOT/bin/lang-kit" version)" = "$V" ] && grep -q "^let shotsKitVersion = \"$V\"" "$ROOT/shots/shots-kit.swift"'
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
  "api graphql") if [[ "$*" == *mutation* ]]; then echo '{"data": {}}'; else echo '{"data": {"repository": {"a": {"id": "I_up"}, "b": {"id": "I_new"}}}}'; fi ;;
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
  'cmp -s "$pushed/Scripts/docs-kit" "$ROOT/bin/docs-kit" && cmp -s "$pushed/Scripts/site-shots.swift" "$ROOT/shots/shots-kit.swift" && [ -f "$pushed/Scripts/AccessibilityAudit.swift" ]'
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

[ "$fails" -eq 0 ] && echo "product-kit: every test passed" || echo "product-kit: $fails failed"
exit $((fails > 0))
