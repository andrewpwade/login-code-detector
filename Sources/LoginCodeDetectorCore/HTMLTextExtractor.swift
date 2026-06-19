import Foundation

/// Converts HTML email bodies into plain text suitable for normalization and code extraction.
public enum HTMLTextExtractor {
    public static func text(from html: String) -> String {
        var working = html
        let blockTags = [
            "br", "p", "/p", "div", "/div", "tr", "/tr", "td", "/td", "th", "/th",
            "li", "/li", "h1", "/h1", "h2", "/h2", "h3", "/h3"
        ]

        for tag in blockTags {
            working = working.replacingOccurrences(
                of: "(?i)<\\s*\(tag)(\\s+[^>]*)?>",
                with: "\n",
                options: .regularExpression
            )
        }

        working = working.replacingOccurrences(
            of: "(?is)<(script|style)[^>]*>.*?</\\1>",
            with: " ",
            options: .regularExpression
        )
        working = working.replacingOccurrences(of: "(?s)<[^>]+>", with: " ", options: .regularExpression)
        working = decodeEntities(in: working)
        return TextNormalizer.normalize(working)
    }

    private static func decodeEntities(in text: String) -> String {
        guard let data = text.data(using: .utf8) else {
            return text
        }
        let attributed = try? NSAttributedString(
            data: data,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ],
            documentAttributes: nil
        )
        return attributed?.string ?? text
    }
}
