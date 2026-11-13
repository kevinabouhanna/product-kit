import SwiftUI

// A tiny iPhone and iPad app for product-kit's tests (#43): a title, a time that changes by
// itself, a setting, a list of rows whose length is data, and, when launched with
// `-extra <title>`, one more button: a change to its interface. In English and Arabic, which is
// written right to left (#41).
@main
struct ShotsTestApp: App {
    var body: some Scene {
        WindowGroup { Home() }
    }
}

struct Home: View {
    @State private var sync = true
    private let rows = Int(UserDefaults.standard.string(forKey: "rows") ?? "") ?? 3
    private let extra = UserDefaults.standard.string(forKey: "extra")

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Updated \(Date.now.formatted(date: .omitted, time: .shortened))")
                    Toggle(String(localized: "Sync"), isOn: $sync)
                    Text(String(localized: "Items")).font(.headline)
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(0..<rows, id: \.self) { i in Text("\(String(localized: "Item")) \(i + 1)") }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("rows")
                    if let extra { Button(extra) {} }
                }
                .padding()
            }
            .navigationTitle(String(localized: "Home"))
        }
    }
}
