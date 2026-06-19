import Foundation
import XCTest
@testable import LoginCodeDetectorCore

final class IMAPDiscoveryTests: XCTestCase {
    func testExtractsDomainFromEmailAddress() {
        XCTAssertEqual(IMAPDiscovery.domain(from: " user@example.com "), "example.com")
        XCTAssertNil(IMAPDiscovery.domain(from: "user"))
        XCTAssertNil(IMAPDiscovery.domain(from: "user@example.com/evil"))
        XCTAssertNil(IMAPDiscovery.domain(from: "user@evil.com@attacker.com"))
    }

    func testProviderCandidatesUseKnownSecureHosts() {
        XCTAssertEqual(
            IMAPDiscovery.providerCandidates(for: "gmail.com"),
            [IMAPServerCandidate(host: "imap.gmail.com", port: 993, security: .implicitTLS)]
        )
        XCTAssertEqual(
            IMAPDiscovery.providerCandidates(for: "outlook.com"),
            [IMAPServerCandidate(host: "outlook.office365.com", port: 993, security: .implicitTLS)]
        )
    }

    func testHeuristicCandidatesIncludeImplicitTLSAndStartTLS() {
        XCTAssertEqual(
            IMAPDiscovery.heuristicCandidates(for: "example.com").prefix(2),
            [
                IMAPServerCandidate(host: "imap.example.com", port: 993, security: .implicitTLS),
                IMAPServerCandidate(host: "imap.example.com", port: 143, security: .startTLS)
            ]
        )
    }

    func testParseAutoconfigKeepsOnlySecureIMAPServers() {
        let xml = """
        <clientConfig>
          <emailProvider id="example.com">
            <incomingServer type="imap">
              <hostname>imap.example.com</hostname>
              <port>993</port>
              <socketType>SSL</socketType>
            </incomingServer>
            <incomingServer type="imap">
              <hostname>mail.example.com</hostname>
              <port>143</port>
              <socketType>STARTTLS</socketType>
            </incomingServer>
            <incomingServer type="pop3">
              <hostname>pop.example.com</hostname>
              <port>995</port>
              <socketType>SSL</socketType>
            </incomingServer>
            <incomingServer type="imap">
              <hostname>plain.example.com</hostname>
              <port>143</port>
              <socketType>plain</socketType>
            </incomingServer>
          </emailProvider>
        </clientConfig>
        """

        XCTAssertEqual(
            IMAPDiscovery.parseAutoconfig(Data(xml.utf8)),
            [
                IMAPServerCandidate(host: "imap.example.com", port: 993, security: .implicitTLS),
                IMAPServerCandidate(host: "mail.example.com", port: 143, security: .startTLS)
            ]
        )
    }

    func testDeduplicatesCaseInsensitiveHostPortSecurityTriples() {
        XCTAssertEqual(
            IMAPDiscovery.deduplicated([
                IMAPServerCandidate(host: "imap.example.com", port: 993, security: .implicitTLS),
                IMAPServerCandidate(host: "IMAP.example.com", port: 993, security: .implicitTLS),
                IMAPServerCandidate(host: "imap.example.com", port: 143, security: .startTLS)
            ]),
            [
                IMAPServerCandidate(host: "imap.example.com", port: 993, security: .implicitTLS),
                IMAPServerCandidate(host: "imap.example.com", port: 143, security: .startTLS)
            ]
        )
    }
}
