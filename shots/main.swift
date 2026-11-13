// shots-kit, the commands (product-kit#35). The files are one program: `shots-kit` builds
// them together, and `shots-kit vendor` writes them into one file for a project's CI.

import AppKit
import AVFoundation
import ApplicationServices
import CryptoKit
import ScreenCaptureKit

@main
struct ShotsKit {
    static func main() async {
        _ = NSApplication.shared   // ScreenCaptureKit needs a connection to the window server
        // Line by line into a log too, so a run in the background says what it waits for.
        setvbuf(stdout, nil, _IOLBF, 0)
        var args = Array(CommandLine.arguments.dropFirst())
        if args.first == "version" { print(shotsKitVersion); exit(0) }
        // The project's checkout, for its config and the README's and the
        // docs' assets: this one.
        var repo = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        if let i = args.firstIndex(of: "--repo"), i + 1 < args.count {
            repo = URL(fileURLWithPath: args[i + 1]); args.removeSubrange(i...(i + 1))
        }
        repoRoot = repo
        config = Config.load(repo: repo)
        // The site's checkout: `--site`, or the config's, from the main checkout.
        var givenSite: URL?
        if let i = args.firstIndex(of: "--site"), i + 1 < args.count {
            givenSite = URL(fileURLWithPath: args[i + 1]); args.removeSubrange(i...(i + 1))
        } else if let path = config.site {
            let common = runTool("/usr/bin/git", ["-C", repo.path, "rev-parse", "--path-format=absolute", "--git-common-dir"])
            let main = common.status == 0
                ? URL(fileURLWithPath: common.output.trimmingCharacters(in: .whitespacesAndNewlines)).deletingLastPathComponent()
                : repo
            givenSite = URL(fileURLWithPath: path, relativeTo: main).standardizedFileURL
        }
        // Another copy of the app than the manifest's, such as a development
        // build of a version not yet released.
        var app: String?
        if let i = args.firstIndex(of: "--app"), i + 1 < args.count {
            app = args[i + 1]; args.removeSubrange(i...(i + 1))
        }
        // One language only: `en`, or a language's code (NetworkMonitor#431). All of them otherwise.
        var only: String?
        // A check compares looks too (NetworkMonitor#423), which needs each window in
        // front and active: only while the Mac is idle (NetworkMonitor#475), so a look it
        // can't take is reported as not taken (NetworkMonitor#521).
        if let i = args.firstIndex(of: "--look") { compareLooks = true; args.remove(at: i) }
        if let i = args.firstIndex(of: "--wait-away"), i + 1 < args.count {
            guard let minutes = Double(args[i + 1]), minutes >= 0, minutes <= 240 else {
                print("--wait-away takes minutes, at most 240")
                exit(2)
            }
            waitAway = minutes; args.removeSubrange(i...(i + 1))
        }
        if let i = args.firstIndex(of: "--language"), i + 1 < args.count {
            only = args[i + 1]; args.removeSubrange(i...(i + 1))
        }
        // In a throwaway VM, or on this Mac's screen (product-kit#10): the
        // config's `vm.default` otherwise.
        var inVM: Bool?
        if let i = args.firstIndex(of: "--vm") { inVM = true; args.remove(at: i) }
        if let i = args.firstIndex(of: "--here") { inVM = false; args.remove(at: i) }
        // What the masks make of text, files only (product-kit#32): `mask` reads
        // lines and prints each as a tree would show it, with the project's
        // languages and masks; `mask-test` runs the made-up cases.
        if args.first == "mask-test" {
            do {
                let failures = try MaskTests.run()
                print(failures.isEmpty ? "mask-test: \(MaskTests.cases.count) cases passed"
                      : "mask-test: \(failures.count) of \(MaskTests.cases.count) cases failed:\n" + failures.map { "  " + $0 }.joined(separator: "\n"))
                exit(failures.isEmpty ? 0 : 1)
            } catch {
                print("mask-test: \(error)")
                exit(2)
            }
        }
        if args.first == "mask" {
            do {
                let site = givenSite ?? repo
                let listed = (try? JSONDecoder().decode(Manifest.self, from: Data(contentsOf: site.appendingPathComponent("shots/shots.json"))))?
                    .languages?.map(\.code) ?? []
                masks = try Masks(languages: ["en"] + config.languages + listed, project: config.masks)
            } catch {
                print("mask: \(error)")
                exit(2)
            }
            while let line = readLine(strippingNewline: true) { print(mask(line)) }
            exit(0)
        }
        // A video of a shot (product-kit#65): `video <shot> --out <file from the site> --seconds N`.
        var videoArgs: [String] = []
        var videoOut: String?, videoSeconds = 8.0
        if let i = args.firstIndex(of: "--out"), i + 1 < args.count {
            videoOut = args[i + 1]; videoArgs += ["--out", args[i + 1]]; args.removeSubrange(i...(i + 1))
        }
        if let i = args.firstIndex(of: "--seconds"), i + 1 < args.count {
            videoSeconds = Double(args[i + 1]) ?? 8; videoArgs += ["--seconds", args[i + 1]]; args.removeSubrange(i...(i + 1))
        }
        if args.first == "poster" {
            guard args.count >= 3 else { print("usage: shots-kit poster <video> <image> [--at SECONDS]"); exit(2) }
            let at = args.firstIndex(of: "--at").flatMap { $0 + 1 < args.count ? Double(args[$0 + 1]) : nil } ?? 0.5
            do {
                try await poster(of: URL(fileURLWithPath: args[1]), at: at, to: URL(fileURLWithPath: args[2]))
                print("poster: \(args[2])")
                exit(0)
            } catch {
                print("poster: \(error)")
                exit(2)
            }
        }
        var altSince: String?
        if let i = args.firstIndex(of: "--since"), i + 1 < args.count {
            altSince = args[i + 1]; args.removeSubrange(i...(i + 1))
        }
        guard let command = args.first, ["check", "update", "tree", "audit", "coverage", "coverage-test", "readme", "record", "alt", "video"].contains(command) else {
            print("usage: shots-kit check [--look]|update|audit [names…]|tree <name>|record <names…>|coverage|coverage-test|mask|mask-test|alt [names…] [--since REF]|readme [--site DIR] [--repo DIR] [--app APP] [--language CODE] [--vm|--here] [--wait-away MINUTES]|version")
            exit(2)
        }
        // No site: the manifest is the project's own (product-kit#8).
        if givenSite == nil, command != "coverage-test" { manifestInRepo = true }
        let site = givenSite ?? repo
        let names = Set(args.dropFirst())
        if command == "record", names.isEmpty {
            print("record: name the windows whose marks changed; recording every tree would hide a real change")
            exit(2)
        }
        // With the manifest in the repo, it lists the README's assets itself.
        let repoAssets = manifestInRepo ? nil
            : try? JSONDecoder().decode(RepoAssets.self, from: Data(contentsOf: repo.appendingPathComponent(repoAssetsPath)))

        // Made-up pages only: where `coverage` looks for media (NetworkMonitor#425).
        if command == "coverage-test" {
            do {
                let failures = try CoverageTests.run()
                let count = CoverageTests.site.count + CoverageTests.repo.count + CoverageTests.branches.count
                if failures.isEmpty {
                    print("coverage-test: \(count) cases passed")
                    exit(0)
                }
                print("coverage-test: \(failures.count) of \(count) cases failed:")
                failures.forEach { print("  " + $0) }
                exit(1)
            } catch {
                print("coverage-test: \(error)")
                exit(2)
            }
        }
        // Files only, so first, before anything that needs the app.
        if command == "coverage" {
            do {
                let manifest = try loadManifest(site)
                if !manifestInRepo, repoAssets == nil, FileManager.default.fileExists(atPath: repo.appendingPathComponent(repoAssetsPath).path) {
                    throw Failure("\(repoAssetsPath) doesn't read as a list of assets")
                }
                let found = try Coverage.problems(manifest: manifest, site: site, repoAssets: RepoAssets.of(repoAssets, manifest), repo: repo)
                if found.problems.isEmpty {
                    print("coverage: \(found.summary), all accounted for")
                } else {
                    print("coverage: every image, GIF and video a page uses must be listed, so a change to the window it shows can't leave it stale:")
                    // The branch a pull request goes into, or a push went to, on GitHub.
                    let env = ProcessInfo.processInfo.environment
                    let checking = [env["GITHUB_BASE_REF"], env["GITHUB_REF_NAME"]]
                        .compactMap { $0 }.first { !$0.isEmpty }.flatMap { [config.repoBranch, config.siteBranch].contains($0) ? $0 : nil }
                    let head = env["GITHUB_HEAD_REF"].flatMap { $0.isEmpty ? nil : $0 }
                    Coverage.report(found.problems, onMain: found.onMain, checking: checking, head: head).forEach { print($0) }
                }
                if !found.stale.isEmpty {
                    print("Out of date, each waiting on its issue:")
                    found.stale.forEach { print("  " + $0) }
                }
                exit(found.problems.isEmpty ? 0 : 1)
            } catch {
                print("coverage: \(error)")
                exit(2)
            }
        }
        // Files only: each picture's alt text and what changed in its window (product-kit#39).
        if command == "alt" {
            do {
                exit(AltPacket.run(names: names, manifest: try loadManifest(site), site: site, repo: repo, since: altSince))
            } catch {
                print("alt: \(error)")
                exit(2)
            }
        }
        // Files only too: the README's copies of the site's pictures.
        if command == "readme" {
            do {
                let manifest = try loadManifest(site)
                let languages: [Language?] = [nil] + (manifest.languages ?? []).map { $0 }
                var copied: [String] = []
                for language in languages where only == nil || only == (language?.code ?? "en") {
                    copied += try copyToRepo(manifest: manifest, site: site, repo: repo, repoAssets: RepoAssets.of(repoAssets, manifest),
                                             language: language)
                }
                print(copied.isEmpty ? "readme: the README's pictures are the site's already"
                                     : "readme: copied the site's pictures to " + copied.joined(separator: ", "))
                exit(0)
            } catch {
                print("readme: \(error)")
                exit(2)
            }
        }
        // Drawn by the project: no app, no screen, no lanes (product-kit#8).
        if let manifest = try? loadManifest(site), let render = manifest.render {
            exit(Rendered.run(command, names: names, manifest: manifest, render: render, site: site, repo: repo))
        }
        // A driver of the project's choosing: the screens it opens, the core does the rest (product-kit#35).
        if let manifest = try? loadManifest(site), let driver = manifest.driver {
            exit(Commanded.run(command, names: names, manifest: manifest, driver: driver, site: site, repo: repo,
                               repoAssets: RepoAssets.of(repoAssets, manifest), only: only))
        }
        // In a VM: the app, the site and the project go in, what changed comes back.
        if InVM.commands.contains(command), !InVM.inside, inVM ?? config.vm.byDefault {
            do {
                let manifest = try loadManifest(site)
                exit(InVM.run(args + (compareLooks ? ["--look"] : []) + (only.map { ["--language", $0] } ?? []) + videoArgs,
                              manifest: manifest, site: site, repo: repo, app: app))
            } catch {
                print("shots-kit: \(error)")
                exit(2)
            }
        }
        // One run at a time: each quits and relaunches the app, so two at once,
        // from two terminals or two sessions, spoil each other's windows.
        let lock = open(NSHomeDirectory() + "/Library/Caches/shots-kit.lock", O_CREAT | O_RDWR, 0o644)
        guard lock >= 0, flock(lock, LOCK_EX | LOCK_NB) == 0 else {
            print("shots-kit: another run is driving an app; try again once it's done")
            exit(2)
        }
        do {
            guard AXIsProcessTrusted() else { throw Failure("give this terminal Accessibility in System Settings › Privacy & Security") }
            var manifest = try loadManifest(site)
            if let app { manifest.app = app }
            // Trees and pictures are read on a Retina screen; on a 1x one
            // they'd differ from the records without any change (NetworkMonitor#487).
            if stage() == nil, ["check", "update", "record"].contains(command) {
                throw Failure("no Retina screen to read the windows on: the records are read on one")
            }
            // Put back as it was, the installed copy, even after a run with
            // another copy (`--app`, NetworkMonitor#506).
            var installed = manifest
            installed.app = try loadManifest(site).app
            let mac = Mac(manifest: manifest, installed: installed, command: command)
            // However the run ends: Ctrl-C or a kill too.
            for sig in [SIGINT, SIGTERM, SIGHUP] {
                signal(sig, SIG_IGN)
                let source = DispatchSource.makeSignalSource(signal: sig, queue: .global())
                source.setEventHandler { mac.end(); exit(128 + sig) }
                source.resume()
                signalSources.append(source)
            }
            var session = Session(manifest: manifest)
            // Reading the tree needs no focus; a picture shows the window active.
            session.background = ["check", "tree", "audit"].contains(command) && !(command == "check" && compareLooks)
            var status: Int32 = 0
            // English, then each language's page with the same shots in it.
            let languages: [Language?] = [nil] + (manifest.languages ?? []).map { $0 }
            for language in languages where only == nil || only == (language?.code ?? "en") {
                if let language { print("\n\(language.code), for \(language.page):") }
                do {
                    let translator = try language.map { try Translator(app: manifest.app, language: $0) }
                    if command == "video" {
                        guard let name = names.first, names.count == 1, var shot = manifest.shots.first(where: { $0.name == name }),
                              let out = videoOut else {
                            throw Failure("usage: shots-kit video <shot> --out <file, from the site> [--seconds N] [--language CODE]")
                        }
                        if let language, let translator { shot = shot.localized(language, translator) }
                        try mac.hold("recording a window")
                        try session.launch(shot.open)
                        let window = try session.window(shot.window)
                        session.place(window)
                        try session.bringForward(window)
                        let url = site.appendingPathComponent(out)
                        try await session.record(window, to: url, seconds: videoSeconds) {
                            for spec in shot.click ?? [] {
                                usleep(900_000)
                                try session.click(spec, in: window)
                            }
                        }
                        print("video: recorded \(out) (\(Int(videoSeconds)) s)")
                        continue
                    }
                    let s = try await run(command, names: names, manifest: manifest, session: session, mac: mac, site: site,
                                          repo: repo, repoAssets: RepoAssets.of(repoAssets, manifest), language: language,
                                          translator: translator)
                    status = max(status, s)
                    if let missing = translator?.missing, !missing.isEmpty {
                        print("  kept in English, as the app's \(language!.code) table doesn't have them "
                              + "(a name is fine; otherwise add it to the language's `specs`): "
                              + missing.sorted().joined(separator: " | "))
                    }
                } catch { status = 2; print("shots-kit: \(error)") }
            }
            mac.end()
            exit(status)
        } catch {
            print("shots-kit: \(error)")
            exit(2)
        }
    }

    static func run(_ command: String, names: Set<String>, manifest: Manifest, session: Session, mac: Mac, site: URL, repo: URL,
                    repoAssets: RepoAssets?, language: Language? = nil, translator: Translator? = nil) async throws -> Int32 {
        var shots = manifest.shots.filter { names.isEmpty || names.contains($0.name) }
        if shots.isEmpty { throw Failure("no shot named \(names.sorted().joined(separator: ", "))") }
        if let language, let translator { shots = shots.map { $0.localized(language, translator) } }
        // Each language's trees apart, as its labels differ.
        let trees = site.appendingPathComponent(language.map { "shots/trees/\($0.code)" } ?? "shots/trees")
        try FileManager.default.createDirectory(at: trees, withIntermediateDirectories: true)
        var page = try Page(site: site, path: language?.page ?? config.page, up: language?.up ?? "")
        var changed: [String] = [], flagged: [String] = [], failed: [String] = []
        /// Windows whose look differs from their picture's (NetworkMonitor#423).
        var looks: [String] = []
        var problems: [String] = []
        var cached: (args: [String], window: String)?

        // What's made by hand from each window, on the site and in the README
        // and docs (NetworkMonitor#413), to name when the window changes.
        // Named once, from English: they're remade from that window in every
        // language at the same time.
        var handMade: [String: [String]] = [:]
        if language == nil {
            for shot in manifest.shots { handMade[shot.name, default: []] += shot.flags ?? [] }
            for asset in manifest.assets ?? [] {
                for name in asset.shows ?? [] where !(handMade[name] ?? []).contains(asset.file) { handMade[name, default: []].append(asset.file) }
            }
            for asset in repoAssets?.assets ?? [] {
                for name in asset.shows ?? [] { handMade[name, default: []].append("\(asset.file) (main)") }
            }
        }

        // The version each record was taken from (NetworkMonitor#421), English only: what's
        // made by hand is checked against it.
        var versions = language == nil ? Versions.read(trees) : [:]
        let appVersion = Versions.app(manifest.app)

        var current: [String: [String]] = [:]
        // One shot, read and taken.
        func take(_ shot: Shot) async throws {
            // A costly shot follows its base window: retaken only when the
            // base's tree differs from the one it was last taken with.
            var baseTree: [String]?
            if let base = shot.when, command == "record" {
                // Can't be read without taking it (a speed test): record
                // only that it was taken with the base window as it reads
                // now, so a new mark there doesn't retake it.
                guard let now = current[base] else { print("\(shot.name): name \(base) too, to record its base"); return }
                try (now.joined(separator: "\n") + "\n").write(
                    to: trees.appendingPathComponent("\(shot.name).base.txt"), atomically: true, encoding: .utf8)
                print("\(shot.name): recorded \(base) as it was taken with")
                return
            }
            if let base = shot.when {
                let baseFile = trees.appendingPathComponent("\(shot.name).base.txt")
                let taken = (try? String(contentsOf: baseFile, encoding: .utf8))?.split(separator: "\n").map(String.init)
                guard let now = current[base] else {
                    print("\(shot.name): needs \(base) checked first, in the same run"); return
                }
                let named = names.contains(shot.name)
                if taken == now && !named { print("\(shot.name): unchanged (\(base) is)"); return }
                if command != "update" || (taken != nil && !named && command == "check") {
                    print("\(shot.name): \(base) changed, so it's retaken on update")
                    changed.append(shot.name); return
                }
                if command != "update" { return }
                baseTree = now
            }
            // Shots that open the same window without clicks share a launch.
            if cached?.args != shot.open || cached?.window != shot.window || shot.click != nil {
                cached = nil
                try session.launch(shot.open)
                cached = (shot.open, shot.window)
            }
            // Once more from a fresh launch if it doesn't show: a popover
            // now and then doesn't open on the first try.
            var window: AXUIElement
            do { window = try session.window(shot.window) } catch {
                try session.launch(shot.open)
                window = try session.window(shot.window)
            }
            // On the stage, before anything reads it (NetworkMonitor#487).
            session.place(window)
            if let spec = shot.skipIf, find(spec, in: window) != nil {
                print("\(shot.name): skipped while \(spec) shows; it's tried again on the next update")
                cached = nil
                return
            }
            if shot.click != nil { cached = nil }
            for spec in shot.click ?? [] { try session.click(spec, in: window) }
            if let spec = shot.scroll { try session.scrollToEnd(spec, in: window) }
            if let wait = shot.waitFor { try session.wait(for: wait, in: window) }
            // A click can rebuild what was clicked in, such as a popover
            // that grows: find the window again.
            if shot.click != nil || shot.scroll != nil { window = try session.window(shot.window) }
            // Read it once it has settled: lists and charts fill in a
            // moment after the window opens.
            var now = tree(window, data: shot.data ?? [], ignore: shot.ignore ?? [])
            for _ in 0..<12 {
                usleep(700_000)
                let again = tree(window, data: shot.data ?? [], ignore: shot.ignore ?? [])
                if again == now { break }
                now = again
            }
            current[shot.name] = now
            if command == "tree" { print(now.joined(separator: "\n")); return }
            if command == "audit" {
                let found = AccessibilityAudit.audit(window).map { "\(shot.window): \($0)" }
                print("\(shot.name): " + (found.isEmpty ? "nothing missing" : "\(found.count) to fix"))
                problems += found
                return
            }

            let treeFile = trees.appendingPathComponent("\(shot.name).txt")
            let before = (try? String(contentsOf: treeFile, encoding: .utf8))?.split(separator: "\n").map(String.init)
            let differs = before != now
            // The look, against the one kept from the picture (NetworkMonitor#423).
            let lookFile = trees.appendingPathComponent("\(shot.name).look")
            if let file = shot.file, command == "record" {
                // From the picture, with the window's masks laid on it as
                // it is now: the picture is what the site shows.
                let fresh = try await session.look(window, shot)
                if let picture = NSImage(contentsOf: site.appendingPathComponent(file))?
                    .cgImage(forProposedRect: nil, context: nil, hints: nil),
                   picture.width == fresh.picture.width, picture.height == fresh.picture.height,
                   let look = Look(picture, masks: fresh.masks) {
                    try look.text.write(to: lookFile, atomically: true, encoding: .utf8)
                    let d = fresh.look.differing(from: look)
                    print("\(shot.name): kept its look, from \(file)" + (d.map { $0.count > 0 ? " (\($0.count) of \($0.of) cells differ now)" : "" } ?? ""))
                } else {
                    print("\(shot.name): \(file) isn't the window's size now, so its look isn't kept; retake it")
                }
            } else if shot.file != nil,
                      // An update compares what it won't retake anyway.
                      (command == "check" && compareLooks)
                        || (command == "update" && !(differs || names.contains(shot.name) || shot.always == true)),
                      let kept = (try? String(contentsOf: lookFile, encoding: .utf8)).flatMap(Look.init(text:)) {
                let fresh = try await session.look(window, shot)
                if let d = fresh.look.differing(from: kept) {
                    if d.count > Look.threshold {
                        looks.append("\(shot.name): \(d.count) of \(d.of) cells differ")
                    } else if d.count > 0 {
                        print("\(shot.name): looks the same (\(d.count) of \(d.of) cells differ, within \(Look.threshold))")
                    }
                } else {
                    looks.append("\(shot.name): its picture is \(kept.width)×\(kept.height), the window \(fresh.look.width)×\(fresh.look.height) now")
                }
            }
            if command == "record" {
                try record(shot, now: now, before: before, handMade: handMade[shot.name] ?? [], trees: trees)
                return
            }
            if let before, differs {
                print("\(shot.name): the interface changed")
                diff(before, now).prefix(40).forEach { print($0) }
                changed.append(shot.name)
            } else {
                print(differs ? "\(shot.name): no tree recorded yet" : "\(shot.name): unchanged")
            }
            let named = names.contains(shot.name)
            // What's made by hand from this window is compared with the
            // tree it was made from: retaking the window's own picture
            // doesn't remake them, so it doesn't end the reminder. Only an
            // update by the window's name does, once they're remade.
            let hand = handMade[shot.name] ?? []
            let madeFile = trees.appendingPathComponent("\(shot.name).made.txt")
            let madeOnDisk = (try? String(contentsOf: madeFile, encoding: .utf8))?.split(separator: "\n").map(String.init)
            let made = madeOnDisk ?? before
            if !hand.isEmpty, let made, made != now, !(command == "update" && named) {
                flagged += hand.map { "\($0), from \(shot.name)" }
            }
            guard command == "update", differs || named || shot.always == true || baseTree != nil else { return }
            // A window that only flags videos keeps its old tree until
            // they're remade and it's updated by name, so the reminder stays.
            if shot.file == nil, before != nil, !named { return }

            if let file = shot.file {
                // Active, with its look kept from the same capture.
                let taken = try await session.look(window, shot)
                let image = taken.picture
                // A crop leaves out the traffic lights that tell.
                if shot.crop == nil && !isActive(image, window: window) {
                    // What had the front instead, to find what takes it.
                    let front = NSWorkspace.shared.frontmostApplication
                    print("  warning: \(file) shows the window inactive; in front: "
                          + "\(front?.localizedName ?? "nothing") (\(front?.bundleIdentifier ?? "?"))")
                }
                try writePNG(image, to: site.appendingPathComponent(file))
                try taken.look.text.write(to: lookFile, atomically: true, encoding: .utf8)
                page.setSize(of: file, pixels: CGSize(width: image.width, height: image.height))
                print("  retook \(file) (\(image.width)×\(image.height))")
                // And the README's copy of it, in this language (NetworkMonitor#434).
                for copy in try copyToRepo(manifest: manifest, site: site, repo: repo, repoAssets: repoAssets,
                                           language: language, shots: [shot.name]) {
                    print("  copied it to \(copy)")
                }
            }
            let windowFrame = frame(window) ?? .zero
            for area in shot.areas ?? [] {
                guard var element = find(area.element, in: window) else { print("  warning: no \(area.element) for \(area.match)"); continue }
                if area.parent == true, let p = parent(of: element) { element = p }
                guard let r = frame(element) else { continue }
                page.place(area, at: r.offsetBy(dx: -windowFrame.minX, dy: -windowFrame.minY), windowWidth: windowFrame.width)
            }
            // Each record keeps its version while it holds the same tree.
            let treeName = treeFile.lastPathComponent, madeName = madeFile.lastPathComponent
            if !hand.isEmpty {
                if named {
                    try (now.joined(separator: "\n") + "\n").write(to: madeFile, atomically: true, encoding: .utf8)
                    versions[madeName] = (madeOnDisk == now ? versions[madeName] : before == now ? versions[treeName] : nil) ?? appVersion
                } else if madeOnDisk == nil, let before {
                    try (before.joined(separator: "\n") + "\n").write(to: madeFile, atomically: true, encoding: .utf8)
                    versions[madeName] = versions[treeName]
                }
            }
            try (now.joined(separator: "\n") + "\n").write(to: treeFile, atomically: true, encoding: .utf8)
            versions[treeName] = (before == now ? versions[treeName] : nil) ?? appVersion
            if language == nil { try Versions.write(versions, to: trees) }
            if let baseTree {
                try (baseTree.joined(separator: "\n") + "\n").write(
                    to: trees.appendingPathComponent("\(shot.name).base.txt"), atomically: true, encoding: .utf8)
            }
            // Saved as it goes, so a later failure doesn't leave a picture
            // without its size and areas.
            try page.save()
        }

        // Every window that needs nothing of the person at the Mac first, behind the others
        // and without focus. A window to bring forward or click for real while
        // someone is at the Mac isn't taken (NetworkMonitor#521): it's reported as not taken, and
        // why, and the run goes on and ends as it would without it. Only with
        // `--wait-away MINUTES` does it wait, silently and with the lanes free,
        // in case the Mac is left idle or locked anyway, then takes those alone
        // (NetworkMonitor#504).
        var queue = shots
        var notTaken: [String] = []
        let deadline = Date().addingTimeInterval(waitAway * 60)
        try mac.hold("reading windows")
        while true {
            cached = nil
            var later: [Shot] = [], reasons: [String] = []
            for shot in queue {
                // A costly shot follows its base window, so waits with it.
                if let base = shot.when, later.contains(where: { $0.name == base }) { later.append(shot); continue }
                do { try await take(shot) } catch let away as NeedsAway {
                    later.append(shot)
                    reasons.append("\(shot.name) needs \(away.what)")
                    cached = nil
                } catch {
                    print("\(shot.name): \(error)")
                    failed.append(shot.name)
                    cached = nil
                }
            }
            if later.isEmpty { break }
            queue = later
            mac.letGo()
            if waitAway > 0 {
                print("\n" + reasons.joined(separator: "; ") + ": these need the screen while you're using it, so the run "
                      + "waits up to \(String(format: "%g", waitAway)) min, silently with the lanes free, in case it's left idle or locked")
            }
            guard waitAway > 0, try mac.holdOnceAway(later.map(\.name).joined(separator: ", ") + ", with the Mac idle",
                                                     until: deadline) else {
                notTaken = reasons
                break
            }
        }

        if command == "update" {
            page.stampAssets(site: site)
            try page.save()
        }
        // Advice, not a failure: it reads pixels, which the Mac can change
        // without the app (NetworkMonitor#423).
        if !looks.isEmpty {
            print("\nThese look different from their pictures (a colour, an icon, spacing, a font), whatever their trees say. "
                  + "Compare them by eye, and retake the ones that changed with `update <names>`:")
            looks.forEach { print("  " + $0) }
        }
        if !flagged.isEmpty {
            print("\nThese show a window that changed since they were made. Remake them by hand, then run `update` with the window's name:")
            Set(flagged).sorted().forEach { print("  \($0)") }
        }
        // Not a failure, and nothing to hold a release or a review on (NetworkMonitor#521):
        // what's left is said, and taken on a later run.
        if !notTaken.isEmpty {
            print("\nNot taken: they need the real screen (a window brought forward, or a real click), and the Mac was "
                  + "in use. Their pictures and trees are as they were; a later run takes them:")
            notTaken.forEach { print("  " + $0) }
        }
        if command == "audit", !problems.isEmpty {
            // The same row repeats down a list; say it once.
            var seen = Set<String>()
            print("\nFor VoiceOver:")
            for p in problems where seen.insert(p).inserted { print("  " + p) }
        }
        if !failed.isEmpty { return 2 }
        if command == "record" { return 0 }
        if command == "audit" { return problems.isEmpty ? 0 : 1 }
        return command == "check" && !(changed.isEmpty && flagged.isEmpty) ? 1 : 0
    }

    /// Records a window's tree as it reads now, without retaking its picture
    /// (NetworkMonitor#416): for after a mark in the manifest changed what's data or left
    /// out, such as the Mac's connection. The diff it prints should be only
    /// what the new marks cover. A reminder to remake what's made by hand
    /// stays: the tree each was made from is updated only if it was the
    /// window's tree, and a window that only flags videos keeps its old tree
    /// while they're waiting to be remade.
    static func record(_ shot: Shot, now: [String], before: [String]?, handMade: [String], trees: URL) throws {
        let treeFile = trees.appendingPathComponent("\(shot.name).txt")
        let madeFile = trees.appendingPathComponent("\(shot.name).made.txt")
        if shot.file == nil, !handMade.isEmpty, let before, before != now {
            print("\(shot.name): kept, as what's made from it is waiting to be remade (\(handMade.joined(separator: ", ")))")
            return
        }
        if let before, before == now { print("\(shot.name): unchanged"); return }
        print("\(shot.name): recorded" + (before == nil ? "" : ", as it reads now:"))
        if let before { diff(before, now).prefix(40).forEach { print($0) } }
        let text = now.joined(separator: "\n") + "\n"
        if let made = (try? String(contentsOf: madeFile, encoding: .utf8))?.split(separator: "\n").map(String.init),
           made == before {
            try text.write(to: madeFile, atomically: true, encoding: .utf8)
        }
        try text.write(to: treeFile, atomically: true, encoding: .utf8)
    }
}
