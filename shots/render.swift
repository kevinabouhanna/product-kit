// shots-kit, pictures the project draws itself (product-kit#35). The files are one program: `shots-kit` builds
// them together, and `shots-kit vendor` writes them into one file for a project's CI.

import AppKit
import AVFoundation
import ApplicationServices
import CryptoKit
import ScreenCaptureKit

// MARK: - Drawn by the project

/// The manifest's `render` (product-kit#8): how the project draws its own pictures.
/// `{out}` in either command is the folder the drawings go in. Both run in the
/// project's checkout.
struct Render: Decodable {
    /// Builds what draws them, such as `["./build.sh"]`. Optional.
    var build: [String]?
    /// Draws every picture into `{out}`, out of sight and from fixed data:
    /// `["build/App.app/Contents/MacOS/App", "--snapshot", "shots/demo.json", "{out}"]`.
    var command: [String]
}

/// Pictures the project draws itself, from fixed data with a fixed clock, out of
/// sight (product-kit#8). A drawing that differs from its picture by a pixel means
/// the interface changed, since nothing else can: so `check` compares them, and
/// `update` copies the ones that differ. No app is opened, nothing is shown, and
/// no Mac lane is taken.
enum Rendered {
    /// A shot of a manifest with `render`: its picture and the drawing it's from.
    struct Shot: Decodable {
        var name: String
        var file: String
        var render: String
    }

    /// How long each command may take before it's stopped.
    static let buildLimit: TimeInterval = 20 * 60, drawLimit: TimeInterval = 10 * 60

    static func run(_ command: String, names: Set<String>, manifest: Manifest, render: Render, site: URL, repo: URL) -> Int32 {
        guard ["check", "update"].contains(command) else {
            print("\(command): not for pictures the project draws itself (the manifest's `render`); check and update are")
            return 2
        }
        let shots = manifest.shots.filter { names.isEmpty || names.contains($0.name) }
        let unknown = names.subtracting(manifest.shots.map(\.name))
        if !unknown.isEmpty || shots.isEmpty {
            print("\(command): no shot named \((unknown.isEmpty ? names : unknown).sorted().joined(separator: ", "))")
            return 2
        }
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("shots-kit-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: out) }
        do {
            try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
            func expand(_ argv: [String]) -> [String] { argv.map { $0.replacingOccurrences(of: "{out}", with: out.path) } }
            if let build = render.build, !build.isEmpty {
                print("building: \(build.joined(separator: " "))")
                try runCommand(expand(build), in: repo, limit: buildLimit, what: "the build")
            }
            print("drawing: \(render.command.joined(separator: " "))")
            try runCommand(expand(render.command), in: repo, limit: drawLimit, what: "the drawing")
        } catch {
            print("\(command): \(error)")
            return 2
        }

        var changed: [String] = [], missing: [String] = []
        for shot in shots {
            guard let drawing = shot.render else { continue }
            let drawn = out.appendingPathComponent(drawing)
            guard FileManager.default.fileExists(atPath: drawn.path) else {
                print("\(shot.name): the drawing made no \(drawing)")
                missing.append(shot.name)
                continue
            }
            let picture = site.appendingPathComponent(shot.file ?? "")
            guard let difference = compare(drawn, picture) else {
                print("\(shot.name): unchanged")
                continue
            }
            changed.append(shot.name)
            if command == "update" {
                do {
                    try FileManager.default.createDirectory(at: picture.deletingLastPathComponent(), withIntermediateDirectories: true)
                    if FileManager.default.fileExists(atPath: picture.path) { try FileManager.default.removeItem(at: picture) }
                    try FileManager.default.copyItem(at: drawn, to: picture)
                    print("\(shot.name): redrawn (\(difference)), \(shot.file ?? "")")
                } catch {
                    print("\(shot.name): couldn't write \(shot.file ?? ""): \(error)")
                    missing.append(shot.name)
                }
            } else {
                print("\(shot.name): changed: \(difference)")
            }
        }
        // What's made by hand from a window that changed: remade by hand, when asked.
        let handMade = (manifest.assets ?? []).compactMap { asset -> String? in
            let shows = (asset.shows ?? []).filter(changed.contains)
            return shows.isEmpty ? nil : "\(asset.file) (shows \(shows.joined(separator: ", ")))"
        }
        if !handMade.isEmpty {
            print("Made by hand, and showing what changed; remake by hand when asked:")
            handMade.forEach { print("  " + $0) }
        }
        let total = shots.filter { $0.render != nil }.count
        if command == "check" {
            print(changed.isEmpty ? "check: all \(total) pictures are as drawn"
                                  : "check: \(changed.count) of \(total) pictures differ from the drawing; `shots-kit update` copies the drawings")
            return missing.isEmpty ? (changed.isEmpty ? 0 : 1) : 2
        }
        print(changed.isEmpty ? "update: all \(total) pictures were as drawn" : "update: redrew \(changed.count) of \(total)")
        return missing.isEmpty ? 0 : 2
    }

    /// Runs `argv` in `dir`, stopped after `limit` seconds; throws with the end of
    /// its output when it fails.
    static func runCommand(_ argv: [String], in dir: URL, limit: TimeInterval, what: String) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = argv
        p.currentDirectoryURL = dir
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        try p.run()
        let timer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + limit, execute: timer)
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        p.waitUntilExit()
        timer.cancel()
        if p.terminationReason == .uncaughtSignal, p.terminationStatus == SIGTERM {
            throw Failure("\(what) took more than \(Int(limit / 60)) minutes, so it was stopped")
        }
        guard p.terminationStatus == 0 else {
            let tail = output.split(separator: "\n", omittingEmptySubsequences: false).suffix(20).joined(separator: "\n")
            throw Failure("\(what) failed (exit \(p.terminationStatus)):\n\(tail)")
        }
    }

    /// How a drawing differs from its picture, or nil when it doesn't.
    static func compare(_ drawn: URL, _ picture: URL) -> String? {
        guard let a = try? Data(contentsOf: drawn) else { return "no drawing" }
        guard let b = try? Data(contentsOf: picture) else { return "a new picture" }
        if a == b { return nil }
        guard let x = pixels(a) else { return "the drawing isn't an image" }
        guard let y = pixels(b) else { return "the picture isn't an image" }
        if x.width != y.width || x.height != y.height {
            return "its size, \(y.width)×\(y.height) to \(x.width)×\(x.height) pixels"
        }
        // The same pixels written differently (another PNG encoder) aren't a change.
        var count = 0, minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
        for row in 0..<x.height {
            for col in 0..<x.width {
                let i = (row * x.width + col) * 4
                var differs = false
                for k in 0..<4 where abs(Int(x.bytes[i + k]) - Int(y.bytes[i + k])) > 2 { differs = true; break }
                guard differs else { continue }
                count += 1
                minX = min(minX, col); maxX = max(maxX, col); minY = min(minY, row); maxY = max(maxY, row)
            }
        }
        guard count > 0 else { return nil }
        return "\(count) pixels differ, within \(maxX - minX + 1)×\(maxY - minY + 1) at (\(minX), \(minY)) of \(x.width)×\(x.height)"
    }

    /// An image's pixels as sRGB RGBA, 8 bits each.
    static func pixels(_ data: Data) -> (width: Int, height: Int, bytes: [UInt8])? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let w = image.width, h = image.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return drawn ? (w, h, bytes) : nil
    }
}
