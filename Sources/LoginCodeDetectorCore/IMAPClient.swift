import Foundation

/// Thin async IMAP client for the subset of commands the app needs: connect, authenticate, select, search,
/// fetch, and optionally idle.
/// It deliberately keeps protocol handling local to this type so watcher and onboarding code can work with
/// mailbox-level operations rather than tagged-command parsing.
public actor IMAPClient {
    /// Local constants used while interpreting incremental IMAP state.
    private enum Constants {
        static let firstTagNumber = 1
        static let firstUID = 1 as UInt64
        static let emptyUID = 0 as UInt64
    }

    private let account: IMAPAccount
    private let transport: any IMAPTransport
    private var buffer = Data()
    private var tagCounter = Constants.firstTagNumber
    private var isEncrypted = false

    public init(account: IMAPAccount) {
        switch account.security {
        case .implicitTLS:
            self.init(account: account, transport: NetworkIMAPTransport())
        case .startTLS:
            self.init(account: account, transport: StreamIMAPTransport())
        }
    }

    init(account: IMAPAccount, transport: any IMAPTransport) {
        self.account = account
        self.transport = transport
    }

    public func connect() async throws {
        try Task.checkCancellation()
        try IMAPInputValidation.validateHost(account.host)
        try await transport.connect(
            host: account.host,
            port: account.port,
            security: account.security,
            serverName: account.host,
            timeout: IMAPRuntimeDefaults.connectTimeoutSeconds
        )
        isEncrypted = account.security == .implicitTLS
        _ = try await readLine(timeout: IMAPRuntimeDefaults.commandTimeoutSeconds)
        // Treat STARTTLS as part of connection setup rather than login so the rest of the client can assume
        // credentials are never sent before encryption is active.
        if account.security == .startTLS {
            try await startTLS()
        }
    }

    public func login() async throws {
        guard isEncrypted else {
            throw IMAPError.insecureLoginRefused
        }
        try await ensureTLSVerified()
        _ = try await command("LOGIN \(try IMAPInputValidation.quoteIMAPString(account.username, field: "username")) \(try IMAPInputValidation.quoteIMAPString(account.password, field: "password"))")
    }

    public func capabilities() async throws -> Set<String> {
        let response = try await command("CAPABILITY")
        let joined = response.map(\.text).joined(separator: " ").uppercased()
        return Set(joined.split(separator: " ").map(String.init))
    }

    public func selectMailbox(_ mailbox: String? = nil) async throws {
        _ = try await command("SELECT \(try IMAPInputValidation.quoteIMAPString(mailbox ?? account.mailbox, field: "mailbox"))")
    }

    public func listMailboxes() async throws -> [String] {
        let response = try await command("LIST \"\" \"*\"")
        let mailboxes = response.compactMap(parseMailboxName)
        return Array(Set(mailboxes)).sorted { lhs, rhs in
            if lhs.uppercased() == "INBOX" { return true }
            if rhs.uppercased() == "INBOX" { return false }
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
    }

    public func searchUIDs(after uid: UInt64) async throws -> [UInt64] {
        let response = try await command("UID SEARCH UID \(uid + 1):*")
        return parseUIDSearchResponse(response, greaterThan: uid)
    }

    public func searchUIDsYoungerThan(seconds: Int) async throws -> [UInt64] {
        let response = try await command("UID SEARCH YOUNGER \(seconds)")
        return parseUIDSearchResponse(response)
    }

    public func highestKnownUID() async throws -> UInt64 {
        let response = try await command("STATUS \(try IMAPInputValidation.quoteIMAPString(account.mailbox, field: "mailbox")) (UIDNEXT)")
        // UIDNEXT is the next assignable UID, so subtract one to get the newest message that can already exist.
        let uidNext = parseStatusNumber("UIDNEXT", from: response.map(\.text)) ?? Constants.firstUID
        return uidNext > Constants.emptyUID ? uidNext - 1 : Constants.emptyUID
    }

    public func fetchMessage(uid: UInt64) async throws -> MailEvent? {
        let response = try await command("UID FETCH \(uid) (BODY.PEEK[] INTERNALDATE)")
        guard let rawMessage = response.compactMap(\.literalString).first else {
            throw IMAPError.malformedResponse("FETCH response did not include a message literal")
        }
        let message = MIMEMessage(raw: rawMessage)
        return MailEvent(
            uid: uid,
            sender: message.header("From") ?? "",
            subject: message.header("Subject") ?? "",
            receivedAt: message.receivedAt ?? internalDate(from: response.map(\.text)) ?? Date(),
            plainTextBody: message.plainTextBody,
            htmlBody: message.htmlBody
        )
    }

    public func idleUntilMailboxChanges(timeoutSeconds: UInt64 = IMAPRuntimeDefaults.idleTimeoutSeconds) async throws -> String {
        let tag = nextTag()
        try await writeLine("\(tag) IDLE", timeout: IMAPRuntimeDefaults.writeTimeoutSeconds)
        _ = try await readLine(prefix: "+", timeout: IMAPRuntimeDefaults.commandTimeoutSeconds)
        var wakeReason = "IDLE timeout"
        do {
            try await withThrowingTaskGroup(of: String?.self) { group in
                // Race server activity against a client-side timeout so we periodically re-enter the command loop
                // and avoid hanging forever on servers with fragile IDLE implementations.
                group.addTask { [weak self] in
                    try await self?.readLine(
                        containingAny: ["EXISTS", "RECENT", "FETCH", "EXPUNGE"],
                        timeout: TimeInterval(timeoutSeconds),
                        clampsReadTimeout: false
                    )
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(timeoutSeconds))
                    return nil
                }
                if let result = try await group.next(), let result {
                    wakeReason = result
                }
                group.cancelAll()
            }
        } catch is CancellationError {
            try? await writeLine("DONE", timeout: IMAPRuntimeDefaults.writeTimeoutSeconds)
            throw CancellationError()
        }
        try await writeLine("DONE", timeout: IMAPRuntimeDefaults.writeTimeoutSeconds)
        _ = try await readLine(prefix: "\(tag) OK", timeout: IMAPRuntimeDefaults.commandTimeoutSeconds)
        return wakeReason
    }

    public func disconnect() async {
        await transport.close()
        buffer.removeAll()
        isEncrypted = false
    }

    private func startTLS() async throws {
        let capabilities = try await capabilities()
        guard capabilities.contains("STARTTLS") else {
            throw IMAPError.startTLSUnavailable
        }
        _ = try await command("STARTTLS")
        try await transport.upgradeToTLS(serverName: account.host, timeout: IMAPRuntimeDefaults.connectTimeoutSeconds)
        isEncrypted = true
        buffer.removeAll()
        try await ensureTLSVerified()
    }

    private func ensureTLSVerified() async throws {
        if await transport.isTLSVerified() {
            return
        }
        // Some stream backends publish certificate verification state asynchronously; a cheap round-trip gives
        // the transport a chance to finish surfacing that result before we fail the session.
        _ = try await command("NOOP")
        guard await transport.isTLSVerified() else {
            throw IMAPError.tlsVerificationFailed
        }
    }

    private func command(_ command: String) async throws -> [IMAPResponse] {
        let tag = nextTag()
        try await writeLine("\(tag) \(command)", timeout: IMAPRuntimeDefaults.writeTimeoutSeconds)
        var responses: [IMAPResponse] = []
        while true {
            let response = try await readResponse(timeout: IMAPRuntimeDefaults.commandTimeoutSeconds)
            responses.append(response)
            let line = response.text
            if line.hasPrefix("\(tag) ") {
                let upper = line.uppercased()
                if upper.hasPrefix("\(tag) OK") {
                    return responses
                }
                if upper.hasPrefix("\(tag) NO") || upper.hasPrefix("\(tag) BAD") {
                    throw IMAPError.commandFailed(line)
                }
                throw IMAPError.malformedResponse("Unknown tagged completion: \(line)")
            }
        }
    }

    private func parseUIDSearchResponse(_ response: [IMAPResponse], greaterThan uid: UInt64 = 0) -> [UInt64] {
        response
            .map(\.text)
            .flatMap { $0.split(separator: " ") }
            .compactMap { UInt64($0) }
            .filter { $0 > uid }
            .sorted()
    }

    private func parseStatusNumber(_ key: String, from response: [String]) -> UInt64? {
        let joined = response.joined(separator: " ")
        let pattern = "\(NSRegularExpression.escapedPattern(for: key))\\s+(\\d+)"
        guard
            let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
            let match = regex.firstMatch(in: joined, range: NSRange(joined.startIndex..<joined.endIndex, in: joined)),
            let range = Range(match.range(at: 1), in: joined)
        else {
            return nil
        }
        return UInt64(joined[range])
    }

    private func parseMailboxName(from response: IMAPResponse) -> String? {
        let line = response.text
        guard line.uppercased().hasPrefix("* LIST") else {
            return nil
        }
        if let literal = response.literalString {
            let trimmed = literal.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix(" NIL") {
            return nil
        }
        if let lastQuote = trimmed.lastIndex(of: "\"") {
            let beforeLastQuote = trimmed[..<lastQuote]
            if let firstQuote = beforeLastQuote.lastIndex(of: "\"") {
                let mailbox = String(beforeLastQuote[beforeLastQuote.index(after: firstQuote)...])
                    .replacingOccurrences(of: #"\\(["\\])"#, with: "$1", options: .regularExpression)
                return mailbox.isEmpty ? nil : mailbox
            }
        }
        return trimmed.split(separator: " ").last.map(String.init)
    }

    private func readResponse(timeout: TimeInterval) async throws -> IMAPResponse {
        let line = try await readLine(timeout: timeout)
        if let literalLength = parseLiteralLength(from: line) {
            // IMAP literals are framed separately from the response line, so preserve both pieces together for
            // callers that need the raw message body.
            let literal = try await readExact(count: literalLength, timeout: timeout)
            _ = try await readLine(timeout: timeout)
            return IMAPResponse(line: line, literal: literal)
        }
        return IMAPResponse(line: line)
    }

    private func readLine(
        prefix: String? = nil,
        containingAny needles: [String] = [],
        timeout: TimeInterval,
        clampsReadTimeout: Bool = true
    ) async throws -> String {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let line = popLine(), matches(line: line, prefix: prefix, containingAny: needles) {
                return line
            }
            let remainingTimeout = max(0, deadline.timeIntervalSinceNow)
            let readTimeout = clampsReadTimeout ? min(remainingTimeout, IMAPRuntimeDefaults.readTimeoutSeconds) : timeout
            guard let chunk = try await transport.readSome(timeout: readTimeout) else {
                throw IMAPError.disconnected
            }
            buffer.append(chunk)
        }
        throw IMAPError.timeout("read")
    }

    private func readExact(count: Int, timeout: TimeInterval) async throws -> Data {
        let deadline = Date().addingTimeInterval(timeout)
        while buffer.count < count && Date() < deadline {
            let remainingTimeout = max(0, deadline.timeIntervalSinceNow)
            guard let chunk = try await transport.readSome(timeout: min(remainingTimeout, IMAPRuntimeDefaults.readTimeoutSeconds)) else {
                throw IMAPError.disconnected
            }
            buffer.append(chunk)
        }
        guard buffer.count >= count else {
            throw IMAPError.timeout("read")
        }
        let data = buffer.prefix(count)
        buffer.removeFirst(count)
        return Data(data)
    }

    private func popLine() -> String? {
        guard let range = buffer.firstRange(of: Data("\r\n".utf8)) else {
            return nil
        }
        let lineData = buffer[..<range.lowerBound]
        buffer.removeSubrange(..<range.upperBound)
        return String(data: lineData, encoding: .utf8)
    }

    private func parseLiteralLength(from line: String) -> Int? {
        guard
            let regex = try? NSRegularExpression(pattern: #"\{(\d+)\}$"#),
            let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..<line.endIndex, in: line)),
            let range = Range(match.range(at: 1), in: line)
        else {
            return nil
        }
        return Int(line[range])
    }

    private func matches(line: String, prefix: String?, containingAny needles: [String]) -> Bool {
        if let prefix, !line.hasPrefix(prefix) {
            return false
        }
        if needles.isEmpty {
            return true
        }
        let upper = line.uppercased()
        return needles.contains { upper.contains($0) }
    }

    private func writeLine(_ raw: String, timeout: TimeInterval) async throws {
        try await transport.write(Data("\(raw)\r\n".utf8), timeout: timeout)
    }

    private func nextTag() -> String {
        defer { tagCounter += 1 }
        return "A\(tagCounter)"
    }

    private func internalDate(from response: [String]) -> Date? {
        let joined = response.joined(separator: " ")
        let pattern = #"INTERNALDATE\s+"([^"]+)""#
        guard
            let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
            let match = regex.firstMatch(in: joined, range: NSRange(joined.startIndex..<joined.endIndex, in: joined)),
            let range = Range(match.range(at: 1), in: joined)
        else {
            return nil
        }
        return IMAPInternalDateParser.date(from: String(joined[range]))
    }
}

/// Parsed IMAP response line plus any literal payload that followed it on the wire.
struct IMAPResponse: Equatable {
    let line: String
    let literal: Data?

    init(line: String, literal: Data? = nil) {
        self.line = line
        self.literal = literal
    }

    var text: String {
        line
    }

    var literalString: String? {
        guard let literal else { return nil }
        return String(data: literal, encoding: .utf8)
    }
}

/// Parses IMAP `INTERNALDATE` values into `Date` instances.
private enum IMAPInternalDateParser {
    static func date(from string: String) -> Date? {
        for format in [
            "d-MMM-yyyy HH:mm:ss Z",
            "dd-MMM-yyyy HH:mm:ss Z",
            "d-MMM-yyyy HH:mm Z",
            "dd-MMM-yyyy HH:mm Z"
        ] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.isLenient = true
            formatter.dateFormat = format
            if let date = formatter.date(from: string) {
                return date
            }
        }
        return nil
    }
}

/// Error surface for IMAP protocol, transport, and validation failures.
public enum IMAPError: Error, LocalizedError, Equatable {
    case disconnected
    case commandFailed(String)
    case insecureLoginRefused
    case startTLSUnavailable
    case invalidInput(String)
    case timeout(String)
    case tlsVerificationFailed
    case malformedResponse(String)

    public var errorDescription: String? {
        switch self {
        case .disconnected:
            return "The IMAP connection disconnected."
        case let .commandFailed(message):
            return "IMAP command failed: \(message)"
        case .insecureLoginRefused:
            return "Refusing to send the password before TLS is active."
        case .startTLSUnavailable:
            return "The IMAP server does not offer STARTTLS."
        case let .invalidInput(message):
            return "Invalid IMAP input: \(message)"
        case let .timeout(operation):
            return "Timed out during IMAP \(operation)."
        case .tlsVerificationFailed:
            return "TLS negotiation did not produce a verified peer certificate."
        case let .malformedResponse(message):
            return "Malformed IMAP response: \(message)"
        }
    }
}
