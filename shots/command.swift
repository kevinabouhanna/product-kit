// shots-kit, a driver of the project's choosing (product-kit#35). The files are one program:
// `shots-kit` builds them together, and `shots-kit vendor` writes them into one file for a
// project's CI.

import AppKit
import ApplicationServices
import CryptoKit
import ScreenCaptureKit

// MARK: - A driver of the project's choosing

/// The manifest's `driver` (product-kit#35): a program that opens each picture's screen
/// in an app shots-kit can't drive itself (an iPhone app in the simulator, a web page),
/// and says what it shows. It runs in the project's checkout, once per shot and language,
/// with a request as JSON on its input:
///
///     {"action": "read" | "take", "shot": <the manifest's entry>, "language": "en",
///      "picture": "/abs/path.png" (take only), "repo": "/abs/project"}
///
/// and answers with JSON on its output: `{"window": <element>}` (an element is
/// `Described`'s: `role`, `title`, `description`, `value`, `identifier`, `frame`,
/// `children`, with the Mac's accessibility names), after writing the picture for a take,
/// or `{"skipped": "why"}`. Anything it prints on its error output is shown when it fails.
/// The core does the rest as for any app: masks the screen, leaves out `ignore` and
/// `data`, compares with the recorded tree, and records the tree, the picture's size on the
/// page and the README's copy when it's taken.
struct DriverConfig: Decodable {
    /// The program, from the project's checkout: `["drivers/ios-simulator", "--scheme", "App"]`.
    var command: [String]
    /// Builds what it drives, once per run, before the first shot. Optional.
    var build: [String]?
}

enum Commanded {
    /// How long a build, and each request, may take before it's stopped.
    static let buildLimit: TimeInterval = 20 * 60, requestLimit: TimeInterval = 5 * 60

    struct Answer: Decodable {
        var window: Described?
        var skipped: String?
    }

    static func run(_ command: String, names: Set<String>, manifest: Manifest, driver: DriverConfig, site: URL, repo: URL,
                    repoAssets: RepoAssets?, only: String?) -> Int32 {
        guard ["check", "update", "tree", "record"].contains(command) else {
            print("\(command): not for a manifest with a `driver`; check, update, tree and record are")
            return 2
        }
        let unknown = names.subtracting(manifest.shots.map(\.name))
        if !unknown.isEmpty {
            print("\(command): no shot named \(unknown.sorted().joined(separator: ", "))")
            return 2
        }
        if command == "record", names.isEmpty {
            print("record: name the screens whose marks changed; recording every tree would hide a real change")
            return 2
        }
        // Each shot's entry as the manifest writes it, for the driver.
        let entries: [String: Any]
        do {
            let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: site.appendingPathComponent("shots/shots.json")))
            let list = (raw as? [String: Any])?["shots"] as? [[String: Any]] ?? []
            entries = Dictionary(list.compactMap { e in (e["name"] as? String).map { ($0, e as Any) } }, uniquingKeysWith: { a, _ in a })
            if let build = driver.build, !build.isEmpty {
                print("building: \(build.joined(separator: " "))")
                try Rendered.runCommand(build, in: repo, limit: buildLimit, what: "the build")
            }
        } catch {
            print("\(command): \(error)")
            return 2
        }

        var status: Int32 = 0
        var changedEnglish: [String] = []
        let languages: [Language?] = [nil] + (manifest.languages ?? []).map { $0 }
        for language in languages where only == nil || only == (language?.code ?? "en") {
            if let language { print("\n\(language.code), for \(language.page):") }
            // Element specs in the language, from the app's own table, where there is one.
            let translator = language.flatMap { try? Translator(app: manifest.app, language: $0) }
            do {
                let s = try runLanguage(command, names: names, manifest: manifest, driver: driver, entries: entries, site: site,
                                        repo: repo, repoAssets: repoAssets, language: language, translator: translator,
                                        changed: &changedEnglish)
                status = max(status, s)
            } catch {
                print("\(command): \(error)")
                status = 2
            }
        }
        // What's made by hand from a screen that changed: remade by hand, when asked.
        let handMade = ((manifest.assets ?? []) + (repoAssets?.assets ?? [])).compactMap { asset -> String? in
            let shows = (asset.shows ?? []).filter(changedEnglish.contains)
            return shows.isEmpty ? nil : "\(asset.file) (shows \(shows.joined(separator: ", ")))"
        }
        if !handMade.isEmpty, command != "tree" {
            print("Made by hand, and showing what changed; remake by hand when asked:")
            handMade.forEach { print("  " + $0) }
        }
        return status
    }

    static func runLanguage(_ command: String, names: Set<String>, manifest: Manifest, driver: DriverConfig,
                            entries: [String: Any], site: URL, repo: URL, repoAssets: RepoAssets?, language: Language?,
                            translator: Translator?, changed changedEnglish: inout [String]) throws -> Int32 {
        var shots = manifest.shots.filter { names.isEmpty || names.contains($0.name) }
        // In another language: its specs from the app's table, where there is one, and
        // always its pictures in the language's own folder.
        if let language {
            shots = shots.map { shot in
                if let translator { return shot.localized(language, translator) }
                var shot = shot
                shot.file = shot.file.map(language.file)
                return shot
            }
        }
        let trees = site.appendingPathComponent(language.map { "shots/trees/\($0.code)" } ?? "shots/trees")
        try FileManager.default.createDirectory(at: trees, withIntermediateDirectories: true)
        let pagePath = language?.page ?? config.page
        var page = FileManager.default.fileExists(atPath: site.appendingPathComponent(pagePath).path)
            ? try Page(site: site, path: pagePath, up: language?.up ?? "") : nil
        var versions = language == nil ? Versions.read(trees) : [:]
        var changed: [String] = [], failed: [String] = [], taken: [String] = []

        for shot in shots {
            do {
                guard let answer = try ask(driver, action: "read", entry: entries[shot.name], language: language, picture: nil, repo: repo) else {
                    continue
                }
                if let why = answer.skipped { print("\(shot.name): skipped, \(why)"); continue }
                guard let window = answer.window else { throw Failure("the driver said nothing of the screen") }
                let now = tree(window, data: shot.data ?? [], ignore: shot.ignore ?? [])
                if command == "tree" { print(now.joined(separator: "\n")); continue }
                let treeFile = trees.appendingPathComponent("\(shot.name).txt")
                let before = (try? String(contentsOf: treeFile, encoding: .utf8))?.split(separator: "\n").map(String.init)
                let differs = before != now
                if command == "record" {
                    try (now.joined(separator: "\n") + "\n").write(to: treeFile, atomically: true, encoding: .utf8)
                    print("\(shot.name): recorded" + (differs ? "" : ", as it was"))
                    if let before, differs { diff(before, now).prefix(40).forEach { print($0) } }
                    continue
                }
                if let before, differs {
                    print("\(shot.name): the interface changed")
                    diff(before, now).prefix(40).forEach { print($0) }
                    changed.append(shot.name)
                    if language == nil { changedEnglish.append(shot.name) }
                } else {
                    print(differs ? "\(shot.name): no tree recorded yet" : "\(shot.name): unchanged")
                }
                guard command == "update", differs || names.contains(shot.name) || shot.always == true else { continue }
                if let file = shot.file {
                    let picture = site.appendingPathComponent(file)
                    try FileManager.default.createDirectory(at: picture.deletingLastPathComponent(), withIntermediateDirectories: true)
                    guard let answer = try ask(driver, action: "take", entry: entries[shot.name], language: language,
                                               picture: picture, repo: repo) else { continue }
                    if let why = answer.skipped { print("\(shot.name): not taken, \(why)"); continue }
                    guard let image = NSImage(contentsOf: picture)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                        throw Failure("the driver wrote no picture at \(file)")
                    }
                    page?.setSize(of: file, pixels: CGSize(width: image.width, height: image.height))
                    print("  retook \(file) (\(image.width)×\(image.height))")
                    for copy in try copyToRepo(manifest: manifest, site: site, repo: repo, repoAssets: repoAssets,
                                               language: language, shots: [shot.name]) {
                        print("  copied it to \(copy)")
                    }
                    taken.append(shot.name)
                }
                try (now.joined(separator: "\n") + "\n").write(to: treeFile, atomically: true, encoding: .utf8)
                if language == nil, let version = versionOfApp(manifest) {
                    versions[treeFile.lastPathComponent] = (before == now ? versions[treeFile.lastPathComponent] : nil) ?? version
                    try Versions.write(versions, to: trees)
                }
                if let page { try page.save() }
            } catch {
                print("\(shot.name): \(error)")
                failed.append(shot.name)
            }
        }
        if command == "update", var p = page {
            p.stampAssets(site: site)
            try p.save()
        }
        switch command {
        case "check":
            print(changed.isEmpty ? "check: no interface changed" : "check: \(changed.count) changed; `shots-kit update` retakes them")
            return failed.isEmpty ? (changed.isEmpty ? 0 : 1) : 2
        case "update":
            print(taken.isEmpty ? "update: nothing to retake" : "update: retook \(taken.count)")
            return failed.isEmpty ? 0 : 2
        default:
            return failed.isEmpty ? 0 : 2
        }
    }

    /// The app's version, when the manifest names an app bundle that has one.
    static func versionOfApp(_ manifest: Manifest) -> String? {
        manifest.app.isEmpty ? nil : Versions.app(manifest.app)
    }

    /// One request to the driver, and its answer.
    static func ask(_ driver: DriverConfig, action: String, entry: Any?, language: Language?, picture: URL?, repo: URL) throws -> Answer? {
        var request: [String: Any] = ["action": action, "shot": entry ?? [:], "language": language?.code ?? "en", "repo": repo.path]
        if let picture { request["picture"] = picture.path }
        let input = try JSONSerialization.data(withJSONObject: request, options: [.sortedKeys])
        let output = try call(driver.command, input: input, in: repo, limit: requestLimit)
        do {
            return try JSONDecoder().decode(Answer.self, from: output)
        } catch {
            let said = String(decoding: output.prefix(400), as: UTF8.self)
            throw Failure("the driver's answer isn't the JSON shots-kit reads (\(error.localizedDescription)): \(said)")
        }
    }

    /// Runs the driver with `input`, stopped after `limit` seconds: what it printed on its
    /// output, or a failure with the end of its error output.
    static func call(_ argv: [String], input: Data, in dir: URL, limit: TimeInterval) throws -> Data {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = argv
        p.currentDirectoryURL = dir
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        p.standardInput = stdin
        p.standardOutput = stdout
        p.standardError = stderr
        try p.run()
        stdin.fileHandleForWriting.write(input)
        try? stdin.fileHandleForWriting.close()
        let timer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + limit, execute: timer)
        // Both read at once, so a driver that says a lot on either never blocks.
        var errors = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async { errors = stderr.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        p.waitUntilExit()
        timer.cancel()
        if p.terminationReason == .uncaughtSignal, p.terminationStatus == SIGTERM {
            throw Failure("the driver took more than \(Int(limit / 60)) minutes, so it was stopped")
        }
        guard p.terminationStatus == 0 else {
            let tail = String(decoding: errors, as: UTF8.self).split(separator: "\n").suffix(15).joined(separator: "\n")
            throw Failure("the driver failed (exit \(p.terminationStatus))" + (tail.isEmpty ? "" : ":\n\(tail)"))
        }
        return output
    }
}
