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
# GitHub, recorded: a stand-in for gh that answers the plan's query, a page at a time.
Q="$TMP/planned"
mkdir -p "$Q/docs/phases" "$TMP/gh"
cat >"$TMP/gh/make.py" <<'EOF'
import json, pathlib, sys
here = pathlib.Path(sys.argv[0]).parent
variant = sys.argv[1] if len(sys.argv) > 1 else "base"
def item(order, horizon, number=8):
    return {"project": {"number": number, "owner": {"login": "Someone"}},
            "order": {"number": order} if order is not None else None,
            "horizon": {"name": horizon} if horizon else None}
def issue(n, title, milestone, parent=None, items=()):
    return {"number": n, "title": title, "milestone": {"title": milestone} if milestone else None,
            "parent": parent, "projectItems": {"nodes": list(items)}}
milestones = [
    {"number": 1, "title": "Phase 1: One", "state": "OPEN", "dueOn": "2027-01-01T00:00:00Z"},
    {"number": 2, "title": "Phase 2: Two", "state": "OPEN", "dueOn": "2027-02-01T00:00:00Z"},
    {"number": 3, "title": "Phase 0: Start", "state": "CLOSED", "dueOn": None},
    {"number": 4, "title": "Ideas", "state": "OPEN", "dueOn": None},
]
first = [
    issue(10, "First plan", "Phase 1: One", None, [item(2, "Now")]),
    issue(11, "A step of the first", "Phase 1: One", {"number": 10, "state": "OPEN"}, [item(2, "Now")]),
    issue(12, "Second | plan", "Phase 2: Two", None, [item(9, "Now", number=9), item(1, "Next")]),
    issue(13, "Orphan step", "Phase 2: Two", {"number": 99, "state": "CLOSED"}, [item(None, "Later")]),
]
second = [
    issue(14, "An idea", "Ideas", None, [item(3, "Later")]),
    issue(15, "Not in a milestone", None),
]
if variant == "empty-milestone":
    milestones.append({"number": 5, "title": "Phase 3: Empty", "state": "OPEN", "dueOn": None})
if variant == "off-board":
    first[1]["projectItems"]["nodes"] = []
if variant == "no-horizon":
    first[1]["projectItems"]["nodes"][0]["horizon"] = None
fields = [{"name": "Title", "dataType": "TITLE"}, {"name": "Order", "dataType": "NUMBER"},
          {"name": "Horizon", "dataType": "SINGLE_SELECT", "options": [{"name": n} for n in ("Now", "Next", "Later")]}]
def page(nodes, more):
    return {"data": {"repository": {"milestones": {"nodes": milestones},
                                    "issues": {"pageInfo": {"hasNextPage": more, "endCursor": "c1"}, "nodes": nodes}},
                     "repositoryOwner": {"projectV2": {"title": "Board", "fields": {"nodes": fields}}}}}
(here / "answer1.json").write_text(json.dumps(page(first, True)))
(here / "answer2.json").write_text(json.dumps(page(second, False)))
if variant == "error":
    (here / "answer1.json").write_text(json.dumps({"data": None, "errors": [{"message": "Could not resolve to a ProjectV2"}]}))
EOF
cat >"$TMP/gh/gh.py" <<'EOF'
import pathlib, sys
here = pathlib.Path(sys.argv[0]).parent
flaky = here / "flaky"
if flaky.exists() and int(flaky.read_text()) > 0:
    flaky.write_text(str(int(flaky.read_text()) - 1))
    sys.exit("connection reset by peer")
(here / "calls").open("a").write(" ".join(a for a in sys.argv[1:] if not a.startswith("query=")) + "\n")
print((here / ("answer2.json" if any(a.startswith("after=") for a in sys.argv) else "answer1.json")).read_text())
EOF
gh_answers() { python3 -I "$TMP/gh/make.py" "${1:-base}"; }
gh_answers
export DOCS_KIT_GH="python3 -I $TMP/gh/gh.py" DOCS_KIT_RETRY_WAIT=0
cd "$Q" || exit 1
git init -q -b main . && git config user.email t@example.com && git config user.name t
cat >.product-kit.json <<'EOF'
{
  "repo": "someone/thing",
  "plan": { "pages": "docs/phases", "index": "docs/phases/README.md",
            "project": { "owner": "someone", "number": 8 }, "no_page": ["Ideas"] }
}
EOF
printf '# Phase 1: One\n\n**Milestone:** Phase 1: One · **Status:** Now\n\nThe first: #10.\n' >docs/phases/1-one.md
printf '# Phase 2: Two\n\n**Milestone:** Phase 2: Two · **Status:** Next\n\n#12 and #13, after #10 in phase one.\n' >docs/phases/2-two.md
printf '# Phase 0: Start\n\n**Milestone:** Phase 0: Start · **Status:** Done\n' >docs/phases/0-start.md
printf '# Our plan\n\nWhat the phases are.\n\n## Old\n\nStale.\n' >docs/phases/README.md
git add -A && git commit -qm plan

expect "plan index --check says when the index is out of date" '! "$KIT" plan index --check >/dev/null'
"$KIT" plan index >/dev/null || fail "plan index ran"
index="$(cat docs/phases/README.md)"
expect "the index keeps the text above its first section, under a note" \
  '[ "$(sed -n 1,4p docs/phases/README.md | tail -3)" = "$(printf "# Our plan\n\nWhat the phases are.")" ] && grep -q "^<!-- Written by .docs-kit plan index" <<<"$index" && ! grep -q Stale <<<"$index"'
expect "a section per Horizon, in the board's order, and Done last" \
  '[ "$(grep "^## " <<<"$index" | tr "\n" " ")" = "## Now ## Next ## Later ## Done " ]'
expect "a row per plan: Order, #N title, the phase's page" \
  'grep -qF "| 2 | #10 First plan | [Phase 1: One](1-one.md) |" <<<"$index"'
expect "the board's own item counts, not another board's" 'grep -qF "| 1 | #12 Second \| plan | [Phase 2: Two](2-two.md) |" <<<"$index"'
expect "a sub-issue isn't a plan, unless its parent is closed" \
  '! grep -q "#11" <<<"$index" && grep -q "#13 Orphan step" <<<"$index"'
expect "plans by Order, those with none last; a phase with no page by name" \
  '[ "$(grep -o "#1[34] [A-Za-z ]*| [A-Za-z]*" <<<"$index" | tr "\n" ";")" = "#14 An idea | Ideas;#13 Orphan step | ;" ]'
expect "Done links the finished phases" 'grep -qx "\[Phase 0: Start\](0-start.md)" <<<"$index"'
expect "the second page of issues is read" 'grep -q "after=c1" "$TMP/gh/calls"'
expect "index again changes nothing" '"$KIT" plan index | grep -q "already up to date" && "$KIT" plan index --check >/dev/null'
expect "plan check passes when the pages, the milestones, the issues and the board agree" '"$KIT" plan check >/dev/null'
git add -A && git commit -qm index

plan_fails() { # plan_fails <what it should say>
  out="$("$KIT" plan check 2>&1)"; [ $? -ne 0 ] && grep -qF "$1" <<<"$out" && ! grep -q Traceback <<<"$out"
}
sed -i '' 's/Status:\*\* Now/Status:** Later/' docs/phases/1-one.md
expect "a wrong Status fails, saying why" 'plan_fails "Status is Later, and should be Now (#10 is Now)"'
"$KIT" plan status --write >/dev/null
expect "plan status --write puts it right" 'grep -q "Status:\*\* Now" docs/phases/1-one.md && "$KIT" plan check >/dev/null'
printf '# Phase 1: One\n\nThe first: #10.\n' >docs/phases/1-one.md
"$KIT" plan status --write >/dev/null
expect "--write adds the line under the title when the title is the milestone" \
  '[ "$(sed -n 3p docs/phases/1-one.md)" = "**Milestone:** Phase 1: One · **Status:** Now" ]'
git checkout -q docs/phases/1-one.md
sed -i '' 's/#10/the first plan/' docs/phases/1-one.md
expect "an open plan its page doesn't mention fails" 'plan_fails "doesn'"'"'t mention #10 First plan"'
git checkout -q docs/phases/1-one.md
sed -i '' 's/Milestone:\*\* Phase 2: Two/Milestone:** Phase 2: Too/' docs/phases/2-two.md
expect "a page naming a milestone GitHub doesn't have fails" 'plan_fails "no milestone \"Phase 2: Too\""'
expect "and so does the milestone with no page" 'plan_fails "\"Phase 2: Two\" has no page"'
git checkout -q docs/phases/2-two.md
sed -i '' 's/"no_page": \["Ideas"\]/"no_page": []/' .product-kit.json
expect "an open milestone with no page fails, unless no_page lists it" 'plan_fails "\"Ideas\" has no page in docs/phases/"'
git checkout -q .product-kit.json
sed -i '' 's/"number": 8 }/"number": 8 }, "fields": { "target": "Target" }/' .product-kit.json
expect "a field the board doesn't have fails" 'plan_fails "has no field \"Target\" (plan.fields.target"'
git checkout -q .product-kit.json
printf '\nEdited by hand.\n' >>docs/phases/README.md
expect "an index edited by hand fails" 'plan_fails "docs/phases/README.md is out of date"'
git checkout -q docs/phases/README.md
gh_answers empty-milestone
printf '# Phase 3: Empty\n\n**Milestone:** Phase 3: Empty · **Status:** Done\n' >docs/phases/3-empty.md
expect "an open milestone with no open issues fails: close it" 'plan_fails "\"Phase 3: Empty\" is open with no open issues: close it"'
rm docs/phases/3-empty.md
gh_answers off-board
expect "an issue in a milestone that isn't on the board fails" 'plan_fails "#11 A step of the first (in \"Phase 1: One\") isn'"'"'t on the board"'
gh_answers no-horizon
expect "one with no Horizon fails" 'plan_fails "#11 A step of the first (in \"Phase 1: One\") has no Horizon"'
gh_answers error
expect "GitHub's errors are said plainly" 'plan_fails "GitHub said: Could not resolve to a ProjectV2"'
gh_answers
echo 2 >"$TMP/gh/flaky"
expect "a failed call is tried again" '"$KIT" plan check >/dev/null'
echo 9 >"$TMP/gh/flaky"
expect "and gives up in plain words" 'plan_fails "couldn'"'"'t read the plan from GitHub: connection reset by peer"'
rm "$TMP/gh/flaky"
expect "gh signed out is said at once" \
  'DOCS_KIT_GH="printf \"To get started with GitHub CLI, please run:  gh auth login\nAlternatively, populate the GH_TOKEN environment variable.\n\" >&2; exit 4 #" plan_fails "isn'"'"'t signed in to GitHub"'
mv .product-kit.json "$TMP/elsewhere.json"
expect "--config reads a config from elsewhere, before -C moves" \
  '(cd "$TMP" && "$KIT" --config elsewhere.json -C "$Q" plan check >/dev/null)'
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
