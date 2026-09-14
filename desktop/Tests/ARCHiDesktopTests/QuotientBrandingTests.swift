import AppKit
import XCTest
@testable import ARCHiDesktop

final class QuotientBrandingTests: XCTestCase {
    @MainActor
    func testBundledMarkAndWordmarkLoadThroughTheProductionResourcePath() throws {
        let entries: [(String, NSImage?, Int, Int)] = [
            ("QuotientMark", QuotientBranding.mark, 1024, 1024),
            ("QuotientWordmark", QuotientBranding.wordmark, 2172, 724)
        ]
        for (name, image, width, height) in entries {
            let url = try XCTUnwrap(QuotientBranding.resourceURL(named: name))
            XCTAssertEqual(url.lastPathComponent, "\(name).png")
            XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, "Branding")
            let data = try Data(contentsOf: url)
            XCTAssertEqual(Array(data.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
            XCTAssertEqual(bitmap.pixelsWide, width)
            XCTAssertEqual(bitmap.pixelsHigh, height)
            XCTAssertTrue(try XCTUnwrap(image).isValid)
            XCTAssertLessThan(data.count, 1_400_000)
        }
        XCTAssertNotEqual(QuotientBranding.resourceURL(named: "QuotientMark"),
                          QuotientBranding.resourceURL(named: "QuotientWordmark"))
    }
}
