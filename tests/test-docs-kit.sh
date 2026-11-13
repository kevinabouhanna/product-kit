#!/bin/bash
#
# docs-kit (#36), offline: a small project in a temporary folder, a stand-in for GitHub's
# renderer, and each command checked against it.
# Usage: tests/test-docs-kit.sh

set -uo pipefail
KIT="$(cd "$(dirname "$0")/.." && pwd)/bin/docs-kit"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fails=0
ok() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; fails=$((fails + 1)); }
expect() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }

# GitHub's renderer, near enough: headings, images and paragraphs, with no ids, as the API
# returns them.
cat >"$TMP/render.py" <<'EOF'
import re, sys
out = []
for block in re.split(r"\n\s*\n", sys.stdin.read()):
    m = re.match(r"^(#{1,6}) (.*)$", block.strip())
    if m:
        out.append(f"<h{len(m.group(1))}>{m.group(2)}</h{len(m.group(1))}>")
    elif block.strip():
        text = re.sub(r"!\[([^\]]*)\]\(([^)]+)\)", r'<img src="\2" alt="\1">', block.strip())
        text = re.sub(r"\[([^\]]*)\]\(([^)]+)\)", r'<a href="\2">\1</a>', text)
        out.append(f"<p>{text}</p>")
print("\n".join(out))
EOF
export DOCS_KIT_RENDER="python3 -I $TMP/render.py"

P="$TMP/project"
mkdir -p "$P/docs/fr" "$P/src" "$P/site/docs" "$P/site/fr/docs"
cd "$P" || exit 1
git init -q -b main . && git config user.email t@example.com && git config user.name t
cat >.docs-kit.json <<'EOF'
{
  "repo": "someone/thing",
  "name": "Thing",
  "extra_pages": { "SECURITY.md": { "copy": "security.md", "slug": "security" } },
  "developer_pages": ["docs/dev.md"],
  "languages": { "fr": { "name": "Français", "site": "fr" } },
  "check": { "needs_docs": [ { "paths": ["src/**/*.swift"], "except": ["src/Tests/**"], "lines": "\\bL\\(\"" } ] },
  "site": { "url": "https://someone.github.io/thing/", "templates": { "en": "docs/_t.html", "fr": "fr/docs/_t.html" },
            "strip_lines": ["^English · "] },
  "wiki": { "names": { "SECURITY.md": "Security-Policy" }, "home": "**Thing.** [Source]({web})\n\n" }
}
EOF
cat >docs/README.md <<'EOF'
# Thing docs

English · [Français](fr/README.md)

## Using it

| Page | What |
|---|---|
| [The guide](guide.md) | How |
| [Security](../SECURITY.md) | Reporting |

## Working on it

| Page | What |
|---|---|
| [Development](dev.md) | Building |
EOF
cat >docs/guide.md <<'EOF'
# The guide

English · [Français](fr/guide.md)

Start with [the security policy](../SECURITY.md#reporting) and [building](dev.md), see #12.

![The window](../assets/window.png)

## Pause and resume

## FAQ

## FAQ

<a id="keep-me"></a>
## L'été, `code` and **bold**!

```
## not a heading
```
EOF
printf '# Development\n\nMake it.\n' >docs/dev.md
printf '# Security policy\n\nEnglish · [Français](docs/fr/security.md)\n\n## Reporting\n\nMail.\n' >SECURITY.md
printf '# Docs de Thing\n\n## Utilisation\n\n| Page | Quoi |\n|---|---|\n| [Le guide](guide.md) | Comment |\n' >docs/fr/README.md
printf '# Le guide\n\n## Pause et reprise\n' >docs/fr/guide.md
printf '# Politique de sécurité\n\n## Signaler\n' >docs/fr/security.md
printf 'let a = L("Pause")\n' >src/app.swift
mkdir -p src/Tests && printf 'let t = 1\n' >src/Tests/t.swift
for t in site/docs/_t.html site/fr/docs/_t.html; do
  printf '<html lang="{{lang}}"><title>{{title}}</title>{{alternates}}<nav>{{switch}}</nav><aside>{{nav}}</aside><main>{{content}}</main><a href="{{root}}">home</a><a href="{{source}}">{{commit}}</a></html>\n' >"$t"
done
git add -A && git commit -qm start
git branch -q base

echo "--- anchors"
anchors="$("$KIT" anchors)"
guide() { jq -r --arg f "$1" '.[] | select(.file == $f) | .anchors | join(" ")' <<<"$anchors"; }
expect "headings become GitHub's anchors, repeats numbered, code blocks skipped" \
  '[ "$(guide docs/guide.md)" = "the-guide pause-and-resume faq faq-1 lété-code-and-bold keep-me" ]'
expect "pages for developers aren't published" '! jq -e ".[] | select(.file == \"docs/dev.md\")" <<<"$anchors" >/dev/null'
expect "each language's pages under its folder" \
  '[ "$(jq -r ".[] | select(.file == \"docs/fr/guide.md\") | .path" <<<"$anchors")" = "fr/docs/guide/" ]'
expect "extra pages by their slug" \
  '[ "$(jq -r ".[] | select(.file == \"SECURITY.md\") | .url" <<<"$anchors")" = "https://someone.github.io/thing/docs/security/" ]'

echo "--- site"
"$KIT" site "$P/site" >/dev/null || fail "docs-kit site ran"
page="$(cat site/docs/guide/index.html 2>/dev/null)"
expect "a page per doc, the index and each language's" \
  '[ -f site/docs/index.html ] && [ -f site/docs/security/index.html ] && [ -f site/fr/docs/guide/index.html ] && [ -f site/fr/docs/security/index.html ] && [ ! -e site/docs/dev ]'
expect "each heading carries its anchor" \
  'grep -q "<h2 id=\"pause-and-resume\">" <<<"$page" && grep -q "<h2 id=\"faq-1\">" <<<"$page"'
expect "links between pages are relative, with their anchors" 'grep -q "href=\"../../docs/security/#reporting\"" <<<"$page"'
expect "pages for developers link to GitHub" 'grep -q "href=\"https://github.com/someone/thing/blob/main/docs/dev.md\"" <<<"$page"'
expect "images come from the repository at the commit" \
  "grep -q \"src=\\\"https://raw.githubusercontent.com/someone/thing/$(git rev-parse HEAD)/assets/window.png\\\"\" <<<\"\$page\""
expect "#N links to the issue" 'grep -q "href=\"https://github.com/someone/thing/issues/12\"" <<<"$page"'
expect "strip_lines leaves the page's own switch out" '! grep -q "English ·" <<<"$page"'
expect "the template's switch links the translation" 'grep -q "href=\"../../fr/docs/guide/\" lang=\"fr\"" <<<"$page"'
expect "the nav marks the current page and leaves out developer pages" \
  'grep -q "<a href=\"../../docs/guide/\" aria-current=page>The guide</a>" <<<"$page" && ! grep -q "Development</a>" <<<"$page"'
expect "{{root}} climbs to the site's top" 'grep -q "<a href=\"../../\">home</a>" <<<"$page"'
expect "the French page uses its own template and lang" 'grep -q "<html lang=\"fr\">" site/fr/docs/guide/index.html'
git rm -q docs/fr/guide.md && git commit -qm "no French guide"
"$KIT" site "$P/site" >/dev/null
expect "a page whose doc is gone is removed, the template kept" '[ ! -e site/fr/docs/guide ] && [ -f site/fr/docs/_t.html ]'
git reset -q --hard base

echo "--- wiki"
mkdir -p "$TMP/wiki" && touch "$TMP/wiki/Old-Page.md"
"$KIT" wiki "$TMP/wiki" abc1234 || fail "docs-kit wiki ran"
expect "pages named after their files, or wiki.names" \
  '[ -f "$TMP/wiki/Guide.md" ] && [ -f "$TMP/wiki/Security-Policy.md" ] && [ -f "$TMP/wiki/Guide-fr.md" ] && [ -f "$TMP/wiki/Security-Policy-fr.md" ] && [ -f "$TMP/wiki/Home-fr.md" ]'
expect "Home has wiki.home above the index" 'grep -q "^\*\*Thing.\*\* \[Source\](https://github.com/someone/thing)" "$TMP/wiki/Home.md"'
expect "links between pages become wiki links" 'grep -q "(Security-Policy#reporting)" "$TMP/wiki/Guide.md"'
expect "the sidebar follows the index, each language after, then what neither lists" \
  '[ "$(grep -o "([A-Za-z-]*)" "$TMP/wiki/_Sidebar.md" | tr -d "()" | tr "\n" " ")" = "Home Guide Security-Policy Dev Home-fr Guide-fr Security-Policy-fr " ]'
expect "a page whose doc is gone is removed" '[ ! -e "$TMP/wiki/Old-Page.md" ]'

echo "--- check"
printf 'let b = 2\n' >>src/app.swift
expect "a change with no text in it needs no docs" 'PR_BODY="" "$KIT" check base >/dev/null'
git checkout -q src/app.swift
printf 'let b = L("Resume")\n' >>src/Tests/t.swift
expect "a change under except needs no docs" 'PR_BODY="" "$KIT" check base >/dev/null'
git checkout -q src/Tests/t.swift
printf 'let b = L("Resume")\n' >>src/app.swift
expect "new text in the app with no docs fails" '! PR_BODY="" "$KIT" check base >/dev/null'
expect "the pull request can say why not" 'PR_BODY=$'"'"'Fixes it.\r\n\r\nNo docs needed: a label'"'"' "$KIT" check base >/dev/null'
expect "a phrase with no reason doesn't count" '! PR_BODY="No docs needed:" "$KIT" check base >/dev/null'
printf '\nResume, too.\n' >>docs/dev.md
expect "a page for developers doesn't count" '! PR_BODY="" "$KIT" check base >/dev/null'
git checkout -q docs/dev.md
printf '\nResume, too.\n' >>docs/guide.md
expect "a page for users does" 'PR_BODY="" "$KIT" check base >/dev/null'
git checkout -q docs/guide.md
printf 'let c = L("New")\n' >src/new.swift
expect "a new file counts too" '! PR_BODY="" "$KIT" check base >/dev/null'
rm src/new.swift && git checkout -q src/app.swift

echo "--- vendor"
expect "--check says when the copy is missing" '! "$KIT" vendor --check >/dev/null'
"$KIT" vendor >/dev/null
expect "vendor copies it to Scripts/docs-kit, runnable" '[ -x Scripts/docs-kit ] && cmp -s Scripts/docs-kit "$KIT"'
expect "--check passes once it's the same" '"$KIT" vendor --check >/dev/null'

echo "--- plan"
# GitHub, as a stand-in that keeps its state in a file: milestones, issues, the board.
Q="$TMP/planned"
G="$TMP/gh"
mkdir -p "$Q/docs/phases" "$G"
cat >"$G/make.py" <<'EOF'
import json, sys
def issue(n, title, state="OPEN", milestone=None, parent=None, labels=(), body=""):
    return {"id": f"I{n}", "number": n, "title": title, "state": state, "milestone": milestone, "parent": parent,
            "labels": list(labels), "body": body}
def opts(*names):
    return [{"id": f"o-{n}", "name": n} for n in names]
issues = [
    issue(10, "First plan", milestone="Phase 1: One"),
    issue(11, "A step of the first", milestone="Phase 1: One", parent=10),
    issue(12, "Second | plan", milestone="Phase 2: Two"),
    issue(13, "Orphan step", milestone="Phase 2: Two", parent=99),
    issue(14, "An idea", milestone="Ideas"),
    issue(5, "Long done", state="CLOSED", milestone="Phase 0: Start"),
    issue(99, "A closed parent", state="CLOSED"),
]
def item(n, **values):
    return str(n), {"id": f"PVTI_{n}", "values": values}
state = {
    "repo": "someone/thing", "repo_id": "R1", "next": 1000,
    "milestones": [
        {"id": "M1", "number": 1, "title": "Phase 1: One", "state": "OPEN", "dueOn": "2027-01-01T00:00:00Z"},
        {"id": "M2", "number": 2, "title": "Phase 2: Two", "state": "OPEN", "dueOn": "2027-02-01T00:00:00Z"},
        {"id": "M3", "number": 3, "title": "Phase 0: Start", "state": "CLOSED", "dueOn": None},
        {"id": "M4", "number": 4, "title": "Ideas", "state": "OPEN", "dueOn": None},
    ],
    "labels": [{"id": "L1", "name": "bug"}],
    "issues": {str(i["number"]): i for i in issues},
    "board": {
        "id": "P1", "title": "Board", "owner": "Someone", "number": 8, "type": "User",
        "fields": [
            {"id": "F1", "databaseId": 1, "name": "Title", "dataType": "TITLE"},
            {"id": "F2", "databaseId": 2, "name": "Status", "dataType": "SINGLE_SELECT", "options": opts("Todo", "In Progress", "Done")},
            {"id": "F3", "databaseId": 3, "name": "Order", "dataType": "NUMBER"},
            {"id": "F4", "databaseId": 4, "name": "Horizon", "dataType": "SINGLE_SELECT", "options": opts("Now", "Next", "Later")},
            {"id": "F5", "databaseId": 5, "name": "Milestone", "dataType": "MILESTONE"},
            {"id": "F6", "databaseId": 6, "name": "Track", "dataType": "SINGLE_SELECT", "options": opts("Ears", "Hands")},
        ],
        "items": dict([
            item(10, Order=2, Horizon="Now", Status="Todo", Track="Ears"),
            item(11, Order=7, Horizon="Later", Status="In Progress"),
            item(12, Order=1, Horizon="Next", Status="Todo"),
            item(13, Horizon="Later", Status="Todo"),
            item(14, Order=3, Horizon="Later", Status="Todo"),
            item(5, Status="Todo"),
        ]),
        "views": [{"id": "V1", "number": 1, "name": "Issues", "filter": "no:parent-issue", "layout": "BOARD_LAYOUT"},
                  {"id": "V2", "number": 2, "name": "Roadmap", "filter": "no:parent-issue", "layout": "ROADMAP_LAYOUT"},
                  {"id": "V3", "number": 3, "name": "Ideas", "filter": "is:draft", "layout": "TABLE_LAYOUT", "fields": ["F1"]}],
        "drafts": {
            "PVTI_d2": {"title": "Wake me with music", "body": "Kevin: a song instead of the alarm.\nOn weekdays.",
                        "createdAt": "2026-11-12T09:00:00Z", "by": "kevin",
                        "values": {"Kind": "Bug"}},
            "PVTI_d1": {"title": "A dark mode", "body": "", "createdAt": "2026-11-10T09:00:00Z", "by": "kevin"},
        },
    },
}
json.dump(state, open(sys.argv[1], "w"), indent=1)
EOF
python3 -I "$G/make.py" "$G/github.json"
export DOCS_KIT_GH="python3 -I $(dirname "$KIT")/../tests/fake-github.py $G/github.json" DOCS_KIT_RETRY_WAIT=0 FAKE_PAGE=3
gh_state() { python3 -I -c 'import json,sys; s=json.load(open(sys.argv[1])); print(eval(sys.argv[2], {"s": s, "i": s["issues"], "b": s["board"]}))' "$G/github.json" "$1"; }
cd "$Q" || exit 1
git init -q -b main . && git config user.email t@example.com && git config user.name t
cat >.product-kit.json <<'EOF'
{
  "repo": "someone/thing",
  "name": "Thing",
  "plan": { "pages": "docs/phases", "index": "docs/phases/README.md", "inherit": ["Track"],
            "project": { "owner": "someone", "number": 8 }, "no_page": ["Ideas"] }
}
EOF
printf '# The plan\n\nThing does [one thing](phases/1-one.md) well.\n\n## More\n' >docs/PLAN.md
printf '# Phase 1: One\n\n**Milestone:** Phase 1: One · **Status:** Now\n\nThe first: #10.\n' >docs/phases/1-one.md
printf '# Phase 2: Two\n\n**Milestone:** Phase 2: Two · **Status:** Next\n\n#12 and #13, after #10 in phase one.\n' >docs/phases/2-two.md
printf '# Phase 0: Start\n\n**Milestone:** Phase 0: Start · **Status:** Done\n' >docs/phases/0-start.md
printf '# Our plan\n\nWhat the phases are.\n\n## Old\n\nStale.\n' >docs/phases/README.md
git add -A && git commit -qm plan

out="$("$KIT" plan check 2>&1)"
expect "before init, check says the board has no Level" 'grep -q "has no field \"Level\"" <<<"$out"'
expect "sync won't start without it" '! "$KIT" plan sync >/dev/null 2>&1'
cp "$G/github.json" "$G/before.json"
out="$("$KIT" plan init --dry-run 2>&1)"
expect "init --dry-run says what it would do and changes nothing" \
  'grep -q "field \"Level\" made" <<<"$out" && grep -q "made, the plan" <<<"$out" && cmp -s "$G/github.json" "$G/before.json" && git diff --quiet'
echo 1 >"$G/flaky"
out="$(FAKE_AUTOADD=1 FAKE_FLAKY_WRITES=1 FAKE_FLAKY_SAID="dial tcp 1.2.3.4:443: connect: operation timed out" "$KIT" plan init 2>&1)"; status=$?
expect "init sets the plan up, on a board that adds new issues by itself, after a write that never connected" '[ $status -eq 0 ]'
[ $status -eq 0 ] || echo "$out"
expect "the write was tried again" '[ "$(cat "$G/flaky")" = 0 ]'
root="$(gh_state '[n for n, x in i.items() if "plan" in x["labels"]][0]')"
p1="$(gh_state '[n for n, x in i.items() if x["title"] == "Phase 1: One" and "phase" in x["labels"]][0]')"
p2="$(gh_state '[n for n, x in i.items() if x["title"] == "Phase 2: Two"][0]')"
p0="$(gh_state '[n for n, x in i.items() if x["title"] == "Phase 0: Start"][0]')"
pi="$(gh_state '[n for n, x in i.items() if x["title"] == "Ideas"][0]')"
expect "the board has a Level field: Plan, Phase, Item, Step" \
  '[ "$(gh_state "[o[\"name\"] for f in b[\"fields\"] if f[\"name\"] == \"Level\" for o in f[\"options\"]]")" = "['"'"'Plan'"'"', '"'"'Phase'"'"', '"'"'Item'"'"', '"'"'Step'"'"']" ]'
expect "one root issue, The plan: Thing, labelled and pinned" \
  '[ "$(gh_state "(i[\"$root\"][\"title\"], i[\"$root\"].get(\"pinned\"))")" = "('"'"'The plan: Thing'"'"', True)" ]'
expect "a phase issue per milestone with a page or open, under the root, in its milestone" \
  '[ "$(gh_state "sorted((x[\"title\"], x[\"parent\"] == $root, x[\"milestone\"] == x[\"title\"]) for x in i.values() if \"phase\" in x[\"labels\"])")" = "[('"'"'Ideas'"'"', True, True), ('"'"'Phase 0: Start'"'"', True, True), ('"'"'Phase 1: One'"'"', True, True), ('"'"'Phase 2: Two'"'"', True, True)]" ]'
expect "a finished phase's issue is closed, and Done" \
  '[ "$(gh_state "(i[\"$p0\"][\"state\"], b[\"items\"][\"$p0\"][\"values\"][\"Status\"])")" = "('"'"'CLOSED'"'"', '"'"'Done'"'"')" ]'
expect "items go under their phase; a step stays under its item" \
  '[ "$(gh_state "[i[n][\"parent\"] for n in (\"10\", \"11\", \"12\", \"14\")]")" = "[$p1, 10, $p2, $pi]" ]'
expect "an open step under a closed parent: the parent goes under the phase" '[ "$(gh_state "i[\"99\"][\"parent\"]")" = "$p2" ]'
expect "Level from the tree" \
  '[ "$(gh_state "[b[\"items\"][n][\"values\"].get(\"Level\") for n in (\"$root\", \"$p1\", \"10\", \"11\", \"13\")]")" = "['"'"'Plan'"'"', '"'"'Phase'"'"', '"'"'Item'"'"', '"'"'Step'"'"', '"'"'Step'"'"']" ]'
expect "a step copies its item's Order, Horizon and inherited fields; its Status is its own" \
  '[ "$(gh_state "[b[\"items\"][\"11\"][\"values\"].get(k) for k in (\"Order\", \"Horizon\", \"Track\", \"Status\")]")" = "[2.0, '"'"'Now'"'"', '"'"'Ears'"'"', '"'"'In Progress'"'"']" ]'
expect "a phase's Horizon is its items' earliest, its Order their lowest" \
  '[ "$(gh_state "[b[\"items\"][\"$p1\"][\"values\"].get(k) for k in (\"Horizon\", \"Order\")]")" = "['"'"'Now'"'"', 2.0]" ]'
expect "a closed issue is Done on the board" '[ "$(gh_state "b[\"items\"][\"5\"][\"values\"][\"Status\"]")" = "Done" ]'
body="$(gh_state "i[\"$root\"][\"body\"]")"
expect "the root's description: the plan's first paragraph, its links made whole" \
  'grep -qF "Thing does [one thing](https://github.com/someone/thing/blob/main/docs/phases/1-one.md) well." <<<"$body"'
expect "then the items by Horizon, each with its phase and phase issue" \
  'grep -qF "| 2 | #10 First plan | [Phase 1: One](https://github.com/someone/thing/blob/main/docs/phases/1-one.md) #$p1 |" <<<"$body" && grep -q "^## Now" <<<"$body"'
expect "and the finished phases last" 'grep -A2 "^## Done" <<<"$body" | grep -qF "[Phase 0: Start]"'
expect "the plan's views: made, or their filters put right" \
  '[ "$(gh_state "sorted((v[\"name\"], v[\"filter\"]) for v in b[\"views\"])")" = "[('"'"'In order'"'"', '"'"'is:open level:Item,Step'"'"'), ('"'"'Inbox'"'"', '"'"'is:draft'"'"'), ('"'"'Issues'"'"', '"'"'no:parent-issue'"'"'), ('"'"'Now · Next · Later'"'"', '"'"'is:open level:Item'"'"'), ('"'"'Roadmap'"'"', '"'"'is:open level:Phase,Item'"'"')]" ] && [ "$(gh_state "len(b[\"views\"])")" = 5 ]'
expect "a view whose filter is put right keeps its layout" '[ "$(gh_state "[v[\"layout\"] for v in b[\"views\"] if v[\"name\"] == \"Roadmap\"][0]")" = "ROADMAP_LAYOUT" ]'
kind="$(gh_state '[f["id"] for f in b["fields"] if f["name"] == "Kind"][0]')"
expect "a Kind field: Bug, Feature, Idea, Research" \
  '[ "$(gh_state "[o[\"name\"] for f in b[\"fields\"] if f[\"name\"] == \"Kind\" for o in f[\"options\"]]")" = "['"'"'Bug'"'"', '"'"'Feature'"'"', '"'"'Idea'"'"', '"'"'Research'"'"']" ]'
expect "the Ideas view renamed Inbox in place: still a table of the drafts, now showing the Kind" \
  '[ "$(gh_state "[(v[\"name\"], v[\"layout\"], v[\"filter\"], v[\"fields\"]) for v in b[\"views\"] if v[\"id\"] == \"V3\"]")" = "[('"'"'Inbox'"'"', '"'"'TABLE_LAYOUT'"'"', '"'"'is:draft'"'"', ['"'"'F1'"'"', '"'"'$kind'"'"'])]" ]'
expect "the board view's columns are the Horizon, sorted by Order" \
  '[ "$(gh_state "[(v[\"vertical_group_by\"], v[\"sort_by\"]) for v in b[\"views\"] if v[\"name\"].startswith(\"Now\")]")" = "[([4], [[3, '"'"'asc'"'"']])]" ]'
index="$(cat docs/phases/README.md)"
expect "the index is written too, keeping its head" \
  'grep -q "^<!-- Written by .docs-kit plan index" <<<"$index" && grep -q "^What the phases are" <<<"$index" && ! grep -q Stale <<<"$index"'
expect "the index: a row per item, the board's own values" \
  'grep -qF "| 2 | #10 First plan | [Phase 1: One](1-one.md) |" <<<"$index" && grep -qF "| 1 | #12 Second \| plan | [Phase 2: Two](2-two.md) |" <<<"$index"'
expect "items by Order, those with none last; a phase with no page by name; Done last" \
  '[ "$(grep -o "#1[34] [A-Za-z ]*| [A-Za-z]*" <<<"$index" | tr "\n" ";")" = "#14 An idea | Ideas;#13 Orphan step | ;" ] && grep -qx "\[Phase 0: Start\](0-start.md)" <<<"$index"'
expect "issues are read a page at a time" 'grep -q "read the plan after=3" "$G/github.log"'
out="$("$KIT" plan check 2>&1)"; status=$?
expect "then check passes" '[ $status -eq 0 ] && grep -q "agree" <<<"$out"'
expect "and says, without failing, that entries are waiting" 'grep -qF "2 entries waiting in the Inbox: \`docs-kit plan inbox\`" <<<"$out"'
[ $status -eq 0 ] || echo "$out"
expect "and sync again changes nothing" '"$KIT" plan sync | grep -q "nothing to change"'
git add -A && git commit -qm synced

plan_fails() { # plan_fails <what it should say>
  out="$("$KIT" plan check 2>&1)"; [ $? -ne 0 ] && grep -qF "$1" <<<"$out" && ! grep -q Traceback <<<"$out"
}

echo "--- plan: the inbox"
out="$("$KIT" plan inbox)"
expect "plan inbox lists them, oldest first, with their Kind, notes and item ids" \
  '[ "$(grep -E "^[0-9]\. " <<<"$out" | tr "\n" ";")" = "1. A dark mode (kind not set);2. [Bug] Wake me with music;" ] && grep -qF "   > On weekdays." <<<"$out" && grep -q "item PVTI_d2" <<<"$out" && grep -q "views/3" <<<"$out"'
expect "plan ideas is the same" '[ "$("$KIT" plan ideas)" = "$out" ]'
expect "--json too" '[ "$("$KIT" plan inbox --json | jq -r ".[1].kind")" = Bug ]'
printf '## Why\n\n> Kevin: a song instead of the alarm.\n\n## What\n\nMusic at the wake-up time.\n' >"$TMP/spec.md"
expect "an item needs a Horizon" '{ "$KIT" plan inbox --take PVTI_d2 --phase "Phase 1: One" 2>&1 || true; } | grep -q "an item needs --horizon"'
expect "an id that isn't in the Inbox is said plainly" '{ "$KIT" plan inbox --take PVTI_nope --phase "Phase 1: One" --horizon Now 2>&1 || true; } | grep -q "nothing in the Inbox with the item id"'
out="$("$KIT" plan inbox --take PVTI_d2 --phase "Phase 1: One" --horizon Next --order 6 --set Track=Hands --blocked-by 12 --body-file "$TMP/spec.md" --title "Wake up to music" 2>&1)"
n="$(gh_state 'max(int(x) for x in i)')"
expect "--take makes the entry an issue on the board, its spec the description" \
  '[ "$(gh_state "(i[\"$n\"][\"title\"], i[\"$n\"][\"body\"].splitlines()[0], \"PVTI_d2\" in b[\"drafts\"])")" = "('"'"'Wake up to music'"'"', '"'"'## Why'"'"', False)" ]'
expect "an item of its phase, in its milestone, with its Level, Horizon, Order, fields and Kind" \
  '[ "$(gh_state "(i[\"$n\"][\"parent\"], i[\"$n\"][\"milestone\"], [b[\"items\"][\"$n\"][\"values\"].get(k) for k in (\"Level\", \"Horizon\", \"Order\", \"Track\", \"Kind\")])")" = "($p1, '"'"'Phase 1: One'"'"', ['"'"'Item'"'"', '"'"'Next'"'"', 6.0, '"'"'Hands'"'"', '"'"'Bug'"'"'])" ]'
expect "a Bug gets the repository's bug label; what it waits for is recorded" \
  '[ "$(gh_state "(i[\"$n\"][\"labels\"], i[\"$n\"].get(\"blocked_by\"))")" = "(['"'"'bug'"'"'], [12])" ]'
expect "it says where it went, and that the page should mention it" \
  'grep -qF "is now #$n Wake up to music, an item of #$p1 Phase 1: One, a Bug" <<<"$out" && grep -qF "blocked by #12" <<<"$out" && grep -qF "Now say on docs/phases/1-one.md what #$n is" <<<"$out"'
expect "plan check then asks for the mention" 'plan_fails "doesn'"'"'t mention #$n Wake up to music"'
printf 'Next: #%s.\n' "$n" >>docs/phases/1-one.md
"$KIT" plan inbox --take PVTI_d1 --phase "Phase 1: One" --parent 10 --kind Research >/dev/null
m="$(gh_state 'max(int(x) for x in i)')"
expect "with --parent, a step of that item: it copies the item's Horizon; --kind sets the Kind" \
  '[ "$(gh_state "(i[\"$m\"][\"parent\"], [b[\"items\"][\"$m\"][\"values\"].get(k) for k in (\"Level\", \"Horizon\", \"Kind\")], i[\"$m\"][\"labels\"])")" = "(10, ['"'"'Step'"'"', '"'"'Now'"'"', '"'"'Research'"'"'], [])" ]'
out="$("$KIT" plan set 14 Order=3.5 --blocked-by 10 2>&1)"
expect "plan set moves an item and records what it waits for" \
  '[ "$(gh_state "(b[\"items\"][\"14\"][\"values\"][\"Order\"], i[\"14\"].get(\"blocked_by\"))")" = "(3.5, [10])" ] && grep -qF "#14 An idea, Order 3.5, blocked by #10" <<<"$out"'
expect "plan set refuses a field the board hasn't" '{ "$KIT" plan set 14 Colour=red 2>&1 || true; } | grep -q "no field \"Colour\""'
out="$("$KIT" plan check 2>&1)"; status=$?
expect "the Inbox empty, and check passes" '[ $status -eq 0 ] && ! grep -q "waiting in the Inbox" <<<"$out"'
[ $status -eq 0 ] || echo "$out"
git add -A && git commit -qm ideas
gh_set() { python3 -I -c 'import json,sys; p=sys.argv[1]; s=json.load(open(p)); i=s["issues"]; b=s["board"]; exec(sys.argv[2]); json.dump(s, open(p, "w"))' "$G/github.json" "$1"; }

gh_set 'i["20"] = {"id": "I20", "number": 20, "title": "A new idea", "state": "OPEN", "milestone": "Phase 1: One", "parent": None, "labels": [], "body": ""}'
expect "a new issue in a milestone: check says sync would put it under its phase" 'plan_fails "#20 A new idea: now under #$p1 Phase 1: One"'
expect "and that it has no Horizon, and its page doesn't mention it" \
  'plan_fails "#20 A new idea (an item in \"Phase 1: One\") has no Horizon" && plan_fails "doesn'"'"'t mention #20 A new idea"'
"$KIT" plan sync >/dev/null
expect "sync puts it there, on the board, as an Item" \
  '[ "$(gh_state "(i[\"20\"][\"parent\"], b[\"items\"][\"20\"][\"values\"].get(\"Level\"))")" = "($p1, '"'"'Item'"'"')" ]'
gh_set 'b["items"]["20"]["values"]["Horizon"] = "Next"; b["items"]["20"]["values"]["Order"] = 4'
printf 'And #20.\n' >>docs/phases/1-one.md
"$KIT" plan sync >/dev/null
expect "with its Horizon and a mention, check passes" '"$KIT" plan check >/dev/null'
gh_set 'i["21"] = {"id": "I21", "number": 21, "title": "Somewhere", "state": "OPEN", "milestone": None, "parent": None, "labels": [], "body": ""}'
expect "an open issue with no milestone and no parent isn't in the plan" 'plan_fails "#21 Somewhere isn'"'"'t in the plan: give it a milestone"'
gh_set 'i["21"]["state"] = "CLOSED"'
gh_set 'b["items"]["11"]["values"]["Horizon"] = "Later"'
expect "a step whose Horizon isn't its item's: sync would copy it" 'plan_fails "#11 A step of the first: Horizon Now (from #10)"'
gh_set 'i[str('"$root"')]["body"] += "\nEdited by hand."'
expect "the root's description edited by hand: sync would write it again" 'plan_fails "the plan'"'"'s description written"'
"$KIT" plan sync >/dev/null
expect "sync puts both right" '"$KIT" plan check >/dev/null'

gh_set 'i["30"] = {"id": "I30", "number": 30, "title": "Phase 3: Sub", "state": "OPEN", "milestone": "Phase 3: Sub", "parent": int('"$p2"'), "labels": ["phase"], "body": ""}; i["31"] = {"id": "I31", "number": 31, "title": "Deep", "state": "OPEN", "milestone": None, "parent": 30, "labels": [], "body": ""}; s["milestones"].append({"id": "M9", "number": 9, "title": "Phase 3: Sub", "state": "OPEN", "dueOn": None}); b["items"]["31"] = {"id": "PVTI_31", "values": {"Horizon": "Later", "Order": 9}}'
printf '# Phase 3: Sub\n\n**Milestone:** Phase 3: Sub · **Status:** Later\n\nPart of phase two: #31.\n' >docs/phases/3-sub.md
"$KIT" plan sync >/dev/null
expect "a phase under a phase stays there; its items are Items, in its milestone" \
  '[ "$(gh_state "(i[\"30\"][\"parent\"], i[\"31\"][\"milestone\"], b[\"items\"][\"31\"][\"values\"].get(\"Level\"), b[\"items\"][\"30\"][\"values\"].get(\"Level\"))")" = "($p2, '"'"'Phase 3: Sub'"'"', '"'"'Item'"'"', '"'"'Phase'"'"')" ]'
expect "and the phase above counts them: its Order is its lowest" '[ "$(gh_state "b[\"items\"][\"$p2\"][\"values\"][\"Order\"]")" = "1.0" ]'
expect "check passes with a sub-phase" '"$KIT" plan check >/dev/null'

gh_set 'i["12"]["state"] = "CLOSED"; i["13"]["state"] = "CLOSED"; i["30"]["state"] = "CLOSED"; i["31"]["state"] = "CLOSED"; s["milestones"][-1]["state"] = "CLOSED"'
out="$("$KIT" plan sync 2>&1)"
expect "when a phase's work is all done, sync closes its issue, and its page says Done" \
  '[ "$(gh_state "i[\"$p2\"][\"state\"]")" = "CLOSED" ] && grep -q "Status:\*\* Done" docs/phases/2-two.md && grep -qF "#$p2 Phase 2: Two: closed, everything in it is done" <<<"$out"'
expect "it never closes an item or a step" '! grep -E "#1[0-9] .*: closed" <<<"$out"'
gh_set 'i["12"]["state"] = "OPEN"'
"$KIT" plan sync >/dev/null
expect "work reopened in it reopens the phase" '[ "$(gh_state "i[\"$p2\"][\"state\"]")" = "OPEN" ]'
git checkout -q docs/phases/2-two.md
"$KIT" plan sync >/dev/null

sed -i '' 's/Status:\*\* Now/Status:** Later/' docs/phases/1-one.md
expect "a wrong Status line: check says so" 'plan_fails "docs/phases/1-one.md: Status Now, was Later (#10 is Now)"'
"$KIT" plan status --write >/dev/null
expect "plan status --write puts it right" 'grep -q "Status:\*\* Now" docs/phases/1-one.md'
printf '# Phase 1: One\n\nThe first: #10 and #20.\n' >docs/phases/1-one.md
"$KIT" plan status --write >/dev/null
expect "--write adds the line under the title when the title is the milestone" \
  '[ "$(sed -n 3p docs/phases/1-one.md)" = "**Milestone:** Phase 1: One · **Status:** Now" ]'
sed -i '' 's/#10 and //' docs/phases/1-one.md
expect "an item its page doesn't mention fails" 'plan_fails "doesn'"'"'t mention #10 First plan"'
git checkout -q docs/phases/1-one.md
sed -i '' 's/Milestone:\*\* Phase 1: One/Milestone:** Phase 1: Uno/' docs/phases/1-one.md
expect "a page naming a milestone GitHub doesn't have fails" 'plan_fails "no milestone \"Phase 1: Uno\""'
git checkout -q docs/phases/1-one.md
sed -i '' 's/"no_page": \["Ideas"\]/"no_page": []/' .product-kit.json
expect "an open milestone with no page fails, unless no_page lists it" 'plan_fails "\"Ideas\" has no page in docs/phases/"'
git checkout -q .product-kit.json
printf '\nEdited by hand.\n' >>docs/phases/README.md
expect "an index edited by hand fails" 'plan_fails "docs/phases/README.md: written"'
expect "plan index --check says so too" '! "$KIT" plan index --check >/dev/null'
git checkout -q docs/phases/README.md
gh_set 's["milestones"].append({"id": "M8", "number": 8, "title": "Phase 4: Empty", "state": "OPEN", "dueOn": None})'
printf '# Phase 4: Empty\n\n**Milestone:** Phase 4: Empty · **Status:** Done\n' >docs/phases/4-empty.md
expect "an open milestone with nothing open in it fails: close it" 'plan_fails "\"Phase 4: Empty\" is open with nothing open in it: close it"'
rm docs/phases/4-empty.md
gh_set 's["milestones"].pop()'
gh_set 'b["fields"] = [f for f in b["fields"] if f["name"] != "Track"]'
expect "a field the config names that the board hasn't fails" 'plan_fails "has no field \"Track\" (plan.fields.inherit"'
echo 2 >"$G/flaky"
expect "a failed call is tried again" '"$KIT" plan status >/dev/null'
echo 9 >"$G/flaky"
expect "and gives up in plain words" 'plan_fails "couldn'"'"'t reach GitHub: connection reset by peer"'
rm "$G/flaky"
touch "$G/signed-out"
expect "gh signed out is said at once" 'plan_fails "isn'"'"'t signed in to GitHub"'
rm "$G/signed-out"
mv .product-kit.json "$TMP/elsewhere.json"
expect "--config reads a config from elsewhere, before -C moves" \
  '(cd "$TMP" && "$KIT" --config elsewhere.json -C "$Q" plan status | grep -q "1-one.md: \*\*Milestone")'
mv "$TMP/elsewhere.json" .product-kit.json
echo '{"repo": "someone/thing"}' >"$TMP/no-plan.json"
expect "a config with no plan says so" '{ "$KIT" --config "$TMP/no-plan.json" plan check 2>&1 || true; } | grep -q "no \"plan\" section"'
cd "$P" || exit 1

echo "--- the rest"
expect "-C runs in another folder" '(cd "$TMP" && "$KIT" -C "$P" anchors >/dev/null)'
expect "help lists the commands" '"$KIT" help | grep -q "docs-kit site"'
expect "outside a project it says what's missing" '(cd "$TMP" && mkdir -p bare && cd bare && git init -q && ! "$KIT" anchors 2>&1 | grep -q Traceback)'
mv .docs-kit.json .product-kit.json
echo '{}' >.docs-kit.json
expect ".product-kit.json is read first, shared with lang-kit" '"$KIT" anchors >/dev/null'
rm .docs-kit.json
expect "init writes .product-kit.json" '(cd "$TMP/bare" && "$KIT" init >/dev/null && [ -f .product-kit.json ])'

[ "$fails" -eq 0 ] && echo "docs-kit: every test passed" || echo "docs-kit: $fails failed"
exit $((fails > 0))
