import Foundation

/// Heuristic scorer for extracting likely 2FA codes from normalized message content.
/// The goal is not perfect message understanding; it is to rank short code-like tokens conservatively enough
/// that the app can notify on strong matches without spamming on generic transactional email.
public struct CodeExtractor: Sendable {
    private let strongTerms = [
        "verification code", "security code", "one-time code", "one time code",
        "one-time passcode", "one time passcode", "login code", "sign in code",
        "temporary verification code", "temporary login code", "temporary code",
        "passcode", "2fa", "two-factor", "two factor", "verify your identity",
        "enter these digits", "digit code", "use this code", "code to sign in"
    ]

    private let weakTerms = [
        "code", "verify", "verification", "identity", "sign in", "login", "authenticate",
        "requested", "digits", "account"
    ]

    private let negativeTerms = [
        "invoice", "order number", "tracking number", "phone", "postcode", "zip code",
        "support ticket", "case number", "copyright", "unsubscribe", "total", "receipt"
    ]

    public init() {}

    public func bestCode(in event: MailEvent, allowlistedSenders: [String] = []) -> DetectedCode? {
        let body = bodyText(for: event)
        let searchable = TextNormalizer.normalize([event.subject, event.sender, body].joined(separator: "\n"))
        return detect(in: searchable, sender: event.sender, subject: event.subject, allowlistedSenders: allowlistedSenders).first
    }

    public func bodyText(for event: MailEvent) -> String {
        let plain = TextNormalizer.normalize(event.plainTextBody)
        let html = event.htmlBody.map(HTMLTextExtractor.text(from:)) ?? ""

        if plain.isEmpty {
            return html
        }
        if !html.isEmpty, looksLikeMarkupOrMIME(plain) {
            // Some providers stuff raw HTML/MIME into the plain-text part; prefer the parsed HTML text so scoring
            // is based on what the user would actually read.
            return html
        }
        if !html.isEmpty {
            return TextNormalizer.normalize([plain, html].joined(separator: "\n\n"))
        }
        return plain
    }

    public func detect(
        in text: String,
        sender: String = "",
        subject: String = "",
        allowlistedSenders: [String] = []
    ) -> [DetectedCode] {
        let normalized = TextNormalizer.normalize(text)
        guard !normalized.isEmpty else {
            return []
        }

        let patterns = [
            #"\b\d{6,8}\b"#,
            #"\b\d{3}[\s-]\d{3}\b"#,
            #"\b[A-Z0-9]{6,8}\b"#
        ]

        var detections: [DetectedCode] = []
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                continue
            }
            let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
            for match in regex.matches(in: normalized, range: range) {
                guard let swiftRange = Range(match.range, in: normalized) else {
                    continue
                }
                let rawCode = String(normalized[swiftRange])
                let code = rawCode.replacingOccurrences(of: #"[\s-]"#, with: "", options: .regularExpression)
                guard isPlausible(code) else {
                    continue
                }

                let scored = score(
                    code: code,
                    rawRange: swiftRange,
                    text: normalized,
                    sender: sender,
                    subject: subject,
                    allowlistedSenders: allowlistedSenders
                )
                if scored.score >= 40 {
                    detections.append(DetectedCode(code: code, score: scored.score, reason: scored.reason, sourceRange: swiftRange))
                }
            }
        }

        return detections
            .deduplicatedByCodeKeepingHighestScore()
            .sorted { left, right in
                if left.score == right.score {
                    return left.code.count < right.code.count
                }
                return left.score > right.score
            }
    }

    private func isPlausible(_ code: String) -> Bool {
        guard (6...8).contains(code.count) else {
            return false
        }
        if code.rangeOfCharacter(from: .decimalDigits) == nil {
            return false
        }
        if Int(code).map({ (1900...2099).contains($0) }) == true {
            return false
        }
        return true
    }

    private func score(
        code: String,
        rawRange: Range<String.Index>,
        text: String,
        sender: String,
        subject: String,
        allowlistedSenders: [String]
    ) -> (score: Int, reason: String) {
        // Start numeric codes higher because transactional 2FA mail overwhelmingly uses short digit sequences;
        // alphanumeric candidates need stronger surrounding evidence to avoid matching random tokens.
        var score = code.allSatisfy(\.isNumber) ? 45 : 25
        var reasons: [String] = ["candidate"]

        let context = nearbyText(around: rawRange, in: text, characterRadius: 260).lowercased()
        let subjectLower = subject.lowercased()
        let senderLower = sender.lowercased()

        for term in strongTerms where context.contains(term) || subjectLower.contains(term) {
            score += 22
            reasons.append(term)
            break
        }
        for term in weakTerms where context.contains(term) || subjectLower.contains(term) {
            score += 8
            reasons.append(term)
        }
        for term in negativeTerms where context.contains(term) {
            score -= 35
            reasons.append("negative:\(term)")
            break
        }
        if isAloneOnLine(rawRange, in: text) {
            score += 18
            reasons.append("standalone")
        }
        if appearsSoonAfterIntentPhrase(rawRange, in: text) {
            score += 18
            reasons.append("after-intent")
        }
        if allowlistedSenders.contains(where: { senderLower.contains($0.lowercased()) }) {
            score += 15
            reasons.append("allowlisted-sender")
        }
        if subjectLower.contains("code") || subjectLower.contains("verification") || subjectLower.contains("passcode") {
            score += 12
            reasons.append("subject")
        }
        if looksLikeDateOrTime(code: code, context: context) {
            score -= 35
            reasons.append("date-or-time")
        }

        return (max(0, min(score, 100)), reasons.joined(separator: ", "))
    }

    private func nearbyText(around range: Range<String.Index>, in text: String, characterRadius: Int) -> String {
        let lowerBound = text.index(range.lowerBound, offsetBy: -characterRadius, limitedBy: text.startIndex) ?? text.startIndex
        let upperBound = text.index(range.upperBound, offsetBy: characterRadius, limitedBy: text.endIndex) ?? text.endIndex
        return String(text[lowerBound..<upperBound])
    }

    private func isAloneOnLine(_ range: Range<String.Index>, in text: String) -> Bool {
        let lineStart = text[..<range.lowerBound].lastIndex(of: "\n").map { text.index(after: $0) } ?? text.startIndex
        let lineEnd = text[range.upperBound...].firstIndex(of: "\n") ?? text.endIndex
        let line = text[lineStart..<lineEnd].trimmingCharacters(in: .whitespacesAndNewlines)
        return line.replacingOccurrences(of: #"[\s-]"#, with: "", options: .regularExpression)
            == text[range].replacingOccurrences(of: #"[\s-]"#, with: "", options: .regularExpression)
    }

    private func appearsSoonAfterIntentPhrase(_ range: Range<String.Index>, in text: String) -> Bool {
        let prefixStart = text.index(range.lowerBound, offsetBy: -180, limitedBy: text.startIndex) ?? text.startIndex
        let prefix = text[prefixStart..<range.lowerBound].lowercased()
        return strongTerms.contains { prefix.contains($0) }
    }

    private func looksLikeDateOrTime(code: String, context: String) -> Bool {
        context.contains(" at ") || context.contains(" on ") || context.contains("date") || context.contains("time")
            ? code.hasPrefix("20")
            : false
    }

    private func looksLikeMarkupOrMIME(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("<html")
            || lower.contains("<table")
            || lower.contains("<tbody")
            || lower.contains("<p")
            || lower.contains("content-type: text/html")
            || lower.contains("mime-version:")
    }
}

private extension Array where Element == DetectedCode {
    func deduplicatedByCodeKeepingHighestScore() -> [DetectedCode] {
        var best: [String: DetectedCode] = [:]
        for detection in self where detection.score > (best[detection.code]?.score ?? -1) {
            best[detection.code] = detection
        }
        return Array(best.values)
    }
}
