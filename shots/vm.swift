// shots-kit, in a throwaway macOS VM (product-kit#35). The files are one program: `shots-kit` builds
// them together, and `shots-kit vendor` writes them into one file for a project's CI.

import AppKit
import ApplicationServices
import CryptoKit
import ScreenCaptureKit

// MARK: - In a VM (product-kit#10)

/// Takes the pictures in a throwaway macOS VM (`mac-vm`, from the shared-mac
/// plugin) rather than on this Mac's screen. The VM has its own screen, pointer
/// and focus, so nothing shows on the person's screens, nothing waits for the
/// Mac to be idle, and this Mac's copy of the app is never quit.
///
/// Through a shared folder go this tool, the app (zipped: through the shared
/// folder a bundle's symbolic links come out as loops, NetworkMonitor#528), a
/// copy of the project's and the site's files, and the config's `vm.files`.
/// Inside, the app is installed where the manifest says, `vm.setup` runs, then
/// this same tool, which may take the VM's screen whenever. Each file the run
/// inside changed or added comes back; no other file here is touched, so
/// something changed here meanwhile stays.
enum InVM {
    /// The commands that open the app; the rest read files only, here.
    static let commands: Set<String> = ["check", "update", "record", "tree", "audit"]

    /// This is the run inside the VM.
    static var inside: Bool { ProcessInfo.processInfo.environment["SHOTS_KIT_IN_VM"] == "1" }

    static func onPath(_ name: String) -> String? {
        for dir in (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":") {
            let path = "\(dir)/\(name)"
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }

    /// In the VM only: a system alert in front (UserNotificationCenter), such
    /// as macOS asking again whether captures made over SSH may bypass the
    /// window picker, is answered Allow, so the app's window can come forward.
    /// The VM is this run's own, so there's nobody else to answer it.
    static func allowSystemAlert() {
        guard inside, let front = NSWorkspace.shared.frontmostApplication,
              front.bundleIdentifier == "com.apple.UserNotificationCenter" else { return }
        let ax = AXUIElementCreateApplication(front.processIdentifier)
        for window in attribute(ax, kAXWindowsAttribute) as? [AXUIElement] ?? [] {
            if let allow = find("AXButton:Allow", in: window) {
                AXUIElementPerformAction(allow, kAXPressAction as CFString)
                print("  answered a system alert in the VM: Allow")
                usleep(1_000_000)
                return
            }
        }
    }

    /// Quoted for the VM's shell.
    static func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    /// The files of a checkout: what git tracks and doesn't ignore, so no
    /// build folders; every file but `.git`'s outside one.
    static func files(in dir: URL) -> [String] {
        let fm = FileManager.default
        func isFile(_ rel: String) -> Bool {
            var folder: ObjCBool = false
            return fm.fileExists(atPath: dir.appendingPathComponent(rel).path, isDirectory: &folder) && !folder.boolValue
        }
        let git = runTool("/usr/bin/git", ["-C", dir.path, "ls-files", "-z", "--cached", "--others", "--exclude-standard"])
        if git.status == 0 {
            return Set(git.output.split(separator: "\0").map(String.init)).filter(isFile).sorted()
        }
        return walk(dir)
    }

    /// Every file under a folder, by its path from there, without `.git`'s.
    static func walk(_ dir: URL) -> [String] {
        guard let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        let base = dir.standardizedFileURL.resolvingSymlinksInPath().path + "/"
        var found: [String] = []
        for case let url as URL in e {
            if url.lastPathComponent == ".git" { e.skipDescendants(); continue }
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true,
                  url.lastPathComponent != ".DS_Store" else { continue }
            let path = url.standardizedFileURL.resolvingSymlinksInPath().path
            if path.hasPrefix(base) { found.append(String(path.dropFirst(base.count))) }
        }
        return found.sorted()
    }

    static func hashes(_ dir: URL) -> [String: String] {
        var all: [String: String] = [:]
        for rel in walk(dir) {
            guard let data = try? Data(contentsOf: dir.appendingPathComponent(rel)) else { continue }
            all[rel] = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
        return all
    }

    /// What changed under `from` since `before`, written over the same path under `to`.
    static func bringBack(from: URL, to: URL, before: [String: String]) throws -> [String] {
        var changed: [String] = []
        for (rel, hash) in hashes(from).sorted(by: { $0.key < $1.key }) where before[rel] != hash {
            let dest = to.appendingPathComponent(rel)
            try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contentsOf: from.appendingPathComponent(rel)).write(to: dest, options: .atomic)
            changed.append(rel)
        }
        return changed
    }

    /// Runs `arguments` (the command, its names and options) inside a VM;
    /// returns its status. `app` is `--app`, if given.
    static func run(_ arguments: [String], manifest: Manifest, site: URL, repo: URL, app: String?) -> Int32 {
        guard let macVM = onPath("mac-vm") else {
            print("shots-kit: a run in a VM needs mac-vm on PATH (the shared-mac plugin); --here takes the pictures on this Mac")
            return 2
        }
        let fm = FileManager.default
        let caches = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Caches/shots-kit/vm")
        // One VM run per site at a time: two would bring back over each other.
        // The lock is on the site's folder itself, so no lock file is left behind.
        let lock = open(site.path, O_RDONLY)
        guard lock >= 0, flock(lock, LOCK_EX | LOCK_NB) == 0 else {
            print("shots-kit: another run is taking this site's pictures in a VM; try again once it's done")
            return 2
        }
        let share = caches.appendingPathComponent("shots-\(getpid())")
        try? fm.removeItem(at: share)
        defer { try? fm.removeItem(at: share) }
        do {
            try fm.createDirectory(at: share, withIntermediateDirectories: true)
            guard let me = Bundle.main.executablePath else { throw Failure("can't find this tool's own file") }
            try fm.copyItem(atPath: me, toPath: share.appendingPathComponent("shots-kit").path)
            let appPath = app ?? manifest.app
            guard fm.fileExists(atPath: appPath) else { throw Failure("no app at \(appPath) to copy into the VM") }
            let zip = runTool("/usr/bin/ditto", ["-c", "-k", "--keepParent", appPath, share.appendingPathComponent("app.zip").path])
            guard zip.status == 0 else { throw Failure("couldn't zip \(appPath): \(zip.output)") }

            // The project, and the site when it has one.
            var copies: [(name: String, here: URL)] = [("repo", repo)]
            if !manifestInRepo { copies.append(("site", site)) }
            var before: [String: [String: String]] = [:]
            for copy in copies {
                let into = share.appendingPathComponent(copy.name)
                for rel in files(in: copy.here) {
                    let dest = into.appendingPathComponent(rel)
                    try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try fm.copyItem(at: copy.here.appendingPathComponent(rel), to: dest)
                }
                try fm.createDirectory(at: into, withIntermediateDirectories: true)
                before[copy.name] = hashes(into)
            }

            // What has to be made from this Mac, by the project, into the VM.
            let prepared = share.appendingPathComponent("prepared")
            try fm.createDirectory(at: prepared, withIntermediateDirectories: true)
            if let prepare = config.vm.prepare {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/bin/bash")
                p.arguments = ["-c", prepare]
                p.currentDirectoryURL = repo
                var env = ProcessInfo.processInfo.environment
                env["SHOTS_VM_DIR"] = prepared.path
                env["SHOTS_APP"] = app ?? manifest.app
                p.environment = env
                try p.run()
                p.waitUntilExit()
                guard p.terminationStatus == 0 else { throw Failure("vm.prepare failed (exit \(p.terminationStatus)): \(prepare)") }
            }

            let inside = "/Volumes/My Shared Files/\(share.lastPathComponent)"
            var script = [
                "set -e",
                "s=\(q(inside))",
                "export SHOTS_VM_DIR=\"$s/prepared\"",
                // The installed copy's place, whichever copy goes in (`--app`).
                "app=\(q(manifest.app))",
                // Quit, whoever opened it (a login item does at boot), so it
                // reads the files placed below when it opens again.
                "osascript -e \(q("tell application id \"\(manifest.bundle)\" to quit")) >/dev/null 2>&1 || true",
                "pkill -f \"$app/Contents/MacOS/\" 2>/dev/null || true",
                "t=$(mktemp -d /tmp/shots-app.XXXXXX)",
                "ditto -x -k \"$s/app.zip\" \"$t\"",
                // The same app kept, so what an image approved for it stays (product-kit#12).
                "if [ -d \"$app\" ] && diff -rq \"$app\" \"$t\"/*.app >/dev/null 2>&1; then echo \"shots-kit: $app in the VM is this app already\"",
                "else mkdir -p \"$(dirname \"$app\")\"; rm -rf \"$app\"; mv \"$t\"/*.app \"$app\"; fi",
            ]
            // This Mac's files, to the same place in the VM.
            let home = NSHomeDirectory()
            for (i, file) in config.vm.files.enumerated() {
                let path = (file as NSString).expandingTildeInPath
                guard fm.fileExists(atPath: path) else {
                    print("shots-kit: \(file) isn't on this Mac, so the VM goes without it")
                    continue
                }
                let name = (path as NSString).lastPathComponent
                let holder = share.appendingPathComponent("files/\(i)")
                try fm.createDirectory(at: holder, withIntermediateDirectories: true)
                let copied = runTool("/usr/bin/ditto", [path, holder.appendingPathComponent(name).path])
                guard copied.status == 0 else { throw Failure("couldn't copy \(file): \(copied.output)") }
                let there = path.hasPrefix(home + "/") ? "\"$HOME\"/" + q(String(path.dropFirst(home.count + 1))) : q(path)
                script.append("mkdir -p \"$(dirname \(there))\" && rm -rf \(there) && ditto \"$s\"/files/\(i)/\(q(name)) \(there)")
            }
            // Settings are read again from the files just placed.
            script.append("killall -u \"$USER\" cfprefsd 2>/dev/null || true")
            script.append("cd \"$s/repo\"")
            if let setup = config.vm.setup { script.append("SHOTS_APP=\"$app\" /bin/bash -c \(q(setup))") }
            // The VM's screen is this run's alone: taken whenever, with no Mac lanes.
            let lane = Mac(manifest: manifest, installed: manifest, command: arguments.first ?? "").lane
            script.append("MAC_LANE_IDLE=0 MAC_LANE_HELD=\(q("\(lane) screen")) SHOTS_KIT_IN_VM=1 \"$s/shots-kit\" "
                          + arguments.map(q).joined(separator: " ")
                          + " --repo \"$s/repo\"" + (manifestInRepo ? "" : " --site \"$s/site\""))

            print("shots-kit: \(arguments.first ?? "") in a VM (mac-vm"
                  + (config.vm.image.map { ", the \($0) image" } ?? "") + ", a \(config.vm.display) screen)…")
            let p = Process()
            p.executableURL = URL(fileURLWithPath: macVM)
            p.arguments = ["run", "--share", share.path, "--display", config.vm.display]
                + (config.vm.image.map { ["--image", $0] } ?? [])
                + ["--", "/bin/bash", "-c", script.joined(separator: "\n")]
            try p.run()
            // Stopped from outside: mac-vm deletes its clone, then this folder goes.
            for sig in [SIGINT, SIGTERM, SIGHUP] {
                signal(sig, SIG_IGN)
                let source = DispatchSource.makeSignalSource(signal: sig, queue: .global())
                source.setEventHandler {
                    if p.isRunning { kill(p.processIdentifier, SIGTERM) }
                    p.waitUntilExit()
                    try? fm.removeItem(at: share)
                    exit(128 + sig)
                }
                source.resume()
                signalSources.append(source)
            }
            p.waitUntilExit()

            // Whatever the status: an update saves each picture as it goes.
            var back: [String] = []
            for copy in copies {
                back += try bringBack(from: share.appendingPathComponent(copy.name), to: copy.here,
                                      before: before[copy.name] ?? [:]).map { copy.here.appendingPathComponent($0).path }
            }
            if !back.isEmpty {
                print("\nBrought back from the VM:")
                back.forEach { print("  " + $0) }
            }
            return p.terminationStatus
        } catch {
            print("shots-kit: \(error)")
            return 2
        }
    }
}
