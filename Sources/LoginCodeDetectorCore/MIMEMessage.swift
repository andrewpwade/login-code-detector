import Foundation

/// Minimal MIME parser for extracting headers and the first text/plain or text/html body from raw messages.
struct MIMEMessage {
    let headers: [String: String]
    let body: String

    init(raw: String) {
        let (headerBlock, bodyBlock) = Self.split(raw: raw)
        self.headers = Self.parseHeaders(headerBlock)
        self.body = bodyBlock
    }

    func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }

    var receivedAt: Date? {
        guard let dateHeader = header("Date") else {
            return nil
        }
        return RFC2822DateParser.date(from: dateHeader)
    }

    var plainTextBody: String {
        if let part = Self.firstPart(in: body, headers: headers, matching: "text/plain") {
            return part.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return body.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var htmlBody: String? {
        guard let part = Self.firstPart(in: body, headers: headers, matching: "text/html") else {
            return nil
        }
        let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func split(raw: String) -> (String, String) {
        if let range = raw.range(of: "\r\n\r\n") {
            return (String(raw[..<range.lowerBound]), String(raw[range.upperBound...]))
        }
        if let range = raw.range(of: "\n\n") {
            return (String(raw[..<range.lowerBound]), String(raw[range.upperBound...]))
        }
        return (raw, "")
    }

    private static func parseHeaders(_ headerBlock: String) -> [String: String] {
        var result: [String: String] = [:]
        var currentName: String?
        var currentValue = ""

        func flush() {
            guard let currentName else { return }
            result[currentName.lowercased()] = currentValue.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        for line in headerBlock.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(line)
            if line.hasPrefix(" ") || line.hasPrefix("\t") {
                currentValue += " " + line.trimmingCharacters(in: .whitespaces)
                continue
            }
            flush()
            guard let colon = line.firstIndex(of: ":") else {
                currentName = nil
                currentValue = ""
                continue
            }
            currentName = String(line[..<colon])
            currentValue = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        }
        flush()
        return result
    }

    private static func firstPart(in body: String, headers: [String: String], matching desiredContentType: String) -> String? {
        let effectiveBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !effectiveBody.isEmpty else {
            return nil
        }

        if let boundary = boundary(from: headers["content-type"]) {
            return firstPart(inMultipart: effectiveBody, boundary: boundary, matching: desiredContentType)
        }

        if desiredContentType == contentType(from: headers["content-type"]) {
            return decodedBody(effectiveBody, headers: headers)
        }
        return nil
    }

    private static func firstPart(inMultipart body: String, boundary: String, matching desiredContentType: String) -> String? {
        for segment in multipartSegments(in: body, boundary: boundary) {
            let part = MIMEMessage(raw: segment)
            if let match = firstPart(in: part.body, headers: part.headers, matching: desiredContentType) {
                return match
            }
            if contentType(from: part.headers["content-type"]) == desiredContentType {
                return decodedBody(part.body, headers: part.headers).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return nil
    }

    private static func multipartSegments(in body: String, boundary: String) -> [String] {
        let normalized = body.replacingOccurrences(of: "\r\n", with: "\n")
        let delimiter = "--\(boundary)"
        let closingDelimiter = "\(delimiter)--"
        var segments: [String] = []
        var current: [String]?

        for line in normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == delimiter || trimmed == closingDelimiter {
                if let current {
                    let segment = current.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !segment.isEmpty {
                        segments.append(segment)
                    }
                }
                if trimmed == closingDelimiter {
                    current = nil
                    break
                }
                current = []
                continue
            }
            current?.append(line)
        }

        return segments
    }

    private static func boundary(from contentType: String?) -> String? {
        guard let contentType else { return nil }
        let pattern = #"boundary\s*=\s*(?:"([^"]+)"|([^;]+))"#
        guard
            let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
            let match = regex.firstMatch(in: contentType, range: NSRange(contentType.startIndex..<contentType.endIndex, in: contentType))
        else {
            return nil
        }
        if let range = Range(match.range(at: 1), in: contentType) {
            return String(contentType[range])
        }
        if let range = Range(match.range(at: 2), in: contentType) {
            return String(contentType[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private static func contentType(from value: String?) -> String? {
        guard let value else { return nil }
        return value.split(separator: ";", maxSplits: 1).first.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
    }

    private static func decodedBody(_ body: String, headers: [String: String]) -> String {
        switch headers["content-transfer-encoding"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "base64":
            let compact = body.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
            guard let data = Data(base64Encoded: compact) else {
                return body
            }
            return String(data: data, encoding: .utf8) ?? body
        case "quoted-printable":
            return decodeQuotedPrintable(body)
        default:
            return body
        }
    }

    private static func decodeQuotedPrintable(_ body: String) -> String {
        var bytes: [UInt8] = []
        let scalars = Array(body.replacingOccurrences(of: "\r\n", with: "\n").unicodeScalars)
        var index = 0

        while index < scalars.count {
            let scalar = scalars[index]
            if scalar == "=" {
                let next = index + 1
                if next < scalars.count, scalars[next] == "\n" {
                    index += 2
                    continue
                }
                if index + 2 < scalars.count,
                   let high = hexValue(scalars[index + 1]),
                   let low = hexValue(scalars[index + 2]) {
                    bytes.append(UInt8(high * 16 + low))
                    index += 3
                    continue
                }
            }
            bytes.append(contentsOf: String(scalar).utf8)
            index += 1
        }

        return String(data: Data(bytes), encoding: .utf8) ?? body
    }

    private static func hexValue(_ scalar: UnicodeScalar) -> UInt8? {
        switch scalar.value {
        case 48...57:
            return UInt8(scalar.value - 48)
        case 65...70:
            return UInt8(scalar.value - 55)
        case 97...102:
            return UInt8(scalar.value - 87)
        default:
            return nil
        }
    }
}

/// Date parser for the subset of RFC 2822 header formats commonly seen in mail messages.
private enum RFC2822DateParser {
    static func date(from string: String) -> Date? {
        let normalized = normalize(string)
        for format in [
            "EEE, d MMM yyyy HH:mm:ss ZZZZ",
            "EEE, d MMM yyyy HH:mm:ss Z",
            "EEE, d MMM yyyy HH:mm:ss zzz",
            "d MMM yyyy HH:mm:ss ZZZZ",
            "d MMM yyyy HH:mm:ss Z",
            "d MMM yyyy HH:mm:ss zzz",
            "EEE, d MMM yyyy HH:mm ZZZZ",
            "EEE, d MMM yyyy HH:mm Z",
            "EEE, d MMM yyyy HH:mm zzz"
        ] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.isLenient = true
            formatter.dateFormat = format
            if let date = formatter.date(from: normalized) {
                return date
            }
        }
        return nil
    }

    private static func normalize(_ string: String) -> String {
        let noComments = string.replacingOccurrences(
            of: #"\s*\([^)]*\)"#,
            with: "",
            options: .regularExpression
        )
        return noComments
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
