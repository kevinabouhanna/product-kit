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

echo "--- the rest"
expect "-C runs in another folder" '(cd "$TMP" && "$KIT" -C "$P" anchors >/dev/null)'
expect "help lists the commands" '"$KIT" help | grep -q "docs-kit site"'
expect "outside a project it says what's missing" '(cd "$TMP" && mkdir -p bare && cd bare && git init -q && ! "$KIT" anchors 2>&1 | grep -q Traceback)'

[ "$fails" -eq 0 ] && echo "docs-kit: every test passed" || echo "docs-kit: $fails failed"
exit $((fails > 0))
