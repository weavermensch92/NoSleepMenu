import AppKit

@MainActor
struct StatusPart {
    let text: String
    let logo: NSImage?
    let fallback: String
}

@MainActor
enum StatusImage {
    /// One image on ONE NSStatusItem keeps both providers adjacent when dragged.
    static func render(parts: [StatusPart], sleepEnabled: Bool) -> NSImage {
        guard !parts.isEmpty else {
            let image = NSImage(systemSymbolName: sleepEnabled ? "moon.zzz.fill" : "moon", accessibilityDescription: L("잠자기 방지"))!
            image.isTemplate = true
            return image
        }
        let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let widths = parts.map { part -> CGFloat in
            let textWidth = (part.text as NSString).size(withAttributes: attributes).width
            let logoWidth = part.logo == nil ? (part.fallback as NSString).size(withAttributes: attributes).width : 18
            return ceil(textWidth) + 4 + ceil(logoWidth)
        }
        let size = NSSize(width: widths.reduce(0, +) + CGFloat(parts.count - 1) * 12, height: 22)
        let image = NSImage(size: size, flipped: false) { _ in
            var x: CGFloat = 0
            for (index, part) in parts.enumerated() {
                let textSize = (part.text as NSString).size(withAttributes: attributes)
                (part.text as NSString).draw(at: NSPoint(x: x, y: floor((22 - textSize.height) / 2)), withAttributes: attributes)
                let iconX = x + ceil(textSize.width) + 4
                if let logo = part.logo {
                    logo.draw(in: NSRect(x: iconX, y: 2, width: 18, height: 18))
                } else {
                    (part.fallback as NSString).draw(at: NSPoint(x: iconX, y: floor((22 - textSize.height) / 2)), withAttributes: attributes)
                }
                x += widths[index] + 12
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

/// Vendor-owned logos stay in their installed apps, outside this repository and its packages.
@MainActor
enum VendorAssets {
    enum Vendor { case codex, claude }
    private static var cache: [String: NSImage] = [:]
    static func logo(_ vendor: Vendor) -> NSImage? {
        let name = vendor == .codex ? "chatgptTemplate" : "TrayIconTemplate"
        if let image = cache[name] { return image }
        let ids = vendor == .codex ? ["com.openai.codex", "com.openai.chat"] : ["com.anthropic.claudefordesktop"]
        let home = FileManager.default.homeDirectoryForCurrentUser
        var roots = ids.compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
        for app in vendor == .codex ? ["ChatGPT", "Codex"] : ["Claude"] {
            roots += [URL(fileURLWithPath: "/Applications/\(app).app"), home.appendingPathComponent("Applications/\(app).app")]
        }
        for root in roots {
            let url = root.appendingPathComponent("Contents/Resources/\(name).png")
            if let image = NSImage(contentsOf: url) {
                image.isTemplate = true
                cache[name] = image
                return image
            }
        }
        return nil
    }
}
