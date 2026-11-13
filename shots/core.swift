// shots-kit: keeps a website's pictures of a macOS app current, without anyone
// looking at them. Part of product-kit (kevinabouhanna/product-kit#6); it grew
// out of NetworkMonitor's site-shots (NetworkMonitor#329), whose issues the
// notes below name.
//
// Each picture on the site has an entry in the site's `shots/shots.json`: the
// launch arguments that open its window, anything to click first, and which
// parts of the window are data rather than interface. For each entry it opens
// the installed app and reads the window's accessibility tree: roles, labels,
// sizes. Numbers, dates, settings' values and the regions marked as data are
// masked, so the tree changes only when the interface does. It compares that
// with the tree recorded when the picture was taken (`shots/trees/<name>.txt`):
//
//   check            reports what changed, and which videos or staged pictures
//                    show a window that changed (they're remade by hand).
//                    With --look, and on `update`, also as advice the windows
//                    that look different from their pictures, outside what's
//                    masked (`<name>.look`)
//   update [names]   retakes the pictures whose window changed (or the ones
//                    named), records their trees, and updates the page: each
//                    picture's size, the clickable areas laid over it, and the
//                    `?v=` on every asset link
//   tree <name>      prints the masked tree, for writing an entry
//   audit [names]    checks each window for what VoiceOver can't name, on
//                    real data in its lists
//   readme           copies the site's pictures the README uses into it, in
//                    every language. Files only. `update` copies each one it
//                    retakes
//   record <names>   records the named windows' trees as they read now,
//                    without retaking their pictures: after marking more of
//                    a window as data or ignored. And keeps each picture's
//                    look from the picture as it is
//   coverage         every image, GIF and video the site, the README and the
//                    docs use is a shot's picture or listed with the windows
//                    it shows. Files only, so it runs in CI
//   coverage-test    where `coverage` looks for media, on made-up pages
//   mask             prints each line it reads as a tree would show it: the
//                    numbers, dates and the project's own values masked, in
//                    every language the project shows. Files only
//   mask-test        the masks on made-up labels in several languages
//   version
//
// With --vm (or `vm.default` in the config, and not --here), check, update,
// record, tree and audit run in a throwaway macOS VM (`mac-vm`, from the
// shared-mac plugin) rather than on this Mac's screen, and bring back what they
// changed (product-kit#10). See `InVM`.
//
// What's particular to a project is in its `.product-kit.json` (`--repo`, the
// current folder by default): `shots` (see `Config`) and `site.url`. A project
// with no website keeps `shots/shots.json` in its own checkout (product-kit#8).
//
// Or the project draws its pictures itself (product-kit#8): the manifest's
// `render` builds it and runs a command that writes each picture, out of sight,
// from fixed data. Then `check` compares each drawing with its picture, pixel
// by pixel, and `update` copies the ones that differ: no app, no screen, no
// lanes. See `Rendered`.
//
// It needs Accessibility and Screen Recording for the terminal it runs in. It
// takes the app's Mac lane and `screen` itself (mac-lane, from the shared-mac
// plugin), only while it reads or takes windows. A shot that needs a window
// brought forward or a real click while someone is using the Mac isn't taken:
// it's reported as not taken, and why, and never waited on unless asked
// (`--wait-away MINUTES`: silently, with the lanes free). Nobody is ever asked
// to step away. It quits and relaunches the app, and whenever it lets the
// lanes go, however the run ends, puts the installed copy back running if it
// was.
//
// Build: swiftc -O -parse-as-library <its files, in shots/SOURCES' order, or the one
// file `shots-kit vendor` writes> AccessibilityAudit.swift
// (`shots-kit` in product-kit does it, and keeps the build), with the project's
// own AccessibilityAudit.swift when it has one (`shots.audit`).

import AppKit
import AVFoundation
import ApplicationServices
import CryptoKit
import ScreenCaptureKit

let shotsKitVersion = "2.9.0"

// MARK: - Config

/// What's particular to a project: `shots` in its `.product-kit.json`, and
/// the site's address from `site.url`. Every key is optional.
struct Config {
    /// The site's checkout, from the project's main checkout (so the same from
    /// any worktree), such as `../App-site`. `--site` overrides it.
    var site: String?
    /// The README's and the docs' list of their assets, in the repo.
    var repoAssets = "assets.json"
    /// The app's Mac lane; the bundle id's last part, lowercased, by default.
    var lane: String?
    /// Launch arguments that open windows behind the others without
    /// activating the app, for commands that only read the tree.
    var background: [String] = []
    /// Launch arguments that show the app in a language; `{code}` is its code.
    var language = ["-AppleLanguages", "({code})"]
    /// The app's table for a language, in its bundle; `{code}` is its code.
    var strings = "Contents/Resources/{code}.lproj/Localizable.strings"
    /// The site's address: links to its assets written with it are the site's.
    var siteURL: String?
    /// The branches the site and the repo are on, for the asset check's report.
    var siteBranch = "gh-pages"
    var repoBranch = "main"
    /// Taking the pictures in a throwaway VM (product-kit#10): see `InVM`.
    var vm = VMConfig()
    /// The languages the project shows, by code (`languages` in the config, and
    /// the source language): their dates and times are masked (product-kit#32).
    var languages: [String] = []
    /// The project's own values that change by themselves, masked after the
    /// numbers and dates: `shots.masks`, each a pattern and what it stands for.
    var masks: [(pattern: String, token: String)] = []
    /// Roles whose size is kept whole, numbers and all: one drawn at a fixed
    /// width whatever it shows, such as a menu-bar readout (`shots.keep_width`).
    var keepWidth: Set<String> = []
    /// The site's folder of pictures, GIFs and videos (`shots.media`).
    var media = "assets"
    /// The site's page that shows the pictures and their clickable areas, in
    /// the first language (`shots.page`); each other language names its own.
    var page = "index.html"

    static func load(repo: URL) -> Config {
        var c = Config()
        guard let data = try? Data(contentsOf: repo.appendingPathComponent(".product-kit.json")),
              let top = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return c }
        c.siteURL = (top["site"] as? [String: Any])?["url"] as? String
        let source = (top["lang"] as? [String: Any])?["source"] as? String
        c.languages = (source.map { [$0] } ?? []) + ((top["languages"] as? [String: Any])?.keys.sorted() ?? [])
        guard let shots = top["shots"] as? [String: Any] else { return c }
        for rule in shots["masks"] as? [[String: String]] ?? [] {
            if let pattern = rule["pattern"], let token = rule["as"] { c.masks.append((pattern, token)) }
        }
        if let v = shots["keep_width"] as? [String] { c.keepWidth = Set(v) }
        if let v = shots["media"] as? String { c.media = v.hasSuffix("/") ? String(v.dropLast()) : v }
        if let v = shots["page"] as? String { c.page = v }
        c.site = shots["site"] as? String
        if let v = shots["repo_assets"] as? String { c.repoAssets = v }
        c.lane = shots["lane"] as? String
        let launch = shots["launch"] as? [String: Any]
        if let v = launch?["background"] as? [String] { c.background = v }
        if let v = launch?["language"] as? [String] { c.language = v }
        if let v = shots["strings"] as? String { c.strings = v }
        let branches = shots["branches"] as? [String: String]
        if let v = branches?["site"] { c.siteBranch = v }
        if let v = branches?["repo"] { c.repoBranch = v }
        if let vm = shots["vm"] as? [String: Any] {
            if let v = vm["default"] as? Bool { c.vm.byDefault = v }
            if let v = vm["display"] as? String { c.vm.display = v }
            if let v = vm["files"] as? [String] { c.vm.files = v }
            c.vm.setup = vm["setup"] as? String
            c.vm.prepare = vm["prepare"] as? String
            c.vm.image = vm["image"] as? String
        }
        return c
    }
}

/// `shots.vm`: how a run in a VM sets the VM up (product-kit#10).
struct VMConfig {
    /// Pictures are taken in a VM unless `--here` says this Mac.
    var byDefault = false
    /// The VM's screen in pixels, shown at 2x: 3200x2000 is a 1600×1000-point
    /// Retina screen, where a 1300×800-point window fits.
    var display = "3200x2000"
    /// Files and folders of this Mac copied to the same place in the VM before
    /// the app opens (`~` the home folder): the app's data and settings, for
    /// pictures that show them.
    var files: [String] = []
    /// A command run in the VM from the project's copy, once the app is
    /// installed (`$SHOTS_APP`) and before any picture: the app's first-run state.
    /// What `prepare` made is in `$SHOTS_VM_DIR`.
    var setup: String?
    /// A command run on this Mac, in the project, before the VM starts: it
    /// writes into `$SHOTS_VM_DIR`, which goes into the VM, what has to be made
    /// from this Mac (other apps' icons, its time zone) (product-kit#12).
    var prepare: String?
    /// The project's own image to clone (`mac-vm image`), set up once with
    /// what the app needs approved, rather than the golden image (product-kit#12).
    var image: String?
}

nonisolated(unsafe) var config = Config()
/// The project's checkout (`--repo`).
nonisolated(unsafe) var repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

// MARK: - Manifest

struct Manifest: Decodable {
    var app: String
    var bundle: String
    var shots: [Shot]
    /// The site's assets this tool doesn't take: see `HandMade`.
    var assets: [HandMade]?
    /// The other languages the site has a page in (NetworkMonitor#431). Each shot is taken
    /// again in each, for its page.
    var languages: [Language]?
    /// Pictures the project draws itself (product-kit#8): no app or window to
    /// open, so its shots name only their `file` and their `render`.
    var render: Render?
    /// A program that opens each screen and says what it shows (product-kit#35): an
    /// iPhone app in the simulator, a web page. `app` and `bundle` are then optional.
    var driver: DriverConfig?
    /// The README's and the docs' files in `assets` (`"in": "repo"`), apart (product-kit#36).
    var repoListed: [HandMade] = []

    enum CodingKeys: String, CodingKey { case app, bundle, shots, assets, languages, render, driver }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        assets = try c.decodeIfPresent([HandMade].self, forKey: .assets)
        languages = try c.decodeIfPresent([Language].self, forKey: .languages)
        render = try c.decodeIfPresent(Render.self, forKey: .render)
        driver = try c.decodeIfPresent(DriverConfig.self, forKey: .driver)
        if driver != nil {
            app = try c.decodeIfPresent(String.self, forKey: .app) ?? ""
            bundle = try c.decodeIfPresent(String.self, forKey: .bundle) ?? ""
            shots = try c.decode([Shot].self, forKey: .shots)
        } else if render != nil {
            app = try c.decodeIfPresent(String.self, forKey: .app) ?? ""
            bundle = try c.decodeIfPresent(String.self, forKey: .bundle) ?? ""
            shots = try c.decode([Rendered.Shot].self, forKey: .shots).map {
                Shot(name: $0.name, file: $0.file, open: [], window: "", render: $0.render)
            }
        } else {
            app = try c.decode(String.self, forKey: .app)
            bundle = try c.decode(String.self, forKey: .bundle)
            shots = try c.decode([Shot].self, forKey: .shots)
        }
    }
}

/// `shots/shots.json`: on the site, or in the project's checkout when it has no
/// site (product-kit#8).
func loadManifest(_ site: URL) throws -> Manifest {
    let file = site.appendingPathComponent("shots/shots.json")
    guard FileManager.default.fileExists(atPath: file.path) else {
        throw Failure(manifestInRepo
            ? "no shots/shots.json: put it in the project's checkout, or say where the site is (shots.site in .product-kit.json, or --site)"
            : "no shots/shots.json in \(site.path)")
    }
    var manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: file))
    // The README's and the docs' files it lists (`"in": "repo"`) are the README's list,
    // when the manifest is on a site; with no site they're in the same checkout anyway.
    if !manifestInRepo, let all = manifest.assets {
        manifest.repoListed = all.filter { $0.place == "repo" }
        manifest.assets = all.filter { $0.place != "repo" }
    }
    masks = try Masks(languages: ["en"] + config.languages + (manifest.languages ?? []).map(\.code), project: config.masks)
    return manifest
}

/// The project has no site: the manifest and its pictures are in its checkout,
/// and the README's and the docs' assets are listed in it (product-kit#8).
nonisolated(unsafe) var manifestInRepo = false

/// A language the site has a page in (NetworkMonitor#431). Its pictures are taken from the
/// app shown in that language (`-language`), into a folder of their own, for
/// its page; their trees are kept apart too. Element specs are translated with
/// the app's own table, so the manifest names each element once, in English.
struct Language: Decodable {
    /// The app's code for it: `zh-Hans`.
    var code: String
    /// Its page, from the site's root: `zh/index.html`.
    var page: String
    /// Where its pictures go: `assets/zh-Hans/`, the English one's path after it.
    var assets: String
    /// Labels in specs the table can't translate, because a spec names only
    /// the start of one (`This connection was already`) or a part (`~on metered
    /// connections`): the English as written in the spec, to this language's.
    var specs: [String: String]?

    /// From its page's folder back to the site's root: `../` for `zh/index.html`.
    var up: String { String(repeating: "../", count: page.split(separator: "/").count - 1) }

    /// Where it keeps its copy of an English picture.
    func file(_ english: String) -> String {
        english.hasPrefix(config.media + "/") ? assets + english.dropFirst(config.media.count + 1) : english
    }
}

/// Element specs and window titles in another language, from the app's table
/// for it (`<code>.lproj/Localizable.strings` in the app), and the language's
/// `specs` for what the table can't say.
final class Translator {
    let table: [String: String]
    let overrides: [String: String]
    /// Labels found in neither, which stay English: report them.
    private(set) var missing: Set<String> = []

    init(app: String, language: Language) throws {
        let url = URL(fileURLWithPath: app).appendingPathComponent(config.strings.replacingOccurrences(of: "{code}", with: language.code))
        guard let table = NSDictionary(contentsOf: url) as? [String: String] else {
            throw Failure("\(app) has no \(language.code) table; is it a version with that language?")
        }
        self.table = table
        overrides = language.specs ?? [:]
    }

    /// `Role:label`, `Role:~part` and `Outer>Inner`, with the labels translated.
    func spec(_ spec: String) -> String {
        spec.components(separatedBy: ">").map { part in
            let pieces = part.split(separator: ":", maxSplits: 1).map(String.init)
            return pieces.count == 2 ? "\(pieces[0]):\(label(pieces[1]))" : part
        }.joined(separator: ">")
    }

    /// A window's title, or a spec for one that has none.
    func window(_ title: String) -> String { title.hasPrefix("AX") ? spec(title) : label(title) }

    func label(_ english: String) -> String {
        if let own = overrides[english] { return own }
        let part = english.hasPrefix("~")
        let text = part ? String(english.dropFirst()) : english
        if let translated = table[text] { return (part ? "~" : "") + translated }
        // A separator or a number is the same in every language; a name may
        // be too (`kevinabouhanna`), which the report lets you tell.
        if text.rangeOfCharacter(from: .letters) != nil { missing.insert(english) }
        return english
    }
}

/// An image, GIF or video the pages use that isn't a shot's picture (NetworkMonitor#413).
/// Every asset a page uses must be either a shot's `file` or one of these, so
/// none can go stale unnoticed: `coverage` fails on any that isn't.
struct HandMade: Decodable {
    var file: String
    /// The shots whose windows it shows. When one changes, it's named for
    /// remaking by hand until that shot is updated by name.
    var shows: [String]?
    /// Or why it shows no window this tool can check: an icon, the menu bar.
    var none: String?
    /// Or, in the README's list, the shot whose picture it's a copy of (NetworkMonitor#434):
    /// `update` copies the site's picture here, and each language's to
    /// `<folder>/<code>/<name>`, which needn't be listed.
    var copy: String?
    /// With `shows`, required: the app version it was made from, such as
    /// `1.28.1` (NetworkMonitor#421). It fails the check when it's older than the record of
    /// a window it shows (`Versions`), so an asset that was out of date on the
    /// day it was listed doesn't pass.
    var made: String?
    /// The issue its remake waits on, such as `NetworkMonitor#458`, when it's out of date
    /// and can't be remade yet: the check names it without failing. It fails
    /// again once the asset is as new as its windows, until this comes out.
    var stale: String?
    /// `repo`: a file of the README's or the docs', in the project's checkout, listed in a
    /// manifest that's on the site, when the site is on the same branch (product-kit#36).
    var place: String?
    /// How it's made: `taken` (a driver's picture), `drawn` (by the app), `recorded`,
    /// `built` (a video made from the pictures), or `hand`, the default for one that `shows`
    /// windows (product-kit#36). Scripted videos and store pictures go by it.
    var how: String?

    static let hows: Set<String> = ["taken", "drawn", "recorded", "built", "hand"]

    enum CodingKeys: String, CodingKey { case file, shows, none, copy, made, stale, place = "in", how }
}

/// The app version each window's record was taken from (NetworkMonitor#421), in
/// `shots/trees/versions.json`, by file name: `{"popover.txt": "1.28.1",
/// "popover.made.txt": "1.28.1"}`. English only, as what's made by hand is.
/// `update` keeps a record's version while the tree it holds stays the same,
/// since the window looked the same then, and sets this run's app version
/// when it changes.
enum Versions {
    static let file = "versions.json"

    static func read(_ trees: URL) -> [String: String] {
        guard let data = try? Data(contentsOf: trees.appendingPathComponent(file)),
              let versions = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return versions
    }

    static func write(_ versions: [String: String], to trees: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try (encoder.encode(versions) + Data("\n".utf8)).write(to: trees.appendingPathComponent(file))
    }

    /// The version of the app at `path`, from its Info.plist.
    static func app(_ path: String) -> String? {
        // A Mac app's is in Contents/; an iPhone app's at its top (product-kit#44).
        for inside in ["Contents/Info.plist", "Info.plist"] {
            let plist = URL(fileURLWithPath: path).appendingPathComponent(inside)
            if let version = NSDictionary(contentsOf: plist)?["CFBundleShortVersionString"] as? String { return version }
        }
        return nil
    }

    /// `1.26.7`, `1.28`: numbers and dots only.
    static func valid(_ version: String) -> Bool {
        version.range(of: #"^\d+(\.\d+)*$"#, options: .regularExpression) != nil
    }

    /// Whether `a` is an earlier version than `b`: 1.9 is before 1.10.
    static func older(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p < q }
        }
        return false
    }
}

/// The README's and the docs' assets, in `Resources/README/assets.json` on
/// `main`, listed the same way.
struct RepoAssets: Decodable {
    var assets: [HandMade]

    /// The README's and the docs' list: `shots.repo_assets`'s file, and the manifest's
    /// entries for them (`"in": "repo"`, product-kit#36), as one.
    static func of(_ file: RepoAssets?, _ manifest: Manifest) -> RepoAssets? {
        if manifest.repoListed.isEmpty { return file }
        return RepoAssets(assets: (file?.assets ?? []) + manifest.repoListed)
    }
}

/// What the README's list is called in a report: its file, or the manifest's entries.
func repoListName(_ repo: URL, _ manifest: Manifest) -> String {
    if manifest.repoListed.isEmpty { return repoAssetsPath }
    return FileManager.default.fileExists(atPath: repo.appendingPathComponent(repoAssetsPath).path)
        ? repoAssetsPath : "shots/shots.json (\"in\": \"repo\")"
}

/// Where the repo's list lives, relative to its checkout.
var repoAssetsPath: String { config.repoAssets }

/// A language's copy of one of the README's pictures: `Resources/README/<code>/speed-test.png`.
func repoFile(_ english: String, in language: Language?) -> String {
    guard let language else { return english }
    let url = URL(fileURLWithPath: english)
    let folder = url.deletingLastPathComponent().relativePath
    return (folder == "." ? "" : folder + "/") + language.code + "/" + url.lastPathComponent
}

/// Copies into the README each site picture it uses, in `language` (NetworkMonitor#434), so
/// the README's pictures in every language come from the run that takes the
/// site's: those of the shots in `shots`, or all of them. Only those a page
/// uses, or that are there already, so a language without a README gets none.
/// Returns what it copied.
func copyToRepo(manifest: Manifest, site: URL, repo: URL, repoAssets: RepoAssets?, language: Language?,
                shots: Set<String>? = nil) throws -> [String] {
    let uses = try Coverage.repoUses(repo)
    var copied: [String] = []
    for asset in repoAssets?.assets ?? [] {
        guard let name = asset.copy, shots?.contains(name) ?? true else { continue }
        guard let english = manifest.shots.first(where: { $0.name == name })?.file else {
            throw Failure("\(asset.file) is a copy of \"\(name)\", which isn't a shot with a picture")
        }
        let from = site.appendingPathComponent(language.map { $0.file(english) } ?? english)
        let file = repoFile(asset.file, in: language)
        let to = repo.appendingPathComponent(file)
        guard uses[file] != nil || FileManager.default.fileExists(atPath: to.path),
              let picture = try? Data(contentsOf: from), (try? Data(contentsOf: to)) != picture else { continue }
        try FileManager.default.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
        try picture.write(to: to)
        copied.append(file)
    }
    return copied
}

struct Shot: Decodable {
    var name: String
    /// The picture, relative to the site. None for a window that's only
    /// checked, for the videos and staged pictures in `flags`.
    var file: String?
    var open: [String]
    /// The window's title, or an element to find in any of the app's windows,
    /// such as `AXPopover`.
    var window: String
    /// Elements to click, in order, once the window is open.
    var click: [String]?
    /// A scroll area to scroll to its end, after the clicks.
    var scroll: String?
    /// An element to wait for, after the clicks, such as a speed test's
    /// result: the spec, and how many seconds to wait at most.
    var waitFor: Wait?
    /// Taken only when the window of the shot named here changed in the same
    /// run, or when named: for a shot that costs something to take, such as a
    /// speed test, which must never run just to check.
    var when: String?
    /// Skipped, with a note, while this element is in the window: a speed
    /// test can't run on a hotspot, where the app asks before spending data.
    /// A `when` shot that's skipped is tried again on the next update.
    var skipIf: String?
    /// Elements left out of the tree altogether: lines that come and go with
    /// the Mac's state, such as Hotspot's "already in Low Data Mode".
    var ignore: [String]?
    /// Regions whose contents are data: each one's roles are kept, not its
    /// labels, sizes or how many rows it has.
    var data: [DataRegion]?
    /// Part of the window, found by its elements so it follows the layout.
    var crop: Crop?
    /// Clickable areas laid over the picture on the page, placed from the
    /// window's elements.
    var areas: [Area]?
    /// Retaken on every update, changed or not: About shows the version.
    var always: Bool?
    /// Videos and staged pictures that show this window. They're reported when
    /// it changes, for remaking by hand. The older way of saying what the
    /// manifest's `assets` say with `shows`. With nowhere to say which version
    /// each was made from (`made`, NetworkMonitor#421), an entry here fails the check: list
    /// it under `assets` instead.
    var flags: [String]?
    /// The file the manifest's `render` writes for it (product-kit#8).
    var render: String?

    /// The same shot in `language`: the app opened in it, its elements named
    /// in it, its picture in the language's folder. Videos and staged pictures
    /// are the English shot's business.
    func localized(_ language: Language, _ t: Translator) -> Shot {
        var shot = self
        // AppleLanguages too, so dates and times come out as that language
        // writes them, as on a Mac set to it.
        shot.open = open + config.language.map { $0.replacingOccurrences(of: "{code}", with: language.code) }
        shot.window = t.window(window)
        shot.file = file.map(language.file)
        shot.click = click?.map(t.spec)
        shot.scroll = scroll.map(t.spec)
        shot.waitFor = waitFor.map { Wait(element: t.spec($0.element), seconds: $0.seconds) }
        shot.skipIf = skipIf.map(t.spec)
        shot.ignore = ignore?.map(t.spec)
        shot.data = data?.map { region in
            var region = region
            region.from = t.spec(region.from)
            region.until = region.until.map { ["end", "run"].contains($0) ? $0 : t.spec($0) }
            return region
        }
        shot.crop = crop.map { c in
            var c = c
            c.from = t.spec(c.from); c.through = t.spec(c.through)
            return c
        }
        shot.areas = areas?.map { a in
            var a = a
            a.element = t.spec(a.element)
            return a
        }
        shot.flags = nil
        return shot
    }
}

extension Shot {
    enum CodingKeys: String, CodingKey {
        case name, file, open, window, click, scroll, waitFor, when, skipIf, ignore, data, crop, areas, always, flags, render
    }

    /// `open` and `window` are the macOS driver's; a driver of the project's choosing
    /// may need neither (product-kit#35).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        file = try c.decodeIfPresent(String.self, forKey: .file)
        open = try c.decodeIfPresent([String].self, forKey: .open) ?? []
        window = try c.decodeIfPresent(String.self, forKey: .window) ?? ""
        click = try c.decodeIfPresent([String].self, forKey: .click)
        scroll = try c.decodeIfPresent(String.self, forKey: .scroll)
        waitFor = try c.decodeIfPresent(Wait.self, forKey: .waitFor)
        when = try c.decodeIfPresent(String.self, forKey: .when)
        skipIf = try c.decodeIfPresent(String.self, forKey: .skipIf)
        ignore = try c.decodeIfPresent([String].self, forKey: .ignore)
        data = try c.decodeIfPresent([DataRegion].self, forKey: .data)
        crop = try c.decodeIfPresent(Crop.self, forKey: .crop)
        areas = try c.decodeIfPresent([Area].self, forKey: .areas)
        always = try c.decodeIfPresent(Bool.self, forKey: .always)
        flags = try c.decodeIfPresent([String].self, forKey: .flags)
        render = try c.decodeIfPresent(String.self, forKey: .render)
    }
}

struct Wait: Decodable {
    var element: String
    var seconds: Double
}

struct DataRegion: Decodable {
    /// The element the region starts at, or starts `skip` siblings after:
    /// `skip: 1` marks the value beside a label, whatever it says.
    var from: String
    var skip: Int?
    /// The sibling that ends it (not included); "end" for the rest of its
    /// siblings; "run" for the siblings right after it with the same role, like
    /// a chart's bars. Absent, the region is the `from` element alone.
    var until: String?
    /// Lines that come and go with the Mac's state, such as Network's status
    /// lines on a hotspot (NetworkMonitor#416): the region may be empty, and only that it's
    /// there is kept, not its roles.
    var optional: Bool?
}

struct Crop: Decodable {
    /// The element at the top, and the one at the bottom.
    var from: String
    var through: String
    /// Points left out on each side, and added above the top and below the
    /// bottom.
    var inset: Double
    var pad: [Double]

    /// The rectangle in the window, in points.
    func rect(in window: AXUIElement) throws -> CGRect {
        guard let w = frame(window), let top = find(from, in: window).flatMap(frame),
              let bottom = find(through, in: window).flatMap(frame) else { throw Failure("can't find \(from) or \(through) to crop to") }
        let y = top.minY - w.minY - pad[0]
        return CGRect(x: inset, y: y, width: w.width - 2 * inset, height: bottom.maxY - w.minY + pad[1] - y)
    }
}

struct Area: Decodable {
    /// Text that picks out the area's tag on the page (`shots.page`), e.g. `data-pane="ads"`.
    var match: String
    /// The element it covers.
    var element: String
    /// The element's parent instead, e.g. a whole row for its label.
    var parent: Bool?
    /// Points added on each side: horizontally, vertically.
    var pad: [Double]?
    /// A fixed height, in points.
    var h: Double?
}

/// What changes by itself in a window's text, in every language the project
/// shows, masked so that only the interface counts (product-kit#32): numbers,
/// then month and weekday names and the parts of the day from macOS's own date
/// formats for each language, then the project's own values (`shots.masks`).
struct Masks {
    var rules: [(NSRegularExpression, String)] = []

    /// English as it was always masked, `Sept` and lower-case `am` included.
    static let englishMonths = ["January", "February", "March", "April", "May", "June", "July", "August", "September",
                                "October", "November", "December", "Jan", "Feb", "Mar", "Apr", "Jun", "Jul", "Aug",
                                "Sep", "Sept", "Oct", "Nov", "Dec"]
    static let englishDays = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday",
                              "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    static let englishTimes = ["AM", "PM", "am", "pm"]
    /// What a language says that its date formats don't: Chinese's 星期天.
    static let spoken = ["zh": ["星期天", "周天"]]

    init(languages: [String], project: [(pattern: String, token: String)] = []) throws {
        var months = Set(Masks.englishMonths), days = Set(Masks.englishDays)
        // The parts of the day said after a time (5:51 PM) and before one (下午5:51).
        var after = Set(Masks.englishTimes), before = Set<String>()
        for code in Set(languages) {
            let locale = Locale(identifier: code)
            let f = DateFormatter()
            f.locale = locale
            f.timeZone = TimeZone(identifier: "UTC")
            for list in [f.monthSymbols, f.shortMonthSymbols, f.standaloneMonthSymbols, f.shortStandaloneMonthSymbols] {
                months.formUnion((list ?? []).filter(Masks.nameable).flatMap(Masks.cases))
            }
            for list in [f.weekdaySymbols, f.shortWeekdaySymbols, f.standaloneWeekdaySymbols, f.shortStandaloneWeekdaySymbols] {
                days.formUnion((list ?? []).filter(Masks.nameable).flatMap(Masks.cases))
            }
            days.formUnion(Masks.spoken[String(code.prefix(2))] ?? [])
            // AM and PM (`a`), and the parts of the day a time is said with
            // (`B`): 下午, in the morning, nachmittags; on the side of the time
            // the language puts them.
            for (mark, formats) in [("a", ["a"]), ("B", ["B", "BBBB"])] {
                let order = DateFormatter.dateFormat(fromTemplate: "hmm" + mark, options: 0, locale: locale) ?? ""
                guard let at = order.firstIndex(of: Character(mark)),
                      let hour = order.firstIndex(where: { "hHkK".contains($0) }) else { continue }
                for format in formats {
                    f.dateFormat = format
                    for minute in stride(from: 0, to: 24 * 60, by: 30) {
                        let said = f.string(from: Date(timeIntervalSince1970: Double(minute * 60)))
                        guard !said.isEmpty, said.rangeOfCharacter(from: .decimalDigits) == nil else { continue }
                        if at < hour { before.formUnion(Masks.cases(said)) } else { after.formUnion(Masks.cases(said)) }
                    }
                }
            }
        }
        var rules: [(String, String)] = [
            ("\\d[\\d.,:\u{202F}\u{00A0}]*", "#"),
            (Masks.alternation(months), "‹month›"),
            (Masks.alternation(days), "‹day›"),
            ("#\\s?(?:\(Masks.alternation(after, bounded: false)))(?![\\p{L}])", "‹time›"),
        ]
        if !before.isEmpty {
            rules.append(("(?<![\\p{L}])(?:\(Masks.alternation(before, bounded: false)))\\s?#", "‹time›"))
        }
        rules += project.map { ($0.pattern, $0.token) }
        self.rules = try rules.map { pattern, token in
            do { return (try NSRegularExpression(pattern: pattern), token) }
            catch { throw Failure("shots.masks: \(pattern) isn't a pattern this can read") }
        }
    }

    /// A word as macOS writes it and, where it's written in small letters
    /// (lundi, mars), with a capital, as at the start of a label.
    static func cases(_ word: String) -> [String] {
        guard let first = word.first, first.isLowercase else { return [word] }
        return [word, first.uppercased() + word.dropFirst()]
    }

    /// A name worth masking on its own: not a number, and long enough not to
    /// be part of other words (three letters, or two in a script without spaces).
    static func nameable(_ word: String) -> Bool {
        word.rangeOfCharacter(from: .decimalDigits) == nil && word.count >= (unspaced(word) ? 2 : 3)
    }

    /// Written without spaces between words (Chinese, Japanese, Thai): a name
    /// can't be told from its neighbours by where a word ends.
    static func unspaced(_ word: String) -> Bool {
        word.range(of: "[\\p{Han}\\p{Hiragana}\\p{Katakana}\\p{Thai}\\p{Lao}\\p{Khmer}\\p{Myanmar}]",
                   options: .regularExpression) != nil
    }

    /// The words as one pattern, the longest first; a word in a spaced script
    /// only as a whole word.
    static func alternation(_ words: Set<String>, bounded: Bool = true) -> String {
        let sorted = words.sorted { $0.count != $1.count ? $0.count > $1.count : $0 < $1 }
        let spaced = sorted.filter { !unspaced($0) }.map(NSRegularExpression.escapedPattern(for:))
        let unspacedWords = sorted.filter(unspaced).map(NSRegularExpression.escapedPattern(for:))
        var parts: [String] = []
        if !spaced.isEmpty {
            let words = spaced.joined(separator: "|")
            parts.append(bounded ? "(?<![\\p{L}\\p{N}_])(?:\(words))(?![\\p{L}\\p{N}_])" : "(?:\(words))")
        }
        if !unspacedWords.isEmpty { parts.append("(?:\(unspacedWords.joined(separator: "|")))") }
        return parts.joined(separator: "|")
    }

    func apply(_ s: String) -> String {
        var s = s
        for (regex, token) in rules {
            s = regex.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s),
                                               withTemplate: NSRegularExpression.escapedTemplate(for: token))
        }
        return s.replacingOccurrences(of: "\n", with: " ")
    }
}

/// The masks in use: the project's languages and its own, once its manifest
/// is read; English alone before that.
nonisolated(unsafe) var masks = try! Masks(languages: ["en"])

func mask(_ s: String) -> String { masks.apply(s) }

/// `mask-test`: labels in several languages, and what each must read as.
enum MaskTests {
    struct Case { let languages: [String]; let project: [(pattern: String, token: String)]; let label: String; let reads: String }
    static let units = [(pattern: "#\\s?(bytes|[KMGT]?B/s|[KMGT]bps|bps|[KMGT]?B)(?![A-Za-z])", token: "# ‹unit›")]
    static let cases: [Case] = [
        Case(languages: ["en"], project: [], label: "Updated 5:51\u{202F}PM on Monday, March 3", reads: "Updated ‹time› on ‹day›, ‹month› #"),
        Case(languages: ["en"], project: [], label: "Sun 2 Sept, 9:05 am", reads: "‹day› # ‹month›, ‹time›"),
        Case(languages: ["en"], project: [], label: "Monitor the Marketing app, you may", reads: "Monitor the Marketing app, you may"),
        Case(languages: ["en"], project: [], label: "12.3 MB/s", reads: "# MB/s"),
        Case(languages: ["en"], project: units, label: "12.3 MB/s · 4 GB today", reads: "# ‹unit› · # ‹unit› today"),
        Case(languages: ["en", "zh-Hans"], project: [], label: "下午5:51 · 早上6:02", reads: "‹time› · ‹time›"),
        Case(languages: ["en", "zh-Hans"], project: [], label: "星期一 周三的流量 星期天", reads: "‹day› ‹day›的流量 ‹day›"),
        Case(languages: ["en", "zh-Hans"], project: [], label: "十一月 · 11月13日", reads: "‹month› · #月#日"),
        Case(languages: ["fr"], project: [], label: "Lundi 3 mars à 17:51", reads: "‹day› # ‹month› à #"),
        Case(languages: ["fr"], project: [], label: "Marché de nuit", reads: "Marché de nuit"),
        Case(languages: ["de"], project: [], label: "Montag, 3. März um 17:51", reads: "‹day›, # ‹month› um #"),
        Case(languages: ["de"], project: [], label: "So geht's: am Mo.", reads: "So geht's: am ‹day›"),
        Case(languages: ["ar"], project: [], label: "الاثنين ٣ مارس ٥:٥١ م", reads: "‹day› # ‹month› ‹time›"),
        Case(languages: ["ja"], project: [], label: "月曜日 午後5:51 · 1月", reads: "‹day› ‹time› · #月"),
        Case(languages: ["en"], project: [(pattern: "[$€£]#", token: "‹money›"), (pattern: "#%", token: "‹percent›")],
             label: "$12.50 · 80%", reads: "‹money› · ‹percent›"),
    ]

    static func run() throws -> [String] {
        try cases.compactMap { c in
            let got = try Masks(languages: c.languages, project: c.project).apply(c.label)
            return got == c.reads ? nil : "\(c.languages.joined(separator: ",")): \"\(c.label)\" reads \"\(got)\", not \"\(c.reads)\""
        }
    }
}

// MARK: - Running a tool

/// Runs a tool to its end: its exit status, and what it printed.
@discardableResult
func runTool(_ path: String, _ arguments: [String]) -> (status: Int32, output: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = arguments
    let out = Pipe()
    p.standardOutput = out
    p.standardError = out
    guard (try? p.run()) != nil else { return (-1, "couldn't run \(path)") }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, String(decoding: data, as: UTF8.self))
}

func writePNG(_ image: CGImage, to url: URL) throws {
    // A language's first pictures go in folders that don't exist yet.
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { throw Failure("can't write \(url.path)") }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { throw Failure("can't write \(url.path)") }
}

// MARK: - The page

struct Page {
    let url: URL
    var html: String
    /// From the page's folder back to the site's root, before each asset's
    /// path in its links: `../` for a language's page in a folder.
    let up: String

    init(site: URL, path: String = "index.html", up: String = "") throws {
        url = site.appendingPathComponent(path)
        html = try String(contentsOf: url, encoding: .utf8)
        self.up = up
    }

    func save() throws { try html.write(to: url, atomically: true, encoding: .utf8) }

    /// The whole tag containing `needle`.
    func tagRange(containing needle: String) -> Range<String.Index>? {
        guard let hit = html.range(of: needle),
              let start = html[..<hit.lowerBound].range(of: "<", options: .backwards),
              let end = html[hit.upperBound...].range(of: ">") else { return nil }
        return start.lowerBound..<end.upperBound
    }

    mutating func edit(tagContaining needle: String, _ change: (String) -> String) {
        guard let range = tagRange(containing: needle) else { return }
        html.replaceSubrange(range, with: change(String(html[range])))
    }

    static func set(_ attribute: String, _ value: String, in tag: String) -> String {
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: attribute))=\"[^\"]*\""
        return tag.range(of: pattern, options: .regularExpression) == nil ? tag
            : tag.replacingOccurrences(of: pattern, with: "\(attribute)=\"\(value)\"", options: .regularExpression)
    }

    /// `width` and `height` in pixels, and `data-w` and `data-h` in points
    /// where the tag has them.
    /// Every tag containing `needle`, last first so the ranges stay good.
    mutating func editAll(tagsContaining needle: String, _ change: (String) -> String) {
        var ranges: [Range<String.Index>] = []
        var from = html.startIndex
        while let hit = html.range(of: needle, range: from..<html.endIndex) {
            if let start = html[..<hit.lowerBound].range(of: "<", options: .backwards),
               let end = html[hit.upperBound...].range(of: ">") {
                ranges.append(start.lowerBound..<end.upperBound)
            }
            from = hit.upperBound
        }
        for range in ranges.reversed() { html.replaceSubrange(range, with: change(String(html[range]))) }
    }

    /// The picture's size, on every `<img>` that shows it: one picture can
    /// be in two sections.
    mutating func setSize(of file: String, pixels: CGSize) {
        editAll(tagsContaining: "\"\(up)\(file)") { tag in
            var tag = Page.set("width", "\(Int(pixels.width))", in: tag)
            tag = Page.set("height", "\(Int(pixels.height))", in: tag)
            tag = Page.set("data-w", "\(Int(pixels.width / 2))", in: tag)
            return Page.set("data-h", "\(Int(pixels.height / 2))", in: tag)
        }
    }

    /// An area's `--x` (from the window's centre), `--y`, `--w` and `--h`.
    mutating func place(_ area: Area, at r: CGRect, windowWidth: CGFloat) {
        let padX = area.pad?.first ?? 0, padY = area.pad?.last ?? 0
        let values = ["--x": r.minX - padX - windowWidth / 2, "--y": r.minY - padY,
                      "--w": r.width + 2 * padX, "--h": area.h ?? (r.height + 2 * padY)]
        edit(tagContaining: area.match) { tag in
            var tag = tag
            for (name, v) in values {
                tag = tag.replacingOccurrences(of: "\(name):-?[\\d.]+", with: "\(name):\(Int(v.rounded()))", options: .regularExpression)
            }
            return tag
        }
    }

    /// `?v=` and the first eight hex digits of each asset's contents, on every
    /// link to it, so a page never shows a picture the browser kept from an
    /// older version.
    mutating func stampAssets(site: URL) {
        let folder = NSRegularExpression.escapedPattern(for: config.media)
        let regex = try! NSRegularExpression(pattern: "(\(folder)/[A-Za-z0-9_./-]+\\.(?:png|jpg|jpeg|gif|webp|svg|mp4|webm))(\\?v=[0-9a-f]+)?")
        let ns = html as NSString
        var result = "", last = 0
        for m in regex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let path = ns.substring(with: m.range(at: 1))
            result += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            if let data = try? Data(contentsOf: site.appendingPathComponent(path)) {
                let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined().prefix(8)
                result += "\(path)?v=\(hash)"
            } else {
                result += ns.substring(with: m.range)
            }
            last = m.range.location + m.range.length
        }
        html = result + ns.substring(from: last)
    }
}

// MARK: - Coverage

/// Every image, GIF and video the pages use, each with the pages using it,
/// checked against the lists (NetworkMonitor#413). Reads files only: no app, no
/// Accessibility, so it runs in CI.
enum Coverage {
    static let media = "png|jpe?g|gif|webp|svg|mp4|webm|mov"

    /// The site's files a browser reads for media (NetworkMonitor#425): its pages, at the
    /// top and in folders (each language's, zh/index.html, NetworkMonitor#430), their
    /// stylesheets and their scripts. Not the folders that aren't the site:
    /// hidden ones (.github), shots/ (this tool's), and another checkout
    /// inside it (the app's, which the site's workflow puts in app/).
    static func siteFiles(_ site: URL) -> [String] {
        let fm = FileManager.default
        guard let walk = fm.enumerator(atPath: site.path) else { return [] }
        var files: [String] = []
        while let path = walk.nextObject() as? String {
            let name = (path as NSString).lastPathComponent
            if walk.fileAttributes?[.type] as? FileAttributeType == .typeDirectory {
                if name.hasPrefix(".") || path == "shots"
                    || fm.fileExists(atPath: site.appendingPathComponent(path).appendingPathComponent(".git").path) {
                    walk.skipDescendants()
                }
            } else if !name.hasPrefix("."),
                      ["html", "htm", "css", "js", "mjs"].contains((name as NSString).pathExtension.lowercased()) {
                files.append(path)
            }
        }
        return files.sorted()
    }

    /// The site's own assets: `assets/…`, as a relative link or on the site's
    /// own address (the social preview's `<meta>` tags), wherever it's
    /// written: an attribute, a `srcset`'s list, a stylesheet's `url(…)`, a
    /// string in a script that adds it. Another site's `/assets/` isn't ours.
    static func siteUses(_ site: URL) throws -> [String: Set<String>] {
        // The site's own address, without its scheme: `example.github.io/App/`.
        let own = config.siteURL.map { url -> String in
            let bare = url.replacingOccurrences(of: #"^[a-z]+://"#, with: "", options: .regularExpression)
            return "|" + NSRegularExpression.escapedPattern(for: bare.hasSuffix("/") ? bare : bare + "/")
        } ?? ""
        let regex = try NSRegularExpression(
            pattern: #"(?:^|["'`(=,\s]"# + own + #")(?:\.\./)*("# + NSRegularExpression.escapedPattern(for: config.media)
                + #"/[A-Za-z0-9_./@-]+\.(?:"# + media + #"))"#,
            options: [.caseInsensitive, .anchorsMatchLines])
        var uses: [String: Set<String>] = [:]
        // A page in a folder climbs out with ../; a script's paths are the
        // page's that runs it, so each is the site's assets/ either way.
        for file in siteFiles(site) {
            guard let text = try? String(contentsOf: site.appendingPathComponent(file), encoding: .utf8) else { continue }
            let ns = text as NSString
            for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                uses[ns.substring(with: m.range(at: 1)), default: []].insert(file)
            }
        }
        return uses
    }

    /// The README's, SECURITY's and the docs' Markdown pages: README.<code>.md
    /// for each language (NetworkMonitor#430), and every page under docs/, however deep
    /// (docs/<code>/, the design log's docs/design-overhaul, NetworkMonitor#437).
    static func repoPages(_ repo: URL) -> [String] {
        let fm = FileManager.default
        var pages = ["README.md", "SECURITY.md"]
        let files = (try? fm.contentsOfDirectory(atPath: repo.path)) ?? []
        pages += files.filter { $0.hasPrefix("README.") && $0.hasSuffix(".md") && $0 != "README.md" }.sorted()
        var docs: [String] = []
        if let walk = fm.enumerator(atPath: repo.appendingPathComponent("docs").path) {
            while let path = walk.nextObject() as? String {
                let name = (path as NSString).lastPathComponent
                if name.hasPrefix(".") {
                    walk.skipDescendants()
                } else if name.lowercased().hasSuffix(".md") {
                    docs.append("docs/" + path)
                }
            }
        }
        return pages + docs.sorted()
    }

    /// A Markdown page with its code blanked out, fenced and inline, which
    /// GitHub shows as text: an example there isn't a picture on the page.
    static func withoutCode(_ text: String) -> String {
        var fence: String?
        var lines: [String] = []
        for line in text.components(separatedBy: "\n") {
            // At any depth: a list item's code is indented with it.
            let trimmed = line.drop { $0 == " " || $0 == "\t" }
            let marker = String(trimmed.prefix { $0 == "`" || $0 == "~" })
            if let open = fence {
                if marker.first == open.first, marker.count >= open.count,
                   trimmed.dropFirst(marker.count).allSatisfy(\.isWhitespace) {
                    fence = nil
                }
                lines.append("")
            } else if marker.count >= 3, Set(marker).count == 1,
                      marker.first == "~" || !trimmed.dropFirst(marker.count).contains("`") {
                fence = marker
                lines.append("")
            } else {
                lines.append(line)
            }
        }
        let inline = try! NSRegularExpression(pattern: "(`+).*?\\1")
        let joined = lines.joined(separator: "\n")
        return inline.stringByReplacingMatches(in: joined, range: NSRange(location: 0, length: (joined as NSString).length),
                                               withTemplate: "")
    }

    /// The links to pictures in one Markdown page, as written: HTML's `src`,
    /// `poster` and `srcset` (a `<picture>`'s `<source>` too), and Markdown's
    /// images, inline `![alt](path)` or by reference, `![alt][ref]`,
    /// `![ref][]` or `![ref]`, with `[ref]: path` anywhere on the page.
    static func pictureLinks(_ markdown: String) throws -> [String] {
        let text = withoutCode(markdown)
        let ns = text as NSString
        let all = NSRange(location: 0, length: ns.length)
        func group(_ m: NSTextCheckingResult, _ i: Int) -> String? {
            m.range(at: i).location == NSNotFound ? nil : ns.substring(with: m.range(at: i))
        }
        var links: [String] = []
        let html = try NSRegularExpression(pattern: #"\b(src|poster|srcset)\s*=\s*["']([^"']+)["']"#, options: .caseInsensitive)
        for m in html.matches(in: text, range: all) {
            guard let attribute = group(m, 1), let value = group(m, 2) else { continue }
            if attribute.lowercased() == "srcset" {
                // `a.png 1x, a@2x.png 2x`: each candidate's address.
                links += value.components(separatedBy: ",").compactMap {
                    $0.split(whereSeparator: \.isWhitespace).first.map(String.init)
                }
            } else {
                links.append(value)
            }
        }
        let inline = try NSRegularExpression(pattern: #"!\[[^\]]*\]\(\s*<?([^)\s>]+)"#)
        links += inline.matches(in: text, range: all).compactMap { group($0, 1) }
        // References: labels match without regard to case or spacing, and
        // the first definition of one wins.
        func label(_ s: String) -> String {
            s.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
        var definitions: [String: String] = [:]
        let definition = try NSRegularExpression(pattern: #"^ {0,3}\[([^\]]+)\]:[ \t]*<?([^\s>]+)>?"#, options: .anchorsMatchLines)
        for m in definition.matches(in: text, range: all) {
            guard let name = group(m, 1), let link = group(m, 2), definitions[label(name)] == nil else { continue }
            definitions[label(name)] = link
        }
        let reference = try NSRegularExpression(pattern: #"!\[([^\]]*)\](?:\[([^\]]*)\])?(?![(\[])"#)
        for m in reference.matches(in: text, range: all) {
            let ref = group(m, 2).flatMap { $0.isEmpty ? nil : $0 } ?? group(m, 1) ?? ""
            if let link = definitions[label(ref)] { links.append(link) }
        }
        return links
    }

    /// The README's, SECURITY's and the docs' local media, as paths from the
    /// checkout's root.
    static func repoUses(_ repo: URL) throws -> [String: Set<String>] {
        let mediaRegex = try NSRegularExpression(pattern: #"\.(?:"# + media + #")$"#, options: .caseInsensitive)
        let root = repo.standardizedFileURL.path + "/"
        var uses: [String: Set<String>] = [:]
        for page in repoPages(repo) {
            guard let text = try? String(contentsOf: repo.appendingPathComponent(page), encoding: .utf8) else { continue }
            for written in try pictureLinks(text) {
                if written.contains("://") || written.hasPrefix("#") || written.hasPrefix("data:") { continue }
                let link = written.components(separatedBy: CharacterSet(charactersIn: "?#"))[0]
                guard mediaRegex.firstMatch(in: link, range: NSRange(location: 0, length: (link as NSString).length)) != nil
                else { continue }
                // Relative to the page, as GitHub reads it.
                let base = repo.appendingPathComponent(page).deletingLastPathComponent()
                let full = URL(fileURLWithPath: link, relativeTo: base).standardizedFileURL.path
                guard full.hasPrefix(root) else { continue }
                uses[String(full.dropFirst(root.count)), default: []].insert(page)
            }
        }
        return uses
    }

    /// What's wrong, one line each; empty when every asset is accounted for.
    /// The site's come first, fixed on `gh-pages`; from `onMain` on, the
    /// README's and the docs', fixed on `main` (NetworkMonitor#426). And what's known to be
    /// out of date, waiting on an issue (`stale`), which doesn't fail it.
    static func problems(manifest: Manifest, site: URL, repoAssets: RepoAssets?, repo: URL?) throws
        -> (problems: [String], onMain: Int, summary: String, stale: [String]) {
        var problems: [String] = [], stale: [String] = []
        let shotNames = Set(manifest.shots.map(\.name))
        // Each window's record, as the version it was taken from (NetworkMonitor#421): the
        // tree what's made by hand was last remade from, or the window's own.
        let trees = site.appendingPathComponent("shots/trees")
        let versions = Versions.read(trees)
        func recorded(_ name: String) -> String? {
            let made = "\(name).made.txt"
            return FileManager.default.fileExists(atPath: trees.appendingPathComponent(made).path) ? versions[made] : versions["\(name).txt"]
        }

        func checkList(_ list: [HandMade], root: URL, listName: String, uses: [String: Set<String>], taken: Set<String>) {
            var seen = Set<String>()
            for asset in list {
                let file = asset.file
                if !seen.insert(file).inserted { problems.append("\(file) is listed twice in \(listName)") }
                if taken.contains(file) { problems.append("\(file) is a shot's picture; take it out of \(listName)'s assets") }
                let shows = asset.shows ?? []
                if let how = asset.how, !HandMade.hows.contains(how) {
                    problems.append("\(file) in \(listName) says it's made \"\(how)\": that's one of "
                                    + HandMade.hows.sorted().joined(separator: ", "))
                }
                if asset.copy == nil, shows.isEmpty == (asset.none == nil) {
                    problems.append("\(file) in \(listName) needs either `shows` (the windows it shows) or `none` (why it shows none), not both")
                }
                for name in shows where !shotNames.contains(name) {
                    problems.append("\(file) in \(listName) shows \"\(name)\", which isn't a shot in shots/shots.json"
                                    + (listName == repoAssetsPath ? renamedOnSite : ""))
                }
                // Made from a window older than its record: out of date on
                // the day it was listed, or since a remake of its window (NetworkMonitor#421).
                if !shows.isEmpty, !(asset.made.map(Versions.valid) ?? false) {
                    problems.append("\(file) in \(listName) needs `made`: the app version it was made from, such as \"1.28.1\"")
                } else if !shows.isEmpty, let made = asset.made {
                    let newer = shows.compactMap { name in recorded(name).flatMap { Versions.older(made, than: $0) ? "\(name) (\($0))" : nil } }
                    if newer.isEmpty, let issue = asset.stale {
                        problems.append("\(file) in \(listName) is as new as the windows it shows; take out `stale` (\(issue))")
                    } else if !newer.isEmpty, let issue = asset.stale {
                        stale.append("\(file), made from \(made), waits on \(issue): \(newer.joined(separator: ", ")) changed since")
                    } else if !newer.isEmpty {
                        problems.append("\(file) in \(listName) was made from \(made), but these windows' records are newer: "
                                        + newer.joined(separator: ", ") + ". Remake it and set `made`, or set `stale` to the issue its remake waits on")
                    }
                }
                if !FileManager.default.fileExists(atPath: root.appendingPathComponent(file).path) {
                    problems.append("\(file) is listed in \(listName) but doesn't exist")
                } else if uses[file] == nil {
                    problems.append("\(file) is listed in \(listName) but no page uses it; take it out")
                }
            }
            for (file, pages) in uses.sorted(by: { $0.key < $1.key }) where !taken.contains(file) && !seen.contains(file) {
                problems.append("\(file) (\(pages.sorted().joined(separator: ", "))) isn't listed. Add it to \(listName)'s "
                                + "`assets` with the shots whose windows it `shows`, or `none` and why it shows none")
            }
        }

        // The site: each asset is a shot's picture, a flag, or listed. Without
        // a site, the README's and the docs' are, against the one list (product-kit#8).
        let inRepo = manifestInRepo && repo != nil
        var siteUses = try siteUses(site)
        if inRepo, let repo { siteUses.merge(try repoUses(repo)) { $0.union($1) } }
        // Each shot's picture, and its copy in each language (NetworkMonitor#431).
        var pictures: [(file: String, shot: String)] = manifest.shots.compactMap { s in s.file.map { ($0, s.name) } }
        var translated: [(file: String, shot: String)] = []
        for language in manifest.languages ?? [] {
            translated += manifest.shots.compactMap { s in s.file.map { (language.file($0), "\(s.name) (\(language.code))") } }
        }
        let shotFiles = Set((pictures + translated).map(\.file))
        // A language's copy is needed once its page shows it: until the first
        // run takes it, the page can show the English one.
        pictures += translated.filter { siteUses[$0.file] != nil }
        for (file, shot) in pictures where !FileManager.default.fileExists(atPath: site.appendingPathComponent(file).path) {
            problems.append("\(file), \(shot)'s picture, doesn't exist")
        }
        let flagged = manifest.shots.flatMap { shot in (shot.flags ?? []).map { HandMade(file: $0, shows: [shot.name]) } }
        checkList((manifest.assets ?? []) + flagged.filter { f in !(manifest.assets ?? []).contains { $0.file == f.file } },
                  root: site, listName: "shots/shots.json", uses: siteUses, taken: shotFiles)
        var summary = inRepo ? "\(siteUses.count) assets in the README and docs" : "\(siteUses.count) assets on the site"

        // The README and the docs.
        let onMain = inRepo ? 0 : problems.count
        if let repo, !inRepo {
            let uses = try repoUses(repo)
            // A copy of a shot's picture is listed once, in English; each
            // language's copy of it comes with it (NetworkMonitor#434).
            var copies = Set<String>()
            for asset in repoAssets?.assets ?? [] {
                guard let name = asset.copy else { continue }
                if manifest.shots.first(where: { $0.name == name })?.file == nil {
                    problems.append("\(asset.file) in \(repoAssetsPath) is a copy of \"\(name)\", which isn't a shot with a picture in shots/shots.json"
                                    + renamedOnSite)
                }
                for language in manifest.languages ?? [] {
                    let file = repoFile(asset.file, in: language)
                    copies.insert(file)
                    if uses[file] != nil, !FileManager.default.fileExists(atPath: repo.appendingPathComponent(file).path) {
                        problems.append("\(file), the \(language.code) copy of \(asset.file), doesn't exist; `update` makes it")
                    }
                }
            }
            checkList(repoAssets?.assets ?? [], root: repo, listName: repoListName(repo, manifest), uses: uses, taken: copies)
            summary += " and \(uses.count) in the README and docs"
        }
        return (problems, onMain, summary, stale)
    }

    /// A shot `main` names, gone from `gh-pages`: the usual cause is a change
    /// there, so say where to follow it (NetworkMonitor#426).
    static var renamedOnSite: String {
        " on \(config.siteBranch). If a change there renamed or removed it, change \(repoAssetsPath) on \(config.repoBranch) to match"
    }

    /// Each branch's problems under its name, so a failure says which branch to
    /// fix. `checking` is the branch the check runs for, from GitHub's
    /// variables; where it's the other one, a note says the problems come from
    /// across the branches (NetworkMonitor#426).
    static func report(_ problems: [String], onMain: Int, checking: String?, head: String?) -> [String] {
        let groups: [(branch: String, what: String, problems: ArraySlice<String>)] = [
            (config.siteBranch, "the site's pages and shots/shots.json", problems[..<onMain]),
            (config.repoBranch, "the README, the docs and \(manifestInRepo ? "shots/shots.json" : repoAssetsPath)", problems[onMain...]),
        ]
        var lines: [String] = []
        for group in groups where !group.problems.isEmpty {
            lines.append("On \(group.branch) (\(group.what)), fixed in a pull request into \(group.branch):")
            if let checking, checking != group.branch {
                let this = head == nil ? "this push" : "this pull request"
                let pair = group.branch == config.siteBranch
                    ? "name that branch \(head ?? "<main's branch>")-site"
                    : "name this branch after that one, with -site"
                lines.append("  Not in \(this)'s files: \(group.branch) changed, or \(this) changes what \(group.branch) has to match. "
                             + "Fix them in a pull request into \(group.branch). To land both at once, \(pair), and each is "
                             + "checked against the other.")
            }
            lines += group.problems.map { "  " + $0 }
        }
        return lines
    }
}

// MARK: - Coverage tests

/// Where the check looks for media, each place a case (NetworkMonitor#425): made-up pages in
/// a folder of their own, scanned like the real ones. `make test` runs them,
/// with `site-shots coverage-test`, so a page that hides a picture from the
/// check can't come back unnoticed.
enum CoverageTests {
    struct Case {
        var name: String
        /// Files, by path, and what's in them.
        var files: [String: String]
        /// What the scan should find: each asset, and the pages using it.
        var expect: [String: Set<String>]
    }

    static let site: [Case] = [
        Case(name: "a page at the top", files: ["index.html": #"<img src="assets/top.png">"#],
             expect: ["assets/top.png": ["index.html"]]),
        Case(name: "a language's page in a folder", files: ["zh/index.html": #"<img src="../assets/zh-Hans/a.png">"#],
             expect: ["assets/zh-Hans/a.png": ["zh/index.html"]]),
        Case(name: "pages deeper in folders, not only index.html",
             files: ["guide/setup/index.html": #"<img src="../../assets/deep.png">"#,
                     "guide/faq.html": #"<video poster="../assets/faq.jpg" src="../assets/faq.mp4">"#],
             expect: ["assets/deep.png": ["guide/setup/index.html"],
                      "assets/faq.jpg": ["guide/faq.html"], "assets/faq.mp4": ["guide/faq.html"]]),
        Case(name: "srcset, and a picture's sources",
             files: ["index.html": """
                 <img srcset="assets/s.png 1x, assets/s@2x.png 2x">
                 <picture><source srcset="assets/p.webp" type="image/webp"><img src="assets/p.png"></picture>
                 """],
             expect: ["assets/s.png": ["index.html"], "assets/s@2x.png": ["index.html"],
                      "assets/p.webp": ["index.html"], "assets/p.png": ["index.html"]]),
        Case(name: "stylesheets, inline and separate",
             files: ["index.html": #"<style>.hero { background: url(assets/inline.png) }</style>"#,
                     "style.css": #".a { background-image: url("assets/top.jpg") }"#,
                     "css/site.css": ".b { background: url('../assets/nested.webp') }"],
             expect: ["assets/inline.png": ["index.html"], "assets/top.jpg": ["style.css"],
                      "assets/nested.webp": ["css/site.css"]]),
        Case(name: "images that scripts add, inline and separate",
             files: ["index.html": "<script>video.poster = 'assets/inline.gif'</script>",
                     "app.js": "img.src = \"assets/script.png\"; el.style.backgroundImage = `url(assets/tick.svg)`",
                     "js/more.mjs": "const clip = `assets/clip.mp4`"],
             expect: ["assets/inline.gif": ["index.html"], "assets/script.png": ["app.js"],
                      "assets/tick.svg": ["app.js"], "assets/clip.mp4": ["js/more.mjs"]]),
        Case(name: "the site's own address, in a social preview",
             files: ["index.html": #"<meta property="og:image" content="https://example.github.io/App/assets/card.png?v=1">"#],
             expect: ["assets/card.png": ["index.html"]]),
        Case(name: "not the site: other sites, this tool's folder, hidden folders, another checkout",
             files: ["index.html": #"<img src="https://example.com/assets/theirs.png"><img src="/assets/root.png">"#,
                     "shots/notes.html": #"<img src="assets/tool.png">"#,
                     ".github/page.html": #"<img src="assets/hidden.png">"#,
                     "app/.git/HEAD": "ref: refs/heads/main",
                     "app/Resources/Social/card.html": #"<img src="assets/app.png">"#],
             expect: [:]),
    ]

    static let repo: [Case] = [
        Case(name: "an inline Markdown image and an <img>",
             files: ["README.md": #"![Demo](Resources/README/demo.gif) <img src="Resources/README/logo.png" width="64">"#],
             expect: ["Resources/README/demo.gif": ["README.md"], "Resources/README/logo.png": ["README.md"]]),
        Case(name: "srcset, and a picture's sources",
             files: ["README.md": """
                 <img srcset="Resources/README/s.png 1x, Resources/README/s@2x.png 2x" src="Resources/README/s.png">
                 <picture>
                   <source media="(prefers-color-scheme: dark)" srcset="Resources/README/dark.png">
                   <img src="Resources/README/light.png">
                 </picture>
                 """],
             expect: ["Resources/README/s.png": ["README.md"], "Resources/README/s@2x.png": ["README.md"],
                      "Resources/README/dark.png": ["README.md"], "Resources/README/light.png": ["README.md"]]),
        Case(name: "reference-style images: full, collapsed and shortcut",
             files: ["README.md": """
                 ![The popover][pop] and ![Speed test][] and ![diagram].
                 A link isn't a picture: [the logo][logo]. Nor is an unused definition.

                 [pop]: Resources/README/popover.png "The popover"
                 [speed TEST]: <Resources/README/speed-test.png>
                 [Diagram]: docs/diagram.svg
                 [logo]: Resources/README/logo.png
                 [unused]: Resources/README/unused.png
                 """],
             expect: ["Resources/README/popover.png": ["README.md"], "Resources/README/speed-test.png": ["README.md"],
                      "docs/diagram.svg": ["README.md"]]),
        Case(name: "the docs' pages in folders, however deep, in every language",
             files: ["docs/guide.md": "![a](../Resources/README/a.png)",
                     "docs/design/notes/LOG.md": "![b](before/b.png)",
                     "docs/zh-Hans/guide.md": "![a](../../Resources/README/zh-Hans/a.png)",
                     "docs/zh-Hans/more/page.md": #"<img src="../../../Resources/README/zh-Hans/c.png">"#,
                     "README.zh-Hans.md": "![d](Resources/README/zh-Hans/d.png)"],
             expect: ["Resources/README/a.png": ["docs/guide.md"], "docs/design/notes/before/b.png": ["docs/design/notes/LOG.md"],
                      "Resources/README/zh-Hans/a.png": ["docs/zh-Hans/guide.md"],
                      "Resources/README/zh-Hans/c.png": ["docs/zh-Hans/more/page.md"],
                      "Resources/README/zh-Hans/d.png": ["README.zh-Hans.md"]]),
        Case(name: "not a picture on the page: code, other sites, outside the checkout",
             files: ["docs/development.md": """
                 Write `![alt](Resources/README/inline-code.png)` for one.

                 ```html
                 <img src="Resources/README/fenced.png">
                 ```

                 1. In a list:
                     ~~~
                     ![x](Resources/README/indented-fence.png)
                     ~~~

                 ![remote](https://example.com/x.png) ![outside](../../elsewhere.png)
                 """],
             expect: [:]),
    ]

    /// A change on one branch that fails the other's check says which branch
    /// to fix, and that the problem came from there (NetworkMonitor#426). Each case is the
    /// branch the check runs for, the pull request's branch, and what each
    /// group must say, or must not.
    static let branches: [(name: String, checking: String?, head: String?, site: [String], main: [String], notSite: [String], notMain: [String])] = [
        ("a pull request into main", "main", "scanner-425",
         ["Not in this pull request's files: gh-pages changed", "name that branch scanner-425-site"], [],
         [], ["Not in this"]),
        ("a pull request into gh-pages", "gh-pages", "rename-12-site",
         [], ["Not in this pull request's files: main changed", "name this branch after that one, with -site"],
         ["Not in this"], []),
        ("a push to main", "main", nil, ["Not in this push's files"], [], [], ["Not in this"]),
        ("this Mac", nil, nil, [], [], ["Not in this"], ["Not in this"]),
    ]

    /// gh-pages renamed two shots main's list names, and added a picture it
    /// didn't list: what each branch's check says.
    static func runBranches() throws -> [String] {
        var failures: [String] = []
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("coverage-test-" + UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let site = root.appendingPathComponent("site"), repo = root.appendingPathComponent("app")
        for (path, text) in [
            "site/index.html": #"<img src="assets/popover.png"><img src="assets/extra.png">"#,
            "site/assets/popover.png": "", "site/assets/extra.png": "",
            "app/README.md": #"![Demo](Resources/README/demo.gif) ![Speed](Resources/README/speed.png)"#,
            "app/Resources/README/demo.gif": "", "app/Resources/README/speed.png": "",
        ] {
            let file = root.appendingPathComponent(path)
            try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: file, atomically: true, encoding: .utf8)
        }
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data("""
            {"app": "/Applications/Example.app", "bundle": "x",
             "shots": [{"name": "popover", "file": "assets/popover.png", "open": [], "window": "x"}]}
            """.utf8))
        let repoAssets = try JSONDecoder().decode(RepoAssets.self, from: Data("""
            {"assets": [{"file": "Resources/README/demo.gif", "shows": ["popover-subprocesses"], "made": "1.28.1"},
                        {"file": "Resources/README/speed.png", "copy": "speed-test-result"}]}
            """.utf8))
        let found = try Coverage.problems(manifest: manifest, site: site, repoAssets: repoAssets, repo: repo)
        let renamed = "in shots/shots.json on gh-pages. If a change there renamed or removed it, "
            + "change \(repoAssetsPath) on main to match"
        if !(found.problems[..<found.onMain].count == 1 && found.problems[0].hasPrefix("assets/extra.png (index.html) isn't listed")) {
            failures.append("branches: gh-pages' problems are \(found.problems[..<found.onMain]); expected assets/extra.png isn't listed")
        }
        if !(found.problems[found.onMain...].count == 2 && found.problems[found.onMain...].allSatisfy { $0.contains(renamed) }) {
            failures.append("branches: main's problems are \(found.problems[found.onMain...]); expected two saying \"\(renamed)\"")
        }
        for test in branches {
            let lines = Coverage.report(found.problems, onMain: found.onMain, checking: test.checking, head: test.head)
            guard let siteAt = lines.firstIndex(where: { $0.hasPrefix("On gh-pages ") }),
                  let mainAt = lines.firstIndex(where: { $0.hasPrefix("On main ") }), siteAt < mainAt else {
                failures.append("branches, \(test.name): no group for each branch, gh-pages first: \(lines)")
                continue
            }
            let groups = [("gh-pages", lines[siteAt..<mainAt].joined(separator: "\n"), test.site, test.notSite),
                          ("main", lines[mainAt...].joined(separator: "\n"), test.main, test.notMain)]
            for (branch, text, says, never) in groups {
                for line in says where !text.contains(line) {
                    failures.append("branches, \(test.name): \(branch)'s group doesn't say \"\(line)\": \(text)")
                }
                for line in never where text.contains(line) {
                    failures.append("branches, \(test.name): \(branch)'s group says \"\(line)\": \(text)")
                }
            }
        }
        return failures
    }

    /// What failed, one line each.
    static func run() throws -> [String] {
        // The config these cases are written for, whatever the project's.
        config = Config()
        config.siteURL = "https://example.github.io/App/"
        config.repoAssets = "Resources/README/assets.json"
        var failures = try runBranches()
        let fm = FileManager.default
        for (kind, cases) in [("site", site), ("README and docs", repo)] {
            for test in cases {
                let root = fm.temporaryDirectory.appendingPathComponent("coverage-test-" + UUID().uuidString)
                defer { try? fm.removeItem(at: root) }
                for (path, text) in test.files {
                    let file = root.appendingPathComponent(path)
                    try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try text.write(to: file, atomically: true, encoding: .utf8)
                }
                let found = kind == "site" ? try Coverage.siteUses(root) : try Coverage.repoUses(root)
                if found != test.expect {
                    func show(_ u: [String: Set<String>]) -> String {
                        u.isEmpty ? "nothing" : u.sorted { $0.key < $1.key }
                            .map { "\($0.key) (\($0.value.sorted().joined(separator: ", ")))" }.joined(separator: ", ")
                    }
                    failures.append("\(kind), \(test.name): found \(show(found)); expected \(show(test.expect))")
                }
            }
        }
        return failures
    }
}

// MARK: - Running

struct Failure: Error, CustomStringConvertible {
    let description: String
    init(_ d: String) { description = d }
}

func diff(_ old: [String], _ new: [String]) -> [String] {
    let o = Set(old), n = Set(new)
    return old.filter { !n.contains($0) }.map { "  - " + $0.trimmingCharacters(in: .whitespaces) }
        + new.filter { !o.contains($0) }.map { "  + " + $0.trimmingCharacters(in: .whitespaces) }
}

// MARK: - Alt text, as a packet (product-kit#39)

/// For each picture: what changed in its window (its recorded tree, since a commit) and its
/// alt text wherever it's shown, in every language: the one packet a session needs to rewrite
/// the alt text after a retake, rather than every page.
enum AltPacket {
    static func run(names: Set<String>, manifest: Manifest, site: URL, repo: URL, since: String?) -> Int32 {
        let shots = manifest.shots.filter { $0.file != nil && (names.isEmpty || names.contains($0.name)) }
        if shots.isEmpty {
            print("alt: no shot with a picture" + (names.isEmpty ? "" : " named \(names.sorted().joined(separator: ", "))"))
            return 2
        }
        // Every page that could show a picture, with its text.
        var pages: [(path: String, text: String, markdown: Bool)] = []
        for file in Coverage.siteFiles(site) where file.hasSuffix(".html") || file.hasSuffix(".htm") {
            if let text = try? String(contentsOf: site.appendingPathComponent(file), encoding: .utf8) { pages.append((file, text, false)) }
        }
        let markdownRoot = manifestInRepo ? site : repo
        for file in Coverage.repoPages(markdownRoot) {
            if let text = try? String(contentsOf: markdownRoot.appendingPathComponent(file), encoding: .utf8) { pages.append((file, text, true)) }
        }
        let img = try! NSRegularExpression(pattern: #"<img\b[^>]*>"#, options: [.caseInsensitive])
        let alt = try! NSRegularExpression(pattern: #"\balt\s*=\s*"([^"]*)""#, options: [.caseInsensitive])
        let md = try! NSRegularExpression(pattern: #"!\[([^\]]*)\]\(\s*<?([^)\s>]+)"#)

        func alts(of file: String) -> [String] {
            // The picture itself, from any page's folder: `../assets/x.png`, `assets/x.png?v=…`.
            let path = try! NSRegularExpression(pattern: #"\b(?:src|srcset)\s*=\s*["'](?:\.\./)*"#
                                                + NSRegularExpression.escapedPattern(for: file) + #"(?:["'?#\s])"#)
            var found: [String] = []
            for page in pages {
                let ns = page.text as NSString
                for m in img.matches(in: page.text, range: NSRange(location: 0, length: ns.length)) {
                    let tag = ns.substring(with: m.range)
                    guard path.firstMatch(in: tag, range: NSRange(location: 0, length: (tag as NSString).length)) != nil else { continue }
                    let tns = tag as NSString
                    let said = alt.firstMatch(in: tag, range: NSRange(location: 0, length: tns.length)).map { tns.substring(with: $0.range(at: 1)) }
                    found.append("\(page.path): \"\(said ?? "")\"" + (said == nil ? " (no alt text)" : ""))
                }
                if page.markdown {
                    for m in md.matches(in: page.text, range: NSRange(location: 0, length: ns.length)) {
                        let linked = ns.substring(with: m.range(at: 2)).replacingOccurrences(of: #"^(\./|\.\./)+"#, with: "", options: .regularExpression)
                        guard linked == file || linked.hasPrefix(file + "?") else { continue }
                        found.append("\(page.path): \"\(ns.substring(with: m.range(at: 1)))\"")
                    }
                }
            }
            var seen = Set<String>()
            return found.filter { seen.insert($0).inserted }
        }

        for shot in shots {
            guard let file = shot.file else { continue }
            print("\(shot.name) (\(file)):")
            if let since {
                let tree = "shots/trees/\(shot.name).txt"
                let diffed = runTool("/usr/bin/git", ["-C", site.path, "diff", "--unified=0", since, "--", tree])
                let lines = diffed.output.split(separator: "\n").filter { ($0.hasPrefix("+") || $0.hasPrefix("-")) && !$0.hasPrefix("+++") && !$0.hasPrefix("---") }
                print(lines.isEmpty ? "  what changed: nothing in its tree since \(since)"
                                    : "  what changed since \(since):\n" + lines.prefix(30).map { "    " + $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n"))
            }
            var files = [file]
            for language in manifest.languages ?? [] { files.append(language.file(file)) }
            let said = files.flatMap(alts(of:))
            print(said.isEmpty ? "  alt text: no page shows it" : "  alt text:\n" + said.map { "    " + $0 }.joined(separator: "\n"))
        }
        print("Rewrite each alt text that names what changed, in every language: the interface, never its numbers.")
        return 0
    }
}
