// shots-kit, the macOS driver: an app's windows through Accessibility and ScreenCaptureKit (product-kit#35). The files are one program: `shots-kit` builds
// them together, and `shots-kit vendor` writes them into one file for a project's CI.

import AppKit
import AVFoundation
import ApplicationServices
import CryptoKit
import ScreenCaptureKit

// MARK: - Accessibility

func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
    var value: AnyObject?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}

/// An app's accessibility element, read as any other element (product-kit#35).
struct AXNode: UIElement {
    let ax: AXUIElement

    func text(_ name: String) -> String? {
        switch attribute(ax, name) {
        case let s as String: return s.isEmpty ? nil : s
        case let n as NSNumber: return n.stringValue
        default: return nil
        }
    }

    var frame: CGRect? {
        guard let p = attribute(ax, kAXPositionAttribute), let s = attribute(ax, kAXSizeAttribute) else { return nil }
        var origin = CGPoint.zero, size = CGSize.zero
        AXValueGetValue(p as! AXValue, .cgPoint, &origin)
        AXValueGetValue(s as! AXValue, .cgSize, &size)
        return CGRect(origin: origin, size: size)
    }

    var children: [AXNode] { (attribute(ax, kAXChildrenAttribute) as? [AXUIElement] ?? []).map(AXNode.init) }
}

// The masked tree's functions, on an app's accessibility elements as they are.
func text(_ element: AXUIElement, _ name: String) -> String? { AXNode(ax: element).text(name) }
func children(_ element: AXUIElement) -> [AXUIElement] { AXNode(ax: element).children.map(\.ax) }
func frame(_ element: AXUIElement) -> CGRect? { AXNode(ax: element).frame }
func role(_ element: AXUIElement) -> String { role(AXNode(ax: element)) }
func labels(_ element: AXUIElement) -> [String] { labels(AXNode(ax: element)) }
func matches(_ element: AXUIElement, _ spec: String) -> Bool { matches(AXNode(ax: element), spec) }
func find(_ spec: String, in element: AXUIElement) -> AXUIElement? { find(spec, in: AXNode(ax: element))?.ax }
func line(_ element: AXUIElement) -> String { line(AXNode(ax: element)) }
func showsData(_ element: AXUIElement) -> Bool { showsData(AXNode(ax: element)) }
func tree(_ window: AXUIElement, data: [DataRegion], ignore: [String] = [],
          masked: ((AXUIElement) -> Void)? = nil) -> [String] {
    tree(AXNode(ax: window), data: data, ignore: ignore, masked: masked.map { told in { told($0.ax) } })
}

func find(_ role: String, in element: AXUIElement, subrole: String) -> AXUIElement? {
    children(element).first { text($0, kAXRoleAttribute) == role && text($0, kAXSubroleAttribute) == subrole }
}

func parent(of element: AXUIElement) -> AXUIElement? {
    attribute(element, kAXParentAttribute).map { $0 as! AXUIElement }
}

// MARK: - The look (NetworkMonitor#423)

/// What a window looks like, for what its tree can't tell: a colour, an icon,
/// spacing, a font. A small thumbnail of its picture, its average colour in
/// each cell of a grid `Look.across` cells along its longer side, five bits a
/// channel, kept as `shots/trees/<name>.look`. Cells over anything the tree
/// masks (data, a number, a setting's value, a line it leaves out) are left
/// out, `----`.
struct Look {
    /// The picture's size in pixels, and the grid's in cells.
    var width: Int, height: Int, columns: Int, rows: Int
    /// Each cell's colour, five bits a channel, red highest; nil where masked.
    var cells: [UInt16?]

    static let across = 128

    /// `masks` in the picture's pixels, from its top left.
    init?(_ image: CGImage, masks: [CGRect]) {
        let width = image.width, height = image.height
        let cell = max(1, Int((Double(max(width, height)) / Double(Look.across)).rounded(.up)))
        let columns = (width + cell - 1) / cell, rows = (height + cell - 1) / cell
        (self.width, self.height, self.columns, self.rows) = (width, height, columns, rows)
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: bytesPerRow, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        var cells: [UInt16?] = []
        for row in 0..<rows {
            for column in 0..<columns {
                let r = CGRect(x: column * cell, y: row * cell, width: cell, height: cell).intersection(bounds)
                if masks.contains(where: { $0.intersects(r) }) { cells.append(nil); continue }
                var sum = (0, 0, 0), n = 0
                // The buffer's rows run from the top, as the picture's do.
                for y in Int(r.minY)..<Int(r.maxY) {
                    for x in Int(r.minX)..<Int(r.maxX) {
                        let i = y * bytesPerRow + x * 4
                        sum.0 += Int(pixels[i]); sum.1 += Int(pixels[i + 1]); sum.2 += Int(pixels[i + 2]); n += 1
                    }
                }
                let level = { (v: Int) in UInt16((Double(v) / Double(max(n, 1)) / 255 * 31).rounded()) }
                cells.append(level(sum.0) << 10 | level(sum.1) << 5 | level(sum.2))
            }
        }
        self.cells = cells
    }

    init?(text: String) {
        var lines = text.split(separator: "\n").map(String.init)
        guard !lines.isEmpty else { return nil }
        let head = lines.removeFirst().split(separator: " ").compactMap { Int($0) }
        guard head.count == 4 else { return nil }
        (width, height, columns, rows) = (head[0], head[1], head[2], head[3])
        // Four hex digits a cell, a row a line.
        cells = lines.flatMap { line in
            stride(from: 0, to: line.count, by: 4).map { i -> UInt16? in
                let start = line.index(line.startIndex, offsetBy: i)
                return UInt16(line[start..<line.index(start, offsetBy: 4)], radix: 16)
            }
        }
        guard cells.count == columns * rows else { return nil }
    }

    var text: String {
        "\(width) \(height) \(columns) \(rows)\n" + (0..<rows).map { row in
            cells[(row * columns)..<((row + 1) * columns)]
                .map { $0.map { String(format: "%04x", $0) } ?? "----" }.joined()
        }.joined(separator: "\n") + "\n"
    }

    /// A cell differs when a channel is off by more than this many levels of
    /// 32: one level is a colour on a level's edge (NetworkMonitor#423).
    static let tolerance = 1

    /// How many cells may differ before the window is named. On real
    /// captures hours apart none did; an 8-point icon in another colour
    /// changes 2, a 16-point one 6, a line moved by 2 points over a hundred
    /// (product-kit docs/shots-kit.md).
    static let threshold = 1

    /// The cells, masked in neither, whose colour differs; nil when the
    /// pictures aren't the same size.
    func differing(from other: Look) -> (count: Int, of: Int)? {
        guard width == other.width, height == other.height, cells.count == other.cells.count else { return nil }
        var count = 0, of = 0
        for (a, b) in zip(cells, other.cells) {
            guard let a, let b else { continue }
            of += 1
            let channels = [(a >> 10, b >> 10), ((a >> 5) & 31, (b >> 5) & 31), (a & 31, b & 31)]
            if channels.contains(where: { abs(Int($0.0) - Int($0.1)) > Look.tolerance }) { count += 1 }
        }
        return (count, of)
    }
}

/// Whether `check` compares looks too (`--look`): it needs the windows in
/// front, so it's asked for; `update` always does.
nonisolated(unsafe) var compareLooks = false

/// How long a run may wait, silently, for the Mac to be left idle or locked
/// before it takes what needs the real screen (`--wait-away MINUTES`, NetworkMonitor#521).
/// None by default: those shots are reported as not taken.
nonisolated(unsafe) var waitAway: Double = 0

/// What the tree masks in `window`, in screen points: each element's frame.
func maskedFrames(_ window: AXUIElement, _ shot: Shot) -> [CGRect] {
    var frames: [CGRect] = []
    _ = tree(window, data: shot.data ?? [], ignore: shot.ignore ?? []) { element in
        if let f = frame(element) { frames.append(f) }
    }
    return frames
}

// MARK: - The screens

/// The screen every window is read and taken on (NetworkMonitor#487): the built-in Retina
/// display, or another Retina one; nil without one. The pictures are 2x, so
/// it's a Retina screen; it's the same whichever screen is the main one.
func stage() -> NSScreen? {
    let retina = NSScreen.screens.filter { $0.backingScaleFactor >= 2 }
    let builtIn = retina.first { screen in
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
            .map { CGDisplayIsBuiltin($0.uint32Value) != 0 } ?? false
    }
    return builtIn ?? retina.first
}

/// Where the app keeps its windows (`NSWindow Frame Main`): a run moves them
/// onto the stage, and puts them back once the app has quit, so the
/// person's window opens where they left it.
struct SavedFrames {
    let bundle: CFString
    let frames: [String: CFPropertyList]

    init(bundle: String) {
        self.bundle = bundle as CFString
        CFPreferencesAppSynchronize(self.bundle)
        let keys = CFPreferencesCopyKeyList(self.bundle, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? [String] ?? []
        var frames: [String: CFPropertyList] = [:]
        for key in keys where key.hasPrefix("NSWindow Frame ") {
            frames[key] = CFPreferencesCopyAppValue(key as CFString, self.bundle)
        }
        self.frames = frames
    }

    /// Only once the app has quit, or it would write its own over them.
    func restore() {
        CFPreferencesAppSynchronize(bundle)
        let now = CFPreferencesCopyKeyList(bundle, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? [String] ?? []
        for key in Set(now.filter { $0.hasPrefix("NSWindow Frame ") }).union(frames.keys) {
            CFPreferencesSetAppValue(key as CFString, frames[key], bundle)
        }
        CFPreferencesAppSynchronize(bundle)
    }
}

/// Kept for the run: each puts the app back on a signal.
nonisolated(unsafe) var signalSources: [DispatchSourceSignal] = []

/// When this run last clicked with the real pointer: that click counts as input.
nonisolated(unsafe) var lastOwnInput: Date?

/// Seconds since anyone used the keyboard or mouse; infinite while the screen is locked.
func secondsIdle() -> Double {
    if let session = CGSessionCopyCurrentDictionary() as? [String: Any],
       session["CGSSessionScreenIsLocked"] as? Bool == true { return .infinity }
    let idle = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: CGEventType(rawValue: ~0)!)
    // No input since this run's own click, which it made only while the Mac was idle.
    if let last = lastOwnInput, idle >= Date().timeIntervalSince(last) - 1 { return .infinity }
    return idle
}

/// How long the Mac has to have been left alone before a run takes focus or
/// moves the pointer (NetworkMonitor#475): MAC_LANE_IDLE seconds (90) with no keyboard or
/// mouse, or the screen locked. MAC_LANE_IDLE=0 takes them whenever.
let awayAfter = Double(ProcessInfo.processInfo.environment["MAC_LANE_IDLE"] ?? "") ?? 90

func isAway() -> Bool { awayAfter <= 0 || secondsIdle() >= awayAfter }

/// A shot that needs a window brought forward or a real click while someone
/// is at the Mac. It isn't waited for there, with the lanes held (NetworkMonitor#504): the run
/// reads every other window first, lets the lanes go, waits until the Mac is idle, and takes them again for these.
struct NeedsAway: Error { let what: String }

/// Before taking focus or moving the pointer.
func needAway(_ what: String) throws {
    if !isAway() { throw NeedsAway(what: what) }
}

// MARK: - Recording a window (product-kit#65)

/// Writes what a ScreenCaptureKit stream shows to an MP4, frame by frame, as they come.
final class WindowRecording: NSObject, SCStreamOutput, @unchecked Sendable {
    let writer: AVAssetWriter
    let input: AVAssetWriterInput
    private var started = false
    private var frames = 0

    init(to url: URL, width: Int, height: Int) throws {
        try? FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height])
        input.expectsMediaDataInRealTime = true
        writer.add(input)
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, buffer.isValid,
              let info = (CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]])?.first,
              let raw = info[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete else { return }
        if !started {
            writer.startWriting()
            writer.startSession(atSourceTime: buffer.presentationTimeStamp)
            started = true
        }
        if input.isReadyForMoreMediaData, input.append(buffer) { frames += 1 }
    }

    func finish() async throws {
        guard started, frames > 0 else { throw Failure("the recording caught no frames of the window") }
        input.markAsFinished()
        await writer.finishWriting()
        if writer.status != .completed { throw Failure("the video wasn't written: \(writer.error?.localizedDescription ?? "?")") }
    }
}

/// A still from a video, as a JPEG or PNG by its name (product-kit#65): a video's poster.
func poster(of video: URL, at seconds: Double, to url: URL) async throws {
    let generator = AVAssetImageGenerator(asset: AVURLAsset(url: video))
    generator.appliesPreferredTrackTransform = true
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero
    let (image, _) = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600))
    let kind = url.pathExtension.lowercased() == "png" ? "public.png" : "public.jpeg"
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, kind as CFString, 1, nil) else { throw Failure("can't write \(url.path)") }
    CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.88] as CFDictionary)
    guard CGImageDestinationFinalize(dest) else { throw Failure("can't write \(url.path)") }
}

// MARK: - Launching

/// The app's launch jobs in launchd (`application.<bundle>.<n>.<n>`), with
/// each one's process, or nil for a job left with none (NetworkMonitor#508).
func launchJobs(_ bundle: String) -> [(label: String, pid: Int32?)] {
    runTool("/bin/launchctl", ["list"]).output.split(separator: "\n").compactMap { line in
        let f = line.split(whereSeparator: { $0 == "\t" || $0 == " " })
        guard f.count >= 3, f[2].hasPrefix("application.\(bundle).") else { return nil }
        return (String(f[2]), Int32(f[0]))
    }
}

/// Opens the app in the background (-g). Started straight after a quit, while
/// launchd still has the last launch's job, `open` fails with launchd's error
/// 37, "Operation already in progress" (NetworkMonitor#508): then it removes that job, the
/// one with no process, and tries once more, saying so.
func openApp(_ path: String, bundle: String, _ arguments: [String], until started: () -> Bool) throws {
    var removed = false, last = ""
    for attempt in 1...4 {
        let open = runTool("/usr/bin/open", ["-g", "-a", path] + (arguments.isEmpty ? [] : ["--args"] + arguments))
        if open.status == 0 {
            for _ in 0..<40 where !started() { usleep(250_000) }
            if started() { return }
        }
        last = open.output.trimmingCharacters(in: .whitespacesAndNewlines)
        if open.output.contains("Code=37"), !removed {
            removed = true
            let dead = launchJobs(bundle).filter { $0.pid == nil }
            for job in dead {
                let r = runTool("/bin/launchctl", ["remove", job.label])
                print("  launchd still had \(job.label) from the last launch, with no process: "
                      + (r.status == 0 ? "removed it" : "couldn't remove it (\(r.output.trimmingCharacters(in: .whitespacesAndNewlines)))"))
            }
            print("  opening \(path) again")
            continue
        }
        if attempt >= 3 { break }
        sleep(2)
    }
    throw Failure("\(path) didn't start" + (last.isEmpty ? "" : ": \(last)"))
}

// MARK: - The Mac lanes

/// The Mac as a run uses it (NetworkMonitor#504, NetworkMonitor#506). The app's lane and `screen`
/// lanes are held only while it reads or takes windows, never while it waits
/// for the Mac to be idle (NetworkMonitor#521). Letting them go puts the app back: every copy quit,
/// its windows' frames back where they were, and the installed copy
/// running again if it was when they were taken, whichever copy the run used
/// (`--app`).
final class Mac: @unchecked Sendable {
    let manifest: Manifest
    let installed: Manifest
    let command: String
    private var lanes: Process?
    private var lanesInput: Pipe?
    private var lanesHeld = false
    private var savedFrames: SavedFrames?
    private var installedWasRunning = false
    private let lock = NSLock()

    init(manifest: Manifest, installed: Manifest, command: String) {
        self.manifest = manifest; self.installed = installed; self.command = command
    }

    var holding: Bool { lock.withLock { savedFrames != nil } }

    /// Lanes a caller holds already (`mac-lane build/site-shots …`) stay held
    /// until it's done, waits included.
    var callerHolds: Bool {
        let held = (ProcessInfo.processInfo.environment["MAC_LANE_HELD"] ?? "").split(separator: " ").map(String.init)
        return held.contains(lane) && held.contains("screen")
    }

    /// The app's lane: the config's, or its bundle id's last part, lowercased.
    var lane: String {
        config.lane ?? (manifest.bundle.split(separator: ".").last.map { $0.lowercased() } ?? "app")
    }

    /// Takes both lanes, waiting for whoever holds them, and notes how the app is.
    func hold(_ what: String) throws {
        guard !holding else { return }
        if !callerHolds { try takeLanes(what) }
        lock.withLock {
            let path = URL(fileURLWithPath: installed.app).resolvingSymlinksInPath().path
            installedWasRunning = NSRunningApplication.runningApplications(withBundleIdentifier: installed.bundle)
                .contains { $0.bundleURL?.resolvingSymlinksInPath().path == path }
            savedFrames = SavedFrames(bundle: manifest.bundle)
        }
    }

    /// Puts the app back as it was, then lets the lanes go.
    func letGo() {
        let (frames, reopen): (SavedFrames?, Bool) = lock.withLock {
            defer { savedFrames = nil }
            return (savedFrames, installedWasRunning)
        }
        guard let frames else { return }
        Session(manifest: manifest).quit()
        // Its windows back where they were, once it has quit (NetworkMonitor#487).
        frames.restore()
        if reopen {
            do {
                let app = installed
                try openApp(app.app, bundle: app.bundle, []) {
                    !NSRunningApplication.runningApplications(withBundleIdentifier: app.bundle).isEmpty
                }
            } catch { print("shots-kit: couldn't open the installed app again: \(error)") }
        }
        releaseLanes()
    }

    /// Waits silently, with the lanes free, until the Mac happens to be idle
    /// (NetworkMonitor#521): nobody is ever told or asked to step away. Then takes them for what
    /// needs him away; again if he came back while they were busy. Gives up at
    /// `deadline`, returning false, with the lanes free.
    func holdOnceAway(_ what: String, until deadline: Date) throws -> Bool {
        if callerHolds { print("  (the lanes stay held meanwhile: the command that ran this holds them)") }
        while true {
            while !isAway() {
                if Date() >= deadline { return false }
                sleep(5)
            }
            try hold(what)
            if isAway() { return true }
            // Back while the lanes were busy: let them go again, the app untouched.
            lock.withLock { savedFrames = nil }
            releaseLanes()
        }
    }

    /// Both lanes, held by a `mac-lane` that runs until this run closes its
    /// input, or ends: the lanes go with it however it ends.
    private func takeLanes(_ what: String) throws {
        // The project's fallback copy, where it has one; the shared one otherwise.
        let repoCopy = repoRoot.appendingPathComponent("Scripts/mac-lane.sh").standardizedFileURL.path
        let macLane = FileManager.default.isExecutableFile(atPath: repoCopy) ? repoCopy : "mac-lane"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["MAC_LANE=\(lane)", "MAC_LANE_WHAT=shots-kit \(command): \(what)", macLane,
                       "env", "MAC_LANE=screen", macLane, "/bin/sh", "-c", "echo held; exec cat >/dev/null"]
        var env = ProcessInfo.processInfo.environment
        env["MAC_LANE_IDLE"] = nil   // this run waits for the Mac to be idle itself, with the lanes free
        p.environment = env
        let input = Pipe(), output = Pipe()
        p.standardInput = input
        p.standardOutput = output
        try p.run()
        lock.withLock { lanes = p; lanesInput = input; lanesHeld = false }
        var said = Data()
        while !String(decoding: said, as: UTF8.self).contains("held") {
            let more = output.fileHandleForReading.availableData
            if more.isEmpty { break }
            said += more
        }
        guard String(decoding: said, as: UTF8.self).contains("held") else {
            p.waitUntilExit()
            lock.withLock { lanes = nil; lanesInput = nil }
            throw Failure("couldn't take the \(lane) and screen Mac lanes (mac-lane exited \(p.terminationStatus))")
        }
        lock.withLock { lanesHeld = true }
    }

    private func releaseLanes() {
        let (p, input, held): (Process?, Pipe?, Bool) = lock.withLock {
            defer { lanes = nil; lanesInput = nil }
            return (lanes, lanesInput, lanesHeld)
        }
        try? input?.fileHandleForWriting.close()
        // Still waiting for them: it ignores the signals this run does.
        if let p, !held, p.isRunning { kill(p.processIdentifier, SIGKILL) }
        p?.waitUntilExit()
    }

    /// However the run ends: the app put back, the lanes let go, a wait for
    /// them given up.
    func end() {
        letGo()
        releaseLanes()
    }
}

// MARK: - The app

struct Session {
    let manifest: Manifest
    /// Opens windows behind the others without activating the app (the
    /// config's `launch.background`, NetworkMonitor#475), for commands that only read the tree.
    var background = false

    var running: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: manifest.bundle).first
    }

    /// Quits every copy, the installed one and a development build alike: they
    /// share settings. Gracefully, then waits until launchd has let go of each
    /// one's launch job, or opening it again can fail (NetworkMonitor#508).
    func quit() {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: manifest.bundle)
        guard !apps.isEmpty else { return }
        apps.forEach { $0.terminate() }
        for _ in 0..<80 where apps.contains(where: { !$0.isTerminated }) { usleep(250_000) }
        for app in apps where !app.isTerminated { app.forceTerminate(); usleep(500_000) }
        for _ in 0..<60 where !launchJobs(manifest.bundle).isEmpty { usleep(250_000) }
        usleep(500_000)
    }

    func launch(_ arguments: [String]) throws {
        quit()
        // -g: never brings the app forward by itself (NetworkMonitor#475).
        try openApp(manifest.app, bundle: manifest.bundle, arguments + (background ? config.background : [])) { running != nil }
    }

    func window(_ title: String) throws -> AXUIElement {
        guard let app = running else { throw Failure("the app isn't running") }
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        for _ in 0..<60 {
            var windows = attribute(ax, kAXWindowsAttribute) as? [AXUIElement] ?? []
            // The menu bar readout isn't in a window: it's the app's status
            // item, `AXMenuBarItem` in its extras menu bar (NetworkMonitor#424).
            if let extras = attribute(ax, kAXExtrasMenuBarAttribute) { windows.append(extras as! AXUIElement) }
            let found = title.hasPrefix("AX") ? windows.lazy.compactMap { find(title, in: $0) }.first
                : windows.first { (text($0, kAXTitleAttribute) ?? "") == title }
            if let w = found {
                usleep(1_500_000)   // let it lay out and load
                return w
            }
            usleep(250_000)
        }
        throw Failure("no window \"\(title)\"")
    }

    func bringForward(_ window: AXUIElement) throws {
        try needAway("its window brought forward")
        guard let app = running else { return }
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        for _ in 0..<3 {
            AXUIElementSetAttributeValue(ax, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
            AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            usleep(300_000)
        }
    }

    /// A click on the element, as a person would: SwiftUI's disclosure rows
    /// offer no accessibility action.
    func click(_ spec: String, in window: AXUIElement) throws {
        guard let element = appear(spec, in: window), let f = frame(element) else { throw Failure("nothing matches \(spec)") }
        // A click that lands while another app is in front only brings the
        // window forward. Where the element has a value, such as a disclosure
        // row's open or closed, try again until it changes.
        let before = text(element, kAXValueAttribute)
        // A button presses through accessibility, with no pointer involved,
        // which would close a popover by landing outside it.
        var actions: CFArray?
        AXUIElementCopyActionNames(element, &actions)
        if (actions as? [String] ?? []).contains(kAXPressAction),
           AXUIElementPerformAction(element, kAXPressAction as CFString) == .success {
            usleep(1_200_000)
            if before == nil || text(element, kAXValueAttribute) != before { return }
        }
        try needAway("a click")
        for _ in 0..<4 {
            try bringForward(window)
            let point = CGPoint(x: f.minX + min(40, f.width / 2), y: f.midY)
            let saved = CGEvent(source: nil)?.location
            for type in [CGEventType.leftMouseDown, .leftMouseUp] {
                CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
                usleep(60_000)
            }
            lastOwnInput = Date()
            if let saved { CGWarpMouseCursorPosition(saved) }
            usleep(1_200_000)
            if before == nil || text(element, kAXValueAttribute) != before { return }
        }
        throw Failure("clicking \(spec) didn't change it")
    }

    /// Scrolls a list to its end, as far down as it goes.
    func scrollToEnd(_ spec: String, in window: AXUIElement) throws {
        guard let area = appear(spec, in: window) else { throw Failure("nothing matches \(spec)") }
        // A list short enough to show whole has no scroll bar, and is at its end.
        guard let bar = attribute(area, kAXVerticalScrollBarAttribute).map({ $0 as! AXUIElement }) else { return }
        AXUIElementSetAttributeValue(bar, kAXValueAttribute as CFString, 1.0 as CFNumber)
        usleep(800_000)
    }

    /// The element, once it's there: a popover's rows arrive with the first
    /// sample, a moment after it opens.
    func appear(_ spec: String, in window: AXUIElement, seconds: Double = 15) -> AXUIElement? {
        let deadline = Date().addingTimeInterval(seconds)
        repeat {
            if let found = find(spec, in: window) { usleep(500_000); return found }
            usleep(300_000)
        } while Date() < deadline
        return nil
    }

    func wait(for wait: Wait, in window: AXUIElement) throws {
        let deadline = Date().addingTimeInterval(wait.seconds)
        while Date() < deadline {
            if find(wait.element, in: window) != nil { usleep(800_000); return }
            usleep(500_000)
        }
        // What it showed instead, to tell a slow window from a wrong spec.
        let showing = tree(window, data: []).prefix(30).joined(separator: "\n")
        throw Failure("\(wait.element) didn't appear within \(Int(wait.seconds)) s; the window showed:\n\(showing)")
    }

    /// Puts a window in one place before it's read or taken (NetworkMonitor#487): on the
    /// stage screen, `stage()`, 60 points from its visible frame's left and 40
    /// from its top. A window lays out to whole points on a 1x screen and to
    /// half points on a Retina one, so a toolbar segment 37.5 points wide on
    /// one is 38 on the other and rounds to another size; and a translucent
    /// sidebar shows what's behind it. Where the window last was, or which
    /// screen is the main one, changes neither. A popover and the menu bar
    /// readout stay where they are: the popover opens on the Retina screen
    /// itself (`-popoverScreen retina`).
    func place(_ window: AXUIElement) {
        guard role(window) == "AXWindow", let f = frame(window), let screen = stage() else { return }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        // In screen points from the top left, as accessibility has them.
        let visible = CGRect(x: screen.visibleFrame.minX, y: primaryHeight - screen.visibleFrame.maxY,
                             width: screen.visibleFrame.width, height: screen.visibleFrame.height)
        var to = CGPoint(x: visible.minX + max(0, min(60, visible.width - f.width)),
                         y: visible.minY + max(0, min(40, visible.height - f.height)))
        guard f.origin != to, let value = AXValueCreate(.cgPoint, &to) else { return }
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
        // It lays out again for the new screen's scale.
        usleep(800_000)
    }

    func capture(_ window: AXUIElement, crop: Crop?) async throws -> CGImage {
        try await picture(window, crop: crop).image
    }

    /// A capture, with where its top left is on screen and its points to
    /// pixels: to place the masks of the look check on it (NetworkMonitor#423).
    /// The window as ScreenCaptureKit has it: a window by its frame; a popover by the smallest
    /// window around it, which is larger for the arrow and the shadow.
    func capturable(_ window: AXUIElement) async throws -> SCWindow {
        guard let app = running, let f = frame(window) else { throw Failure("no window to capture") }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let candidates = content.windows.filter { $0.owningApplication?.processID == app.processIdentifier }
        let exact = candidates.min(by: { distance($0.frame, f) < distance($1.frame, f) }).flatMap { distance($0.frame, f) < 4 ? $0 : nil }
        let around = candidates.filter { $0.frame.insetBy(dx: -1, dy: -1).contains(f) }
            .min(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height })
        guard let target = exact ?? around else { throw Failure("can't find the window on screen") }
        return target
    }

    /// A video of the window (product-kit#65): `seconds` of it, recorded with ScreenCaptureKit,
    /// while `actions` (the shot's clicks) run, written as an H.264 MP4.
    func record(_ window: AXUIElement, to url: URL, seconds: Double, during actions: () throws -> Void) async throws {
        let target = try await capturable(window)
        let width = Int(target.frame.width * 2) & ~1, height = Int(target.frame.height * 2) & ~1
        let config = SCStreamConfiguration()
        config.width = width
        config.height = height
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        let recording = try WindowRecording(to: url, width: width, height: height)
        let stream = SCStream(filter: SCContentFilter(desktopIndependentWindow: target), configuration: config, delegate: nil)
        try stream.addStreamOutput(recording, type: .screen, sampleHandlerQueue: DispatchQueue(label: "shots-kit.recording"))
        try await stream.startCapture()
        let start = Date()
        do { try actions() } catch {
            try? await stream.stopCapture()
            throw error
        }
        let left = seconds - Date().timeIntervalSince(start)
        if left > 0 { try await Task.sleep(nanoseconds: UInt64(left * 1_000_000_000)) }
        try await stream.stopCapture()
        try await recording.finish()
    }

    func picture(_ window: AXUIElement, crop: Crop?) async throws -> (image: CGImage, origin: CGPoint, scale: CGFloat) {
        let target = try await capturable(window)
        let config = SCStreamConfiguration()
        config.width = Int(target.frame.width * 2)
        config.height = Int(target.frame.height * 2)
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        let image = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: target),
                                                               configuration: config)
        guard let crop else { return (image, target.frame.origin, 2) }
        let r = try crop.rect(in: window)
        let rect = CGRect(x: (r.minX * 2).rounded(), y: (r.minY * 2).rounded(), width: (r.width * 2).rounded(), height: (r.height * 2).rounded())
        guard let cropped = image.cropping(to: rect) else { throw Failure("crop is outside the window") }
        return (cropped, CGPoint(x: target.frame.minX + r.minX, y: target.frame.minY + r.minY), 2)
    }

    /// The window as it looks now, active, with the tree's masks laid on it.
    func look(_ window: AXUIElement, _ shot: Shot) async throws -> (look: Look, picture: CGImage, masks: [CGRect]) {
        place(window)
        var picture = try await picture(window, crop: shot.crop)
        for attempt in 0..<8 where shot.crop == nil && !isActive(picture.image, window: window) {
            InVM.allowSystemAlert()
            try bringForward(window)
            // Longer each time: something else can hold the front for a few seconds.
            if attempt >= 3 { usleep(UInt32(attempt) * 400_000) }
            picture = try await self.picture(window, crop: shot.crop)
        }
        let masks = maskedFrames(window, shot).map { f in
            CGRect(x: (f.minX - picture.origin.x) * picture.scale, y: (f.minY - picture.origin.y) * picture.scale,
                   width: f.width * picture.scale, height: f.height * picture.scale)
        }
        guard let look = Look(picture.image, masks: masks) else { throw Failure("can't read the capture's colours") }
        return (look, picture.image, masks)
    }

    func distance(_ a: CGRect, _ b: CGRect) -> CGFloat {
        abs(a.minX - b.minX) + abs(a.minY - b.minY) + abs(a.width - b.width) + abs(a.height - b.height)
    }
}

/// A capture of an inactive window has grey traffic lights; the active one's
/// close button is red.
func isActive(_ image: CGImage, window: AXUIElement) -> Bool {
    guard let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data),
          let w = frame(window), let close = find("AXButton", in: window, subrole: "AXCloseButton").flatMap(frame) else { return true }
    let x = Int((close.midX - w.minX) * 2), y = Int((close.midY - w.minY) * 2)
    guard x < image.width, y < image.height else { return true }
    let i = y * image.bytesPerRow + x * (image.bitsPerPixel / 8)
    let first = Int(bytes[i]), third = Int(bytes[i + 2])
    let red = image.bitmapInfo.contains(.byteOrder32Little) ? third : first
    let blue = image.bitmapInfo.contains(.byteOrder32Little) ? first : third
    return red > 180 && blue < 120
}
