import Foundation

/// Network timing defaults for autoconfig lookups during discovery.
private enum IMAPDiscoveryDefaults {
    static let autoconfigTimeoutSeconds: TimeInterval = 6
}

/// One possible IMAP server configuration to try during discovery.
public struct IMAPServerCandidate: Sendable, Equatable, Hashable {
    public var host: String
    public var port: Int
    public var security: IMAPAccount.Security

    public init(host: String, port: Int, security: IMAPAccount.Security) {
        self.host = host
        self.port = port
        self.security = security
    }
}

/// Successful discovery output including the chosen server and available mailboxes.
public struct IMAPDiscoveryResult: Sendable, Equatable {
    public var candidate: IMAPServerCandidate
    public var mailboxes: [String]

    public init(candidate: IMAPServerCandidate, mailboxes: [String]) {
        self.candidate = candidate
        self.mailboxes = mailboxes
    }
}

/// Finds plausible IMAP server settings for an email address, then verifies them with a real login.
/// Candidate ordering is intentionally layered from most reliable to most speculative so onboarding is fast on
/// common providers while still offering a fallback path for custom domains.
public actor IMAPDiscovery {
    private let autoconfigLoader: @Sendable (URL) async throws -> Data

    public init(autoconfigLoader: @escaping @Sendable (URL) async throws -> Data = IMAPDiscovery.defaultAutoconfigLoader) {
        self.autoconfigLoader = autoconfigLoader
    }

    public func discover(username: String, password: String) async throws -> IMAPDiscoveryResult {
        let normalizedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = try await candidates(for: normalizedUsername)
        var lastError: (any Error)?

        for candidate in candidates {
            let account = IMAPAccount(
                host: candidate.host,
                port: candidate.port,
                security: candidate.security,
                username: normalizedUsername,
                password: password
            )
            let client = IMAPClient(account: account)
            do {
                try await client.connect()
                try await client.login()
                let mailboxes = try await client.listMailboxes()
                await client.disconnect()
                return IMAPDiscoveryResult(candidate: candidate, mailboxes: mailboxes)
            } catch {
                await client.disconnect()
                lastError = error
            }
        }

        throw lastError ?? IMAPDiscoveryError.noCandidates
    }

    public func candidates(for username: String) async throws -> [IMAPServerCandidate] {
        guard let domain = Self.domain(from: username) else {
            throw IMAPDiscoveryError.emailAddressRequired
        }

        var candidates: [IMAPServerCandidate] = []
        // Prefer known-provider mappings first because they are faster and more reliable than network discovery.
        candidates.append(contentsOf: Self.providerCandidates(for: domain))
        candidates.append(contentsOf: try await autoconfigCandidates(for: domain, emailAddress: username))
        candidates.append(contentsOf: Self.heuristicCandidates(for: domain))
        return Self.deduplicated(candidates)
    }

    public static func domain(from username: String) -> String? {
        let parts = username.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "@", maxSplits: 1)
        guard parts.count == 2, !parts[1].isEmpty else {
            return nil
        }
        let domain = String(parts[1]).lowercased()
        return IMAPInputValidation.isValidDomain(domain) ? domain : nil
    }

    public static func providerCandidates(for domain: String) -> [IMAPServerCandidate] {
        let normalized = domain.lowercased()
        let host: String?
        switch normalized {
        case "gmail.com", "googlemail.com":
            host = "imap.gmail.com"
        case "outlook.com", "hotmail.com", "live.com", "msn.com":
            host = "outlook.office365.com"
        case "icloud.com", "me.com", "mac.com":
            host = "imap.mail.me.com"
        case "yahoo.com", "ymail.com", "rocketmail.com":
            host = "imap.mail.yahoo.com"
        case "fastmail.com", "fastmail.fm":
            host = "imap.fastmail.com"
        case "aol.com":
            host = "imap.aol.com"
        default:
            host = nil
        }
        guard let host else {
            return []
        }
        return [IMAPServerCandidate(host: host, port: IMAPDefaults.implicitTLSPort, security: .implicitTLS)]
    }

    public static func heuristicCandidates(for domain: String) -> [IMAPServerCandidate] {
        ["imap.\(domain)", "mail.\(domain)", domain].flatMap { host in
            [
                IMAPServerCandidate(host: host, port: IMAPDefaults.implicitTLSPort, security: .implicitTLS),
                IMAPServerCandidate(host: host, port: IMAPDefaults.startTLSPort, security: .startTLS)
            ]
        }
    }

    public static func parseAutoconfig(_ data: Data) -> [IMAPServerCandidate] {
        let parser = AutoconfigParser(data: data)
        return deduplicated(parser.parse())
    }

    public static func deduplicated(_ candidates: [IMAPServerCandidate]) -> [IMAPServerCandidate] {
        var seen = Set<IMAPServerCandidate>()
        return candidates.filter { candidate in
            let normalized = IMAPServerCandidate(host: candidate.host.lowercased(), port: candidate.port, security: candidate.security)
            guard !seen.contains(normalized) else {
                return false
            }
            seen.insert(normalized)
            return true
        }
    }

    private func autoconfigCandidates(for domain: String, emailAddress: String) async throws -> [IMAPServerCandidate] {
        let urls = [
            Self.makeURL(host: "autoconfig.\(domain)", path: "/mail/config-v1.1.xml", queryItems: [URLQueryItem(name: "emailaddress", value: emailAddress)]),
            Self.makeURL(host: domain, path: "/.well-known/autoconfig/mail/config-v1.1.xml", queryItems: [URLQueryItem(name: "emailaddress", value: emailAddress)]),
            Self.makeURL(host: "live.thunderbird.net", path: "/autoconfig/v1.1/\(domain)", queryItems: nil)
        ].compactMap { $0 }
        var candidates: [IMAPServerCandidate] = []
        for url in urls {
            do {
                candidates.append(contentsOf: Self.parseAutoconfig(try await autoconfigLoader(url)))
            } catch {
                // Discovery should degrade across endpoints, not fail fast on the first provider that is missing
                // or rate-limited.
                continue
            }
        }
        return candidates
    }

    public static func defaultAutoconfigLoader(url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = IMAPDiscoveryDefaults.autoconfigTimeoutSeconds
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw IMAPDiscoveryError.autoconfigUnavailable
        }
        return data
    }

    private static func makeURL(host: String, path: String, queryItems: [URLQueryItem]?) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = path
        components.queryItems = queryItems
        return components.url
    }

}

/// Discovery failures that should be surfaced directly in onboarding and setup flows.
public enum IMAPDiscoveryError: Error, LocalizedError {
    case emailAddressRequired
    case noCandidates
    case autoconfigUnavailable

    public var errorDescription: String? {
        switch self {
        case .emailAddressRequired:
            return "Enter an email address so the IMAP server can be discovered."
        case .noCandidates:
            return "No IMAP server candidates were found."
        case .autoconfigUnavailable:
            return "Autoconfig was unavailable."
        }
    }
}

/// XML parser for Thunderbird-style autoconfig documents that extracts IMAP server candidates.
private final class AutoconfigParser: NSObject, XMLParserDelegate {
    private let parser: XMLParser
    private var candidates: [IMAPServerCandidate] = []
    private var currentElement = ""
    private var currentProtocolType: String?
    private var currentHostname = ""
    private var currentPort = ""
    private var currentSocketType = ""
    private var isIncomingServer = false

    init(data: Data) {
        parser = XMLParser(data: data)
        super.init()
        parser.delegate = self
    }

    func parse() -> [IMAPServerCandidate] {
        parser.parse()
        return candidates
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        if elementName == "incomingServer" {
            isIncomingServer = true
            currentProtocolType = attributeDict["type"]?.lowercased()
            currentHostname = ""
            currentPort = ""
            currentSocketType = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard isIncomingServer else {
            return
        }
        let value = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return
        }
        switch currentElement {
        case "hostname":
            currentHostname += value
        case "port":
            currentPort += value
        case "socketType":
            currentSocketType += value
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "incomingServer" {
            defer {
                isIncomingServer = false
                currentProtocolType = nil
            }
            guard currentProtocolType == "imap", let port = Int(currentPort), !currentHostname.isEmpty else {
                return
            }
            let socketType = currentSocketType.uppercased()
            if socketType == "SSL" || socketType == "TLS" {
                candidates.append(IMAPServerCandidate(host: currentHostname, port: port, security: .implicitTLS))
            } else if socketType == "STARTTLS" {
                candidates.append(IMAPServerCandidate(host: currentHostname, port: port, security: .startTLS))
            }
        }
        currentElement = ""
    }
}
