// shots-kit, the masked tree: what a window says, as text, whatever drew it (product-kit#35). The files are one program: `shots-kit` builds
// them together, and `shots-kit vendor` writes them into one file for a project's CI.

import AppKit
import ApplicationServices
import CryptoKit
import ScreenCaptureKit

// MARK: - The masked tree

/// Roles whose value is the user's setting rather than interface.
let settingRoles: Set<String> = ["AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXSlider", "AXTextField",
                                 "AXTextArea", "AXComboBox", "AXDisclosureTriangle", "AXIncrementor", "AXValueIndicator"]

// MARK: - Elements, whatever drew them

/// An element of a window, whatever drew it (product-kit#35): an app's accessibility
/// element on the Mac (`AXUIElement`, the macOS driver), or one a driver describes as JSON
/// (`Described`: an iPhone app's, a web page's). Roles and attributes use the Mac's
/// accessibility names (`AXButton`, `AXStaticText`, `AXTitle`), so every driver's windows
/// read alike, and the manifest's specs (`Role:label`) mean the same for each.
protocol UIElement {
    /// An attribute's text, nil when there's none or it's empty: `AXRole`, `AXSubrole`,
    /// `AXTitle`, `AXDescription`, `AXValue`, `AXIdentifier`, `AXHelp`.
    func text(_ name: String) -> String?
    /// Where it is on the screen, in points.
    var frame: CGRect? { get }
    var children: [Self] { get }
}

func text<E: UIElement>(_ element: E, _ name: String) -> String? { element.text(name) }

func children<E: UIElement>(_ element: E) -> [E] { element.children }

func frame<E: UIElement>(_ element: E) -> CGRect? { element.frame }

func role<E: UIElement>(_ element: E) -> String { text(element, kAXRoleAttribute) ?? "?" }

func labels<E: UIElement>(_ element: E) -> [String] {
    [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute].compactMap { text(element, $0) }
}

/// `Role` or `Role:label`, where the label is the start of the element's
/// title, description or value. `find` also takes `Outer>Inner`: an Inner
/// inside an Outer.
func matches<E: UIElement>(_ element: E, _ spec: String) -> Bool {
    let parts = spec.split(separator: ":", maxSplits: 1).map(String.init)
    // `Role#identifier`: the element's accessibility identifier, the same in every language
    // (an iPhone app's usual way to name what tests find, product-kit#43).
    let head = parts[0].split(separator: "#", maxSplits: 1).map(String.init)
    guard role(element) == head[0] else { return false }
    if head.count == 2, text(element, kAXIdentifierAttribute) != head[1] { return false }
    guard parts.count == 2 else { return true }
    // `Role:~text` matches text anywhere in the label, for a line that starts
    // with a number.
    if parts[1].hasPrefix("~") { return labels(element).contains { $0.contains(parts[1].dropFirst()) } }
    return labels(element).contains { $0.hasPrefix(parts[1]) }
}

func find<E: UIElement>(_ spec: String, in element: E) -> E? {
    if let split = spec.range(of: ">") {
        guard let outer = find(String(spec[..<split.lowerBound]), in: element) else { return nil }
        return children(outer).lazy.compactMap { find(String(spec[split.upperBound...]), in: $0) }.first
    }
    if matches(element, spec) { return element }
    for child in children(element) {
        if let found = find(spec, in: child) { return found }
    }
    return nil
}

/// An element a driver describes, as JSON (product-kit#35): `role`, and any of `subrole`,
/// `title`, `description`, `value`, `identifier`, `help`, `frame` (`[x, y, width, height]`
/// in points) and `children`.
final class Described: UIElement, Decodable {
    let role: String
    let subrole, title, label, value, identifier, help: String?
    let rect: [Double]?
    let children: [Described]

    enum CodingKeys: String, CodingKey {
        case role, subrole, title, label = "description", value, identifier, help, rect = "frame", children
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        role = try c.decode(String.self, forKey: .role)
        subrole = try c.decodeIfPresent(String.self, forKey: .subrole)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        label = try c.decodeIfPresent(String.self, forKey: .label)
        // A value may be a number or a switch's state as well as text.
        if let s = try? c.decodeIfPresent(String.self, forKey: .value) { value = s }
        else if let n = try? c.decodeIfPresent(Double.self, forKey: .value) {
            value = n == n.rounded() && abs(n) < 1e15 ? String(Int(n)) : String(n)
        } else if let b = try? c.decodeIfPresent(Bool.self, forKey: .value) { value = b ? "1" : "0" }
        else { value = nil }
        identifier = try c.decodeIfPresent(String.self, forKey: .identifier)
        help = try c.decodeIfPresent(String.self, forKey: .help)
        rect = try c.decodeIfPresent([Double].self, forKey: .rect)
        children = try c.decodeIfPresent([Described].self, forKey: .children) ?? []
    }

    func text(_ name: String) -> String? {
        let found: String?
        switch name {
        case kAXRoleAttribute: found = role
        case kAXSubroleAttribute: found = subrole
        case kAXTitleAttribute: found = title
        case kAXDescriptionAttribute: found = label
        case kAXValueAttribute: found = value
        case kAXIdentifierAttribute: found = identifier
        case kAXHelpAttribute: found = help
        default: found = nil
        }
        return found?.isEmpty == true ? nil : found
    }

    var frame: CGRect? {
        guard let r = rect, r.count == 4 else { return nil }
        return CGRect(x: r[0], y: r[1], width: r[2], height: r[3])
    }
}

func rounded(_ v: CGFloat) -> Int { Int((v / 4).rounded()) * 4 }

/// One line per element: its role, its labels with numbers and dates masked,
/// and its size to the nearest 4 points. Positions are left out, since a list
/// above can push everything down; a text's width too, since a number's digits
/// change it.
func line<E: UIElement>(_ element: E) -> String {
    let r = role(element)
    var parts = [r]
    if let sub = text(element, kAXSubroleAttribute) { parts.append("(\(sub))") }
    for name in [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXIdentifierAttribute, kAXHelpAttribute] {
        if name == kAXValueAttribute && settingRoles.contains(r) { continue }
        if let s = text(element, name) { parts.append("\(name.dropFirst(2).lowercased())=\"\(mask(s))\"") }
    }
    if let f = frame(element) {
        let shown = settingRoles.contains(r) ? labels(element).dropLast(text(element, kAXValueAttribute) == nil ? 0 : 1) : labels(element)[...]
        let hasNumber = shown.contains { $0.rangeOfCharacter(from: .decimalDigits) != nil }
        // A role drawn at one width whatever it shows keeps its width, numbers
        // and all, so a change in it is its own (`shots.keep_width`; a menu-bar
        // readout, NetworkMonitor#424).
        let keepsWidth = config.keepWidth.contains(r)
        parts.append(!keepsWidth && (r == "AXStaticText" || hasNumber || containerRoles.contains(r))
                     ? "h\(rounded(f.height))" : "\(rounded(f.width))x\(rounded(f.height))")
    }
    return parts.joined(separator: " ")
}

/// The distinct roles in a region, however many rows it has.
func roles<E: UIElement>(in elements: [E]) -> [String] {
    var found = Set<String>()
    func walk(_ e: E) {
        found.insert(role(e) + (text(e, kAXSubroleAttribute).map { "(\($0))" } ?? ""))
        children(e).forEach(walk)
    }
    elements.forEach(walk)
    return found.sorted()
}

/// Containers keep their height only: a scroll bar that comes with a longer
/// list narrows every one of them by its width.
let containerRoles: Set<String> = ["AXGroup", "AXScrollArea", "AXOpaqueProviderGroup", "AXList"]

/// Roles left out altogether: a scroll bar comes and goes with a list's length.
let ignoredRoles: Set<String> = ["AXScrollBar"]

/// `masked` is told of each element whose looks the tree doesn't keep: data,
/// what's left out, a number or a date, a setting's value. The look check
/// leaves them out of the picture too (NetworkMonitor#423).
func tree<E: UIElement>(_ window: E, data: [DataRegion], ignore: [String] = [],
                         masked: ((E) -> Void)? = nil) -> [String] {
    var out: [String] = []
    /// Whether the element's subtree held a data region.
    @discardableResult
    func walk(_ element: E, _ depth: Int) -> Bool {
        let pad = String(repeating: "  ", count: depth)
        let index = out.count
        out.append(pad + line(element))
        if let masked, depth > 0, showsData(element) { masked(element) }
        let kids = children(element).filter { kid in
            let kept = !ignoredRoles.contains(role(kid)) && !ignore.contains { matches(kid, $0) }
            if !kept { masked?(kid) }
            return kept
        }
        var holdsData = false
        var i = 0
        while i < kids.count {
            if let region = data.first(where: { matches(kids[i], $0.from) }) {
                if let skip = region.skip, skip > 0 {
                    // The label itself stays interface.
                    for k in i..<min(i + skip, kids.count) { if walk(kids[k], depth + 1) { holdsData = true } }
                    i += skip
                    guard i < kids.count else {
                        if region.optional == true { out.append(pad + "  data: optional"); holdsData = true }
                        break
                    }
                }
                var end = i + 1
                if let until = region.until {
                    switch until {
                    case "end": end = kids.count
                    case "run": while end < kids.count && role(kids[end]) == role(kids[i]) { end += 1 }
                    default:    end = kids[(i + 1)...].firstIndex { matches($0, until) } ?? kids.count
                    }
                }
                if let masked { kids[i..<end].forEach(masked) }
                out.append(pad + "  data: " + (region.optional == true ? "optional"
                                               : roles(in: Array(kids[i..<end])).joined(separator: " ")))
                holdsData = true
                i = end
            } else {
                if walk(kids[i], depth + 1) { holdsData = true }
                i += 1
            }
        }
        // Whatever holds a data region grows with its rows: keep its width only.
        if holdsData {
            out[index] = out[index].replacingOccurrences(of: "(\\d+)x\\d+$", with: "$1", options: .regularExpression)
                .replacingOccurrences(of: " h\\d+$", with: "", options: .regularExpression)
        }
        return holdsData
    }
    walk(window, 0)
    return out
}

/// Whether an element shows what the tree masks in its labels: a number, a
/// date, a setting's value. A container's labels say nothing of its looks.
func showsData<E: UIElement>(_ element: E) -> Bool {
    let r = role(element)
    if containerRoles.contains(r) { return false }
    // A text area is the user's in Settings, but About's credits too: by
    // what it shows, as text is.
    if settingRoles.contains(r), r != "AXTextArea", text(element, kAXValueAttribute) != nil { return true }
    return labels(element).contains { mask($0) != $0.replacingOccurrences(of: "\n", with: " ") }
}
