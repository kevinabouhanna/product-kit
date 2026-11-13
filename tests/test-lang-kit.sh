#!/bin/bash
#
# lang-kit (#4), offline: small projects in a temporary folder, one per table
# format, and each command checked against them.
# Usage: tests/test-lang-kit.sh

set -uo pipefail
KIT="$(cd "$(dirname "$0")/.." && pwd)/bin/lang-kit"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fails=0
ok() { printf '  ok    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; fails=$((fails + 1)); }
expect() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }
lk() { python3 -I "$KIT" "$@"; }
lks() { python3 -I "$KIT" "$@" || true; }   # for a pipe: its output, whatever its status
repo() { rm -rf "$1"; mkdir -p "$1"; cd "$1" || exit 1; git init -q -b main; git config user.email t@t; git config user.name t; }
commit() { git add -A; git commit -qm "${1:-x}"; }

# --------------------------------------------------------------------------
echo "--- strings: Apple .strings, the text scanned from L(\"…\")"
P="$TMP/app"; repo "$P"
mkdir -p Sources Resources/en.lproj Resources/fr.lproj docs/fr
cat >.product-kit.json <<'EOF'
{
  "repo": "me/app",
  "languages": {"fr": {"name": "Français", "site": "fr"}},
  "developer_pages": ["docs/development.md"],
  "lang": {
    "strings": {"format": "strings", "path": "Resources/{code}.lproj/Localizable.strings",
                "keys": {"scan": ["Sources/*.swift"], "except": ["**/Skip.swift"]}},
    "glossary": "Resources/{code}.lproj/Glossary.json"
  }
}
EOF
cat >Sources/App.swift <<'EOF'
let a = L("Settings")
let b = L("Ad blocking is off")
let c = L("%@ of %@", x, y)   // a comment with L("Not a key")
// L("Commented out")
let d = L("Say \"hi\"\nthere")
let e = L("Hello \(name)")
EOF
echo 'let z = L("Skipped")' >Sources/Skip.swift
cat >Resources/fr.lproj/Localizable.strings <<'EOF'
/* French */
"Settings" = "Réglages";
"Ad blocking is off" = "Le blocage des pubs est désactivé"; // pubs, not the glossary's word
"%@ of %@" = "%2$@ sur %1$@";
"Say \"hi\"\nthere" = "Dis \"salut\"\nlà";
EOF
cat >Resources/fr.lproj/Glossary.json <<'EOF'
{"language": "fr", "name": "Français", "reviewer": "frfriend",
 "avoid": [{"text": "pubs", "why": "say publicités"}],
 "terms": [{"en": "Settings", "text": "Réglages", "everywhere": true},
           {"en": "Ad blocking", "text": "Blocage des publicités", "everywhere": true},
           {"en": "Wiki", "text": "Wiki", "where": "docs"}]}
EOF
commit
lk keys >"$TMP/keys.txt"
printf '%s\n' '%@ of %@' 'Ad blocking is off' 'Say "hi"\nthere' 'Settings' >"$TMP/want.txt"
expect "keys come from L(), comments and interpolations left out" 'cmp -s "$TMP/keys.txt" "$TMP/want.txt"'
out="$(lk strings)"; status=$?
expect "strings fails on the glossary's word missing" '[ $status -eq 1 ] && grep -q "doesn.t say \"Blocage des publicités\"" <<<"$out"'
expect "strings names a word to avoid, and why" 'grep -q "uses \"pubs\": say publicités" <<<"$out"'
expect "positional placeholders match sequential ones" '! grep -q "placeholders differ" <<<"$out"'
expect "a docs-only term isn't asked of the app" '! grep -q "Wiki" <<<"$out"'
sed -i '' 's/Le blocage des pubs est désactivé/Blocage des publicités désactivé/' Resources/fr.lproj/Localizable.strings
expect "a table in its glossary's words passes" 'lks strings | grep -q "all 4 pieces of text"'
echo 'let f = L("Quit")' >>Sources/App.swift
echo '"Gone" = "Parti";' >>Resources/fr.lproj/Localizable.strings
echo '"Settings %@" = "Réglages";' >>Resources/fr.lproj/Localizable.strings
echo 'let g = L("Settings %@", v)' >>Sources/App.swift
out="$(lk strings)"
expect "a missing piece of text is named" 'grep -q "1 missing, such as: Quit" <<<"$out"'
expect "text the app no longer says is named" 'grep -q "the app no longer says, such as: Gone" <<<"$out"'
expect "different placeholders are named" 'grep -q "placeholders differ: \"Settings %@\"" <<<"$out"'
rm Resources/fr.lproj/Glossary.json
expect "a missing glossary fails" 'lks strings | grep -q "no glossary at Resources/fr.lproj/Glossary.json"'
git checkout -q -- . && git clean -qfd

# --------------------------------------------------------------------------
echo "--- check: pages and their copies"
mkdir -p docs/fr
echo "# Home" >README.md; echo "# Accueil" >README.fr.md
echo "# Guide" >docs/guide.md; echo "# Guide" >docs/fr/guide.md
echo "# Dev" >docs/development.md
commit pages
git checkout -q -b change
echo "more" >>README.md; echo "more" >>docs/development.md
commit
out="$(PR_BODY="" lk check main)"; status=$?
expect "a changed page without its copy fails" '[ $status -eq 1 ] && grep -q "README.md changed, but not README.fr.md" <<<"$out"'
expect "a page for developers asks for nothing" '! grep -q development <<<"$out"'
expect "the pull request's reason lets it through" 'PR_BODY="Fixes a link.
No translation needed: a typo" lks check main | grep -q "only, as the pull request says"'
echo "plus" >>README.fr.md; commit
expect "with its copy changed too, it passes" 'PR_BODY="" lks check main | grep -q "changed with it (fr)"'
echo "# New" >docs/new.md
expect "a new page with no copy fails" 'PR_BODY="" lks check main | grep -q "docs/new.md is new, with no docs/fr/new.md"'
rm docs/new.md

# --------------------------------------------------------------------------
echo "--- review"
git checkout -q main
git tag v1
echo '"Quit" = "Quitter";' >>Resources/fr.lproj/Localizable.strings
echo "plus" >>docs/fr/guide.md
commit
out="$(lk review v1)"
expect "review heads each language, for its reviewer" 'grep -q "### Français (fr), v1 to HEAD, for @frfriend" <<<"$out"'
expect "review lists what's new in the table" 'grep -q "| Quit | Quitter |" <<<"$out" && grep -q "1 new or changed" <<<"$out"'
expect "review lists the pages changed" 'grep -q "Pages changed: \`docs/fr/guide.md\`" <<<"$out"'

# --------------------------------------------------------------------------
echo "--- add"
out="$(lk add de Deutsch)"
expect "add puts the language in the config" 'python3 -c "import json,sys; sys.exit(json.load(open(\".product-kit.json\"))[\"languages\"][\"de\"][\"name\"] != \"Deutsch\")"'
expect "add writes its glossary from another's terms" 'python3 -c "import json,sys; g=json.load(open(\"Resources/de.lproj/Glossary.json\")); sys.exit(not (g[\"language\"]==\"de\" and len(g[\"terms\"])==3 and g[\"terms\"][0][\"text\"]==\"\" and g[\"terms\"][0][\"everywhere\"]))"'
expect "add writes its table, and the checklist" '[ -f Resources/de.lproj/Localizable.strings ] && grep -q "The glossary first" <<<"$out"'
expect "strings then lists all of it as missing" 'lks strings | grep -q "Deutsch (de):"'

# --------------------------------------------------------------------------
echo "--- other formats"
P="$TMP/xc"; repo "$P"
cat >.product-kit.json <<'EOF'
{"languages": {"zh-Hans": {"name": "简体中文"}}, "lang": {"strings": {"format": "xcstrings", "path": "Localizable.xcstrings"}}}
EOF
cat >Localizable.xcstrings <<'EOF'
{"sourceLanguage": "en", "version": "1.0", "strings": {
  "Settings": {"localizations": {"zh-Hans": {"stringUnit": {"state": "translated", "value": "设置"}}}},
  "%lld items": {"localizations": {"zh-Hans": {"stringUnit": {"state": "translated", "value": "%lld 项"}}}},
  "Quit": {"localizations": {"zh-Hans": {"stringUnit": {"state": "new", "value": ""}}}},
  "v1.0": {"shouldTranslate": false}
}}
EOF
commit
expect "xcstrings: keys from the catalog, a new one missing, one not to translate left out" \
  'lks strings | grep -q "1 missing, such as: Quit" && [ "$(lk keys | wc -l | tr -d " ")" = 3 ]'

P="$TMP/web"; repo "$P"
mkdir -p locales
cat >.product-kit.json <<'EOF'
{"languages": {"es": {}}, "lang": {"strings": {"format": "json", "path": "locales/{code}.json"}}}
EOF
echo '{"menu": {"quit": "Quit", "count": "{n} files"}}' >locales/en.json
echo '{"menu": {"quit": "Salir", "count": "{count} archivos"}}' >locales/es.json
commit
out="$(lk strings)"
expect "json: nested keys, braces placeholders compared" 'grep -q "placeholders differ: \"{n} files\" → \"{count} archivos\"" <<<"$out"'
echo '{"language": "es", "terms": [{"en": "Quit", "text": "Cerrar"}]}' >locales/es.glossary.json
cat >.product-kit.json <<'EOF'
{"languages": {"es": {}}, "lang": {"strings": {"format": "json", "path": "locales/{code}.json"},
 "glossary": "locales/{code}.glossary.json"}}
EOF
expect "json: the glossary is held to the English text, not the key" \
  'lks strings | grep -q "\"Quit\" is \"Salir\", but the glossary says \"Cerrar\""'

P="$TMP/net"; repo "$P"
cat >.product-kit.json <<'EOF'
{"languages": {"fr": {}}, "lang": {"strings": {"format": "resx", "path": "Strings.{code}.resx", "source_path": "Strings.resx"}}}
EOF
cat >Strings.resx <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<root><data name="Quit" xml:space="preserve"><value>Quit</value></data>
<data name="Count" xml:space="preserve"><value>{0} speakers</value></data>
<data name="Icon" type="System.Resources.ResXFileRef"><value>icon.ico</value></data></root>
EOF
cat >Strings.fr.resx <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<root><data name="Quit" xml:space="preserve"><value>Quitter</value></data></root>
EOF
commit
expect "resx: the neutral file is the source, files left out" 'lks strings | grep -q "1 missing, such as: Count"'

P="$TMP/qt"; repo "$P"
cat >.product-kit.json <<'EOF'
{"languages": {"de": {}}, "lang": {"strings": {"format": "ts", "path": "i18n/app_{code}.ts"}}}
EOF
mkdir i18n
cat >i18n/app_de.ts <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE TS><TS version="2.1" language="de">
<context><name>Tray</name>
<message><source>Quit</source><translation>Beenden</translation></message>
<message><source>Switch to %1</source><translation type="unfinished"></translation></message>
<message><source>Old</source><translation type="obsolete">Alt</translation></message>
</context></TS>
EOF
commit
expect "ts: unfinished is missing, obsolete left out" 'out="$(lks strings)"; grep -q "1 missing, such as: Switch to %1" <<<"$out" && ! grep -q Old <<<"$out"'

# A kind of table lang-kit doesn't know, read by the project's own command (#37).
P="$TMP/own"; repo "$P"
mkdir -p i18n scripts
cat >.product-kit.json <<'EOF'
{"languages": {"it": {}}, "lang": {"strings": {"format": "command", "path": "i18n/{code}.properties",
 "read": ["python3", "scripts/read-properties", "{file}", "{code}"]}}}
EOF
cat >scripts/read-properties <<'EOF'
import json, sys
table = {}
for line in open(sys.argv[1], encoding="utf-8"):
    if "=" in line and not line.startswith("#"):
        k, v = line.split("=", 1); table[k.strip()] = v.strip()
print(json.dumps(table))
EOF
printf 'quit = Quit\nopen = Open %%@\n' >i18n/en.properties
printf 'quit = Esci\n' >i18n/it.properties
commit
expect "a reader of the project's own: its table is held like any other" 'lks strings | grep -q "1 missing, such as: open"'
cat >.product-kit.json <<'EOF'
{"languages": {"it": {}}, "lang": {"strings": {"format": "command", "path": "i18n/{code}.properties"}}}
EOF
expect "format command without read says what it needs" 'lks strings 2>&1 | grep -q "needs lang.strings.read"'
cat >.product-kit.json <<'EOF'
{"languages": {"it": {}}, "lang": {"strings": {"format": "command", "path": "i18n/{code}.properties", "read": ["false"]}}}
EOF
expect "a reader that fails is named" 'lks strings 2>&1 | grep -q "lang.strings.read failed (exit 1)"'

# --------------------------------------------------------------------------
echo "--- todo and apply: only what changed, as a packet (#39)"
P="$TMP/todo"; repo "$P"
mkdir -p Resources/en.lproj Resources/fr.lproj
cat >.product-kit.json <<'EOF'
{"languages": {"fr": {"name": "Français"}},
 "lang": {"strings": {"format": "strings", "path": "Resources/{code}.lproj/Localizable.strings"},
          "glossary": "Resources/{code}.lproj/Glossary.json"}}
EOF
printf '"quit" = "Quit";\n"open" = "Open the window";\n"save" = "Save";\n' >Resources/en.lproj/Localizable.strings
printf '"quit" = "Quitter";\n"save" = "Enregistrer";\n' >Resources/fr.lproj/Localizable.strings
cat >Resources/fr.lproj/Glossary.json <<'EOF'
{"language": "fr", "style": ["Vouvoyez."], "avoid": [{"text": "Ok", "why": "D'accord"}],
 "terms": [{"en": "window", "text": "fenêtre", "where": "docs"}, {"en": "Quit", "text": "Quitter"}]}
EOF
commit; git tag v1
printf '"quit" = "Quit";\n"open" = "Open the window";\n"save" = "Save all";\n' >Resources/en.lproj/Localizable.strings
commit
out="$(lk todo --since v1)"
expect "todo lists what's missing, and what's English changed since, with what it was" \
  'grep -q "Français (fr): 2 to translate; style: Vouvoyez.; never: Ok" <<<"$out" && grep -q "\"open\" = \"Open the window\"" <<<"$out" && grep -q "\"save\" = \"Save all\" (was \"Save\" → \"Enregistrer\")" <<<"$out"'
expect "and leaves out what's done" '! grep -q "\"quit\"" <<<"$out"'
expect "--json gives each piece its glossary terms" \
  'lk todo --since v1 --json | python3 -c "import json,sys; d=json.load(sys.stdin)[0]; sys.exit(d[\"language\"] != \"fr\" or len(d[\"items\"]) != 2)"'
echo '{"fr": {"open": "Ouvrir la fenêtre", "save": "Tout enregistrer"}}' >"$TMP/fr.json"
expect "apply writes them into the table and checks it" \
  'lk apply "$TMP/fr.json" | grep -q "all 3 pieces of text" && grep -q "^\"save\" = \"Tout enregistrer\";$" Resources/fr.lproj/Localizable.strings && grep -q "^\"open\" = \"Ouvrir la fenêtre\";$" Resources/fr.lproj/Localizable.strings'
expect "then there's nothing left to do" 'lk todo | grep -q "nothing to translate"'
echo '{"de": {"open": "Öffnen"}}' >"$TMP/de.json"
expect "apply refuses a language the project hasn't" 'lks apply "$TMP/de.json" 2>&1 | grep -q "de isn.t one of the project.s languages"'
P="$TMP/todo-json"; repo "$P"
mkdir -p locales
echo '{"languages": {"es": {}}, "lang": {"strings": {"format": "json", "path": "locales/{code}.json"}}}' >.product-kit.json
echo '{"menu": {"quit": "Quit", "open": "Open"}}' >locales/en.json
echo '{"menu": {"quit": "Salir"}}' >locales/es.json
commit
echo '{"es": {"menu.open": "Abrir"}}' >"$TMP/es.json"
expect "apply writes nested JSON tables" \
  'lk apply "$TMP/es.json" >/dev/null && python3 -c "import json; d=json.load(open(\"locales/es.json\")); exit(d[\"menu\"] != {\"quit\": \"Salir\", \"open\": \"Abrir\"})"'

# --------------------------------------------------------------------------
echo "--- all of Apple's text: permission prompts, plurals, Shortcuts (#41)"
P="$TMP/apple"; repo "$P"
mkdir -p Resources/en.lproj Resources/ar.lproj Resources/ru.lproj
cat >.product-kit.json <<'EOF'
{"languages": {"ar": {"name": "العربية"}, "ru": {"name": "Русский"}},
 "lang": {"strings": {"format": "strings", "path": "Resources/{code}.lproj/Localizable.strings"},
          "more": [{"format": "strings", "path": "Resources/{code}.lproj/InfoPlist.strings", "keys": {"plist": "Resources/Info.plist"}},
                   {"format": "stringsdict", "path": "Resources/{code}.lproj/Localizable.stringsdict"},
                   {"format": "xcstrings", "path": "Resources/AppShortcuts.xcstrings"}]}}
EOF
cat >Resources/Info.plist <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>me.App</string>
  <key>NSLocationUsageDescription</key><string>The app reads your Wi-Fi network's name.</string>
  <key>NSCameraUsageDescription</key><string>The app shows the camera.</string>
</dict></plist>
EOF
printf '"Quit" = "Quit";\n' >Resources/en.lproj/Localizable.strings
printf '"Quit" = "إنهاء";\n' >Resources/ar.lproj/Localizable.strings
printf '"Quit" = "Выйти";\n' >Resources/ru.lproj/Localizable.strings
printf '"NSLocationUsageDescription" = "يقرأ التطبيق اسم شبكة Wi-Fi.";\n' >Resources/ar.lproj/InfoPlist.strings
printf '"NSLocationUsageDescription" = "Приложение читает имя сети.";\n"NSCameraUsageDescription" = "Приложение показывает камеру.";\n' >Resources/ru.lproj/InfoPlist.strings
plural() { # code, then the forms as key=value
  local code="$1"; shift; local forms="" f
  for f in "$@"; do forms+="<key>${f%%=*}</key><string>${f#*=}</string>"; done
  cat >"Resources/$code.lproj/Localizable.stringsdict" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict><key>%d apps</key><dict>
  <key>NSStringLocalizedFormatKey</key><string>%#@apps@</string>
  <key>apps</key><dict><key>NSStringFormatSpecTypeKey</key><string>NSStringPluralRuleType</string>
    <key>NSStringFormatValueTypeKey</key><string>d</string>$forms</dict>
</dict></dict></plist>
EOF
}
plural en "one=%d app" "other=%d apps"
plural ar "one=تطبيق" "other=%d تطبيقات"
plural ru "one=%d приложение" "few=%d приложения" "many=%d приложений" "other=%d приложения"
cat >Resources/AppShortcuts.xcstrings <<'EOF'
{"sourceLanguage": "en", "version": "1.0", "strings": {
  "Show speed in ${applicationName}": {"localizations": {
    "ar": {"stringUnit": {"state": "translated", "value": "اعرض السرعة في ${applicationName}"}},
    "ru": {"stringUnit": {"state": "translated", "value": "Показать скорость в ${applicationName}"}}}}}}
EOF
commit
out="$(lks strings)"
expect "an Info.plist's permission prompts are text to translate, each one" \
  'grep -q "1 missing, such as: NSCameraUsageDescription" <<<"$out"'
expect "a count's text needs every form the language has: Arabic's six" \
  'grep -q "has no few, many, two, zero form in ar" <<<"$out"'
expect "Russian's four, all there" '! grep -q "form in ru" <<<"$out"'
expect "Shortcuts' phrases are held like any table" 'grep -q "lang-kit: Resources/AppShortcuts.xcstrings" <<<"$out"'
cat >Resources/AppShortcuts.xcstrings <<'EOF'
{"sourceLanguage": "en", "version": "1.0", "strings": {
  "%lld connections": {"localizations": {
    "en": {"variations": {"plural": {"one": {"stringUnit": {"state": "translated", "value": "%lld connection"}}, "other": {"stringUnit": {"state": "translated", "value": "%lld connections"}}}}},
    "ru": {"variations": {"plural": {"one": {"stringUnit": {"state": "translated", "value": "%lld соединение"}}, "other": {"stringUnit": {"state": "translated", "value": "%lld соединения"}}}}}}}}}
EOF
expect "a catalog's plurals need the language's forms too" 'lks strings | grep -q "\"%lld connections\" varies by count but has no few, many form in ru"'
expect "todo names the table each packet is for" 'lk todo | grep -q "العربية (ar): 1 to translate in Resources/{code}.lproj/InfoPlist.strings"'
echo '{"ar": {"NSCameraUsageDescription": "يعرض التطبيق الكاميرا."}}' >"$TMP/ar.json"
expect "apply --table writes into that table" \
  'lks apply "$TMP/ar.json" --table "Resources/{code}.lproj/InfoPlist.strings" >/dev/null; grep -q "NSCameraUsageDescription" Resources/ar.lproj/InfoPlist.strings'
out="$(lk add he Hebrew)"
expect "add sets up a new language's other tables too" '[ -f Resources/he.lproj/InfoPlist.strings ] && grep -q "wrote Resources/he.lproj/InfoPlist.strings" <<<"$out"'
expect "and says what a language written right to left needs" 'grep -q "written right to left" <<<"$out"'

# --------------------------------------------------------------------------
echo "--- the rest"
cd "$TMP/app" || exit 1
expect "vendor copies it to Scripts/lang-kit, runnable" 'lk vendor >/dev/null && [ -x Scripts/lang-kit ] && cmp -s Scripts/lang-kit "$KIT"'
expect "vendor --check says it's this copy" 'lk vendor --check | grep -q "is this copy"'
expect "a .docs-kit.json is read when there's no .product-kit.json" 'git mv .product-kit.json .docs-kit.json && lk keys >/dev/null'
expect "help lists the commands" 'lk help | grep -q "lang-kit review"'
cd "$TMP" || exit 1
expect "outside a project it says what's missing" '! lk strings 2>/dev/null'

[ "$fails" -eq 0 ] && echo "lang-kit: every test passed" || echo "lang-kit: $fails failed"
exit $((fails > 0))
