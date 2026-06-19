import Foundation

/// Timeout defaults for low-level IMAP transport operations.
public enum IMAPRuntimeDefaults {
    public static let idleTimeoutSeconds: UInt64 = 29 * 60
    public static let connectTimeoutSeconds: TimeInterval = 10
    public static let readTimeoutSeconds: TimeInterval = 10
    public static let writeTimeoutSeconds: TimeInterval = 10
    public static let commandTimeoutSeconds: TimeInterval = 20
}

/// Transport abstraction beneath `IMAPClient` so protocol logic can be tested without real sockets.
protocol IMAPTransport: Sendable {
    func connect(
        host: String,
        port: Int,
        security: IMAPAccount.Security,
        serverName: String,
        timeout: TimeInterval
    ) async throws
    func readSome(timeout: TimeInterval) async throws -> Data?
    func write(_ data: Data, timeout: TimeInterval) async throws
    func upgradeToTLS(serverName: String, timeout: TimeInterval) async throws
    func isTLSVerified() async -> Bool
    func close() async
}

/// Shared mutable stream state guarded by a lock for the run-loop-based transport implementation.
final class StreamTransportState: @unchecked Sendable {
    private let lock = NSLock()
    private var openCount = 0
    private var terminalError: (any Error)?
    private var ended = false
    private var tlsVerified = false

    func prepareForNewConnection() {
        withLock {
            openCount = 0
            terminalError = nil
            ended = false
            tlsVerified = false
        }
    }

    func markOpen() {
        withLock {
            openCount += 1
        }
    }

    func openCountValue() -> Int {
        withLock { openCount }
    }

    func markEnded() {
        withLock {
            ended = true
        }
    }

    func fail(_ error: any Error) {
        withLock {
            terminalError = error
        }
    }

    func terminalErrorIfKnown() -> (any Error)? {
        withLock { terminalError }
    }

    func isEnded() -> Bool {
        withLock { ended }
    }

    func isTLSVerified() -> Bool {
        withLock { tlsVerified }
    }

    func setTLSVerified(_ value: Bool) {
        withLock {
            tlsVerified = value
        }
    }

    func close() {
        withLock {
            ended = true
        }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
