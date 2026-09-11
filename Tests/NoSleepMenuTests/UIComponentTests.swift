import AppKit
import XCTest
@testable import NoSleepMenu

final class UIComponentTests: XCTestCase {
    @MainActor
    func testToggleRightEdgeAtDifferentMenuWidths() {
        _ = NSApplication.shared
        for title in ["Prevent sleep", "Sunshine compatibility", "Dim display, keyboard & mute on lid close"] {
            let row = ToggleMenuRow(title: title)
            row.setOn(true)
            for width in [330.0, 450.0, 600.0] {
                row.setFrameSize(NSSize(width: width, height: 54))
                row.layout()
                let toggle = row.subviews.compactMap { $0 as? NSSwitch }.first!
                XCTAssertEqual(toggle.frame.maxX, width - 14, accuracy: 0.1)
                XCTAssertEqual(toggle.state, .on)
            }
        }
    }
    @MainActor
    func testGroupedStatusImageAndProviderFallback() {
        _ = NSApplication.shared
        let codex = StatusPart(text: "82%", logo: nil, fallback: "Codex")
        let claude = StatusPart(text: "99%", logo: nil, fallback: "Claude")
        let first = StatusImage.render(parts: [codex], sleepEnabled: false)
        let second = StatusImage.render(parts: [claude], sleepEnabled: false)
        let grouped = StatusImage.render(parts: [codex, claude], sleepEnabled: false)
        XCTAssertTrue(grouped.isTemplate)
        XCTAssertEqual(grouped.size.width, first.size.width + second.size.width + 12)
        XCTAssertEqual(grouped.size.height, 22)
        XCTAssertNotNil(grouped.tiffRepresentation)
        XCTAssertTrue(StatusImage.render(parts: [], sleepEnabled: true).isTemplate)
    }
}
