import Foundation
import XCTest
@testable import LoginCodeDetectorCore

final class IMAPClientTransportTests: XCTestCase {
    func testConnectTimesOutWhenGreetingNeverArrives() async {
        let transport = FakeIMAPTransport()
        let client = IMAPClient(
            account: IMAPAccount(
                host: "imap.example.com",
                port: 993,
                username: "user@example.com",
                password: "password"
            ),
            transport: transport
        )

        do {
            try await client.connect()
            XCTFail("Expected connect() to time out")
        } catch let error as IMAPError {
            XCTAssertEqual(error, .timeout("read"))
        } catch {
            XCTFail("Expected IMAPError.timeout(read), got \(error)")
        }
    }

    func testLoginFailsWhenTLSCannotBeVerified() async throws {
        let transport = FakeIMAPTransport(script: [
            .read("* OK IMAP4 ready\r\n"),
            .write("A1 NOOP\r\n"),
            .read("A1 OK NOOP completed\r\n")
        ])
        let client = IMAPClient(
            account: IMAPAccount(
                host: "imap.example.com",
                port: 993,
                username: "user@example.com",
                password: "password"
            ),
            transport: transport
        )

        try await client.connect()

        do {
            try await client.login()
            XCTFail("Expected login() to fail TLS verification")
        } catch let error as IMAPError {
            XCTAssertEqual(error, .tlsVerificationFailed)
        }
    }

    func testLoginPreservesPasswordWhitespace() async throws {
        let transport = FakeIMAPTransport(script: [
            .read("* OK IMAP4 ready\r\n"),
            .write("A1 LOGIN \"user@example.com\" \"  pass word  \"\r\n"),
            .read("A1 OK LOGIN completed\r\n")
        ], tlsVerified: true)
        let client = IMAPClient(
            account: IMAPAccount(
                host: "imap.example.com",
                port: 993,
                username: "user@example.com",
                password: "  pass word  "
            ),
            transport: transport
        )

        try await client.connect()
        try await client.login()
    }

    func testStartTLSFailureIsSurfacedWhenCapabilityIsMissing() async throws {
        let transport = FakeIMAPTransport(script: [
            .read("* OK IMAP4 ready\r\n"),
            .write("A1 CAPABILITY\r\n"),
            .read("* CAPABILITY IMAP4rev1 IDLE\r\n"),
            .read("A1 OK CAPABILITY completed\r\n")
        ])
        let client = IMAPClient(
            account: IMAPAccount(
                host: "imap.example.com",
                port: 143,
                security: .startTLS,
                username: "user@example.com",
                password: "password"
            ),
            transport: transport
        )

        do {
            try await client.connect()
            XCTFail("Expected connect() to fail when STARTTLS is unavailable")
        } catch let error as IMAPError {
            XCTAssertEqual(error, .startTLSUnavailable)
        }
    }

    func testFetchMessageParsesLiteralBodyAndHeaders() async throws {
        let rawMessage = """
        From: Example <noreply@example.com>
        Subject: Your code
        Date: Mon, 22 Jun 2026 12:00:00 +0000

        123456
        """
        let literalLength = rawMessage.utf8.count
        let transport = FakeIMAPTransport(script: [
            .read("* OK IMAP4 ready\r\n"),
            .write("A1 UID FETCH 42 (BODY.PEEK[] INTERNALDATE)\r\n"),
            .read("* 1 FETCH (UID 42 INTERNALDATE \"22-Jun-2026 12:00:00 +0000\" BODY[] {\(literalLength)}\r\n"),
            .read(rawMessage),
            .read("\r\n"),
            .read("A1 OK FETCH completed\r\n")
        ], tlsVerified: true)
        let client = IMAPClient(
            account: IMAPAccount(
                host: "imap.example.com",
                port: 993,
                username: "user@example.com",
                password: "password"
            ),
            transport: transport
        )

        try await client.connect()
        let event = try await client.fetchMessage(uid: 42)

        XCTAssertEqual(event?.uid, 42)
        XCTAssertEqual(event?.sender, "Example <noreply@example.com>")
        XCTAssertEqual(event?.subject, "Your code")
        XCTAssertEqual(event?.plainTextBody, "123456")
    }

    func testFetchMessageRejectsMalformedFetchWithoutLiteral() async throws {
        let transport = FakeIMAPTransport(script: [
            .read("* OK IMAP4 ready\r\n"),
            .write("A1 UID FETCH 42 (BODY.PEEK[] INTERNALDATE)\r\n"),
            .read("* 1 FETCH (UID 42 INTERNALDATE \"22-Jun-2026 12:00:00 +0000\")\r\n"),
            .read("A1 OK FETCH completed\r\n")
        ], tlsVerified: true)
        let client = IMAPClient(
            account: IMAPAccount(
                host: "imap.example.com",
                port: 993,
                username: "user@example.com",
                password: "password"
            ),
            transport: transport
        )

        try await client.connect()

        do {
            _ = try await client.fetchMessage(uid: 42)
            XCTFail("Expected malformed response error")
        } catch let error as IMAPError {
            XCTAssertEqual(error, .malformedResponse("FETCH response did not include a message literal"))
        }
    }

    func testListMailboxesParsesLiteralMailboxName() async throws {
        let transport = FakeIMAPTransport(script: [
            .read("* OK IMAP4 ready\r\n"),
            .write("A1 LIST \"\" \"*\"\r\n"),
            .read("* LIST (\\HasNoChildren) \"/\" {5}\r\n"),
            .read("INBOX"),
            .read("\r\n"),
            .read("* LIST (\\HasNoChildren) \"/\" {5}\r\n"),
            .read("Codes"),
            .read("\r\n"),
            .read("A1 OK LIST completed\r\n")
        ], tlsVerified: true)
        let client = IMAPClient(
            account: IMAPAccount(
                host: "imap.example.com",
                port: 993,
                username: "user@example.com",
                password: "password"
            ),
            transport: transport
        )

        try await client.connect()
        let mailboxes = try await client.listMailboxes()

        XCTAssertEqual(mailboxes, ["INBOX", "Codes"])
    }
}

private final class FakeIMAPTransport: IMAPTransport, @unchecked Sendable {
    enum Step {
        case read(String)
        case write(String)
    }

    private let lock = NSLock()
    private var script: [Step]
    private var tlsVerified: Bool
    private var connected = false

    init(script: [Step] = [], tlsVerified: Bool = false) {
        self.script = script
        self.tlsVerified = tlsVerified
    }

    func connect(
        host: String,
        port: Int,
        security: IMAPAccount.Security,
        serverName: String,
        timeout: TimeInterval
    ) async throws {
        withLock {
            connected = true
        }
    }

    func readSome(timeout: TimeInterval) async throws -> Data? {
        try await Task.sleep(for: .milliseconds(20))
        return try withLock {
            guard connected else {
                throw IMAPError.disconnected
            }
            guard !script.isEmpty else {
                throw IMAPError.timeout("read")
            }
            let step = script.removeFirst()
            switch step {
            case let .read(text):
                return Data(text.utf8)
            case let .write(expected):
                throw IMAPError.malformedResponse("Expected client write \(expected)")
            }
        }
    }

    func write(_ data: Data, timeout: TimeInterval) async throws {
        let written = String(decoding: data, as: UTF8.self)
        try withLock {
            guard connected else {
                throw IMAPError.disconnected
            }
            guard !script.isEmpty else {
                throw IMAPError.malformedResponse("Unexpected client write \(written)")
            }
            let step = script.removeFirst()
            switch step {
            case let .write(expected):
                if written != expected {
                    throw IMAPError.malformedResponse("Expected client write \(expected) but got \(written)")
                }
            case let .read(text):
                throw IMAPError.malformedResponse("Expected server read \(text)")
            }
        }
    }

    func upgradeToTLS(serverName: String, timeout: TimeInterval) async throws {}

    func isTLSVerified() async -> Bool {
        withLock {
            tlsVerified
        }
    }

    func close() async {
        withLock {
            connected = false
        }
    }

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}
