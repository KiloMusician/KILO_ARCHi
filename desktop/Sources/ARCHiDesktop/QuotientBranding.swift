import AppKit
import SwiftUI

/// Product branding belongs to the application, independently of the
/// companion's selected body, identity, or exported appearance.
@MainActor
enum QuotientBranding {
    static let mark = image(named: "QuotientMark")
    static let wordmark = image(named: "QuotientWordmark")

    static func resourceURL(named name: String) -> URL? {
        if Bundle.main.bundleURL.pathExtension == "app" {
            return Bundle.main.resourceURL?.appendingPathComponent("Branding/\(name).png")
        }
        return Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Branding")
    }

    private static func image(named name: String) -> NSImage? {
        guard let url = resourceURL(named: name) else { return nil }
        return NSImage(contentsOf: url)
    }
}

@MainActor
struct QuotientBrandSignature: View {
    var body: some View {
        Group {
            if let image = QuotientBranding.wordmark {
                Image(nsImage: image).resizable().scaledToFit()
                    .padding(8)
                    .background(.white, in: RoundedRectangle(cornerRadius: 8))
            } else {
                Text("Quotient Intelligent").font(.system(size: 12, weight: .medium))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Quotient Intelligent. Ideas, insight, impact.")
    }
}
