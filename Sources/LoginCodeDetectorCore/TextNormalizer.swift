import Foundation

/// Normalizes message text into a consistent form before scoring or display logic examines it.
public enum TextNormalizer {
    public static func normalize(_ input: String) -> String {
        input
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "[\\t\\u{00A0} ]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: " *\\n+ *", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
