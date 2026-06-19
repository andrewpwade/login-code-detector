import Foundation

/// Validates and sanitizes IMAP-related user input before it is embedded into protocol commands.
public enum IMAPInputValidation {
    public static func sanitizeMailboxes(_ mailboxes: [String]) -> [String] {
        var seen = Set<String>()
        return mailboxes
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { mailbox in
                !mailbox.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
            }
            .filter { mailbox in
                let key = mailbox.uppercased()
                guard !seen.contains(key) else {
                    return false
                }
                seen.insert(key)
                return true
            }
    }

    public static func quoteIMAPString(_ value: String, field: String) throws -> String {
        guard !value.isEmpty else {
            throw IMAPError.invalidInput("\(field) cannot be empty")
        }
        guard !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw IMAPError.invalidInput("\(field) contains control characters")
        }
        return "\"\(value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    public static func validateHost(_ host: String) throws {
        guard !host.isEmpty else {
            throw IMAPError.invalidInput("host cannot be empty")
        }
        guard !host.unicodeScalars.contains(where: { scalar in
            CharacterSet.controlCharacters.contains(scalar) || CharacterSet.whitespacesAndNewlines.contains(scalar)
        }) else {
            throw IMAPError.invalidInput("host contains invalid characters")
        }
    }

    public static func isValidDomain(_ domain: String) -> Bool {
        guard !domain.isEmpty, !domain.hasPrefix("."), !domain.hasSuffix(".") else {
            return false
        }
        let labels = domain.split(separator: ".", omittingEmptySubsequences: false)
        guard !labels.isEmpty, labels.allSatisfy({ !$0.isEmpty }) else {
            return false
        }
        return labels.allSatisfy { label in
            label.unicodeScalars.allSatisfy { scalar in
                CharacterSet.alphanumerics.contains(scalar) || scalar.value == 45
            }
        }
    }
}
