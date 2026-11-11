# product-kit

Everything a product shows people, kept current and in every language: its **docs**, its
**pictures and videos**, and their **translations**, for the README, the wiki and the website.
A Claude Code plugin, for any project.

Each grew out of NetworkMonitor, where a feature that changed the interface used to leave stale
docs, stale screenshots and an untranslated page behind. product-kit makes them one system: one
config, one list of languages, one manifest of what each picture shows, and one order to do it
in. The plan is [#1](https://github.com/kevinabouhanna/product-kit/issues/1).

```
claude plugin install product-kit@kevinabouhanna --scope user
```

The plugin is listed in the `kevinabouhanna` marketplace (kevinabouhanna/claude-parallel-sessions).
It puts `product-kit`, `docs-kit`, `lang-kit` and `shots-kit` on PATH and gives every session the skill for each
part. They share one config, `.product-kit.json`, with the languages listed once.

## The parts

| Part | Does | State |
|---|---|---|
| `product-kit docs` (`docs-kit`) | `docs/` is the one source; the website's docs pages and the wiki are built from it, and a check asks for docs with the feature. [Reference](docs/docs-kit.md) | ✅ |
| `product-kit lang` (`lang-kit`) | Every language's table held to the app and to its glossary (Apple `.strings` and `.xcstrings`, JSON, `.resx`, Qt `.ts`); a changed page needs its copy; what each release changed, for the native reviewer; adding a language. [Reference](docs/lang-kit.md) | ✅ |
| `product-kit shots` (`shots-kit`) | Every picture, GIF and video listed with the window it shows; reads each picture's window through the Accessibility API, or compares the app's own drawings of it pixel by pixel, retakes only those whose interface changed, and flags the videos. With or without a website. [Reference](docs/shots-kit.md) | ✅ macOS apps (NetworkMonitor, claude-profiles-mac); web and Windows: #1, step 5 |
| `product-kit status` | What's out of date for a release, across all of it | #1, step 7 |

## The order

Language runs through every step: a translated picture is a capture of the translated app.

1. **Words**: the app's text and the docs, in every language, in the same pull request.
2. **Build and release.**
3. **Pictures**: retaken in every language, only where the interface changed.
4. **Videos**: flagged when they show a changed window; remade by hand, when asked.
5. **Publish**: README, wiki, website.
6. **Native review**, after the release.

## Working on it

`tests/run.sh` runs the tests, offline. Each project keeps a copy of the tools it runs in CI
(`docs-kit vendor`, `lang-kit vendor`, `shots-kit vendor`), so its CI needs no plugin.
`tests/run.sh` builds shots-kit, so it needs Swift (Command Line Tools). The workflow is in [CLAUDE.md](CLAUDE.md).
