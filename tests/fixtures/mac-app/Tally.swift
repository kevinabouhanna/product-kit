import AppKit
import SwiftUI

// A tiny Mac app for product-kit's end-to-end test (#47): one window, in English and French,
// that draws its own pictures out of sight (`--snapshot <folder>`), from made-up data, as
// claude-profiles-mac does.
let words: [String: [String: String]] = [
    "en": ["title": "Tally", "today": "Today", "count": "Count"],
    "fr": ["title": "Tally", "today": "Aujourd’hui", "count": "Compter"],
]

struct Window: View {
    let language: String
    var body: some View {
        let w = words[language] ?? words["en"]!
        VStack(alignment: .leading, spacing: 12) {
            Text(w["title"]!).font(.title).bold()
            Text("\(w["today"]!): 12")
            Button(w["count"]!) {}
        }
        .padding(24)
        .frame(width: 320, height: 180, alignment: .topLeading)
        .background(Color.white)
    }
}

@main
struct Tally {
    @MainActor static func main() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else {
            print("Tally: --snapshot <folder> draws its pictures")
            return
        }
        let folder = URL(fileURLWithPath: args[i + 1])
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (language, name) in [("en", "home.png"), ("fr", "home-fr.png")] {
            let renderer = ImageRenderer(content: Window(language: language))
            renderer.scale = 2
            guard let image = renderer.cgImage,
                  let dest = CGImageDestinationCreateWithURL(folder.appendingPathComponent(name) as CFURL, "public.png" as CFString, 1, nil)
            else { continue }
            CGImageDestinationAddImage(dest, image, nil)
            CGImageDestinationFinalize(dest)
        }
    }
}
