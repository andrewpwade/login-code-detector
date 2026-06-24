import Foundation
import Network

/// `NWConnection`-based IMAP transport for implicit TLS sessions.
/// Network.framework gives the app explicit connection states and avoids the run-loop races that can occur with
/// Foundation streams during startup. STARTTLS still uses `StreamIMAPTransport` because it must upgrade an
/// already-open plaintext connection in place.
final class NetworkIMAPTransport: IMAPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var connection: NWConnection?
    private var isReady = false
    private var terminalError: (any Error)?

    func connect(
        host: String,
        port: Int,
        security: IMAPAccount.Security,
        serverName: String,
        timeout: TimeInterval
    ) async throws {
        guard security == .implicitTLS else {
            throw IMAPError.startTLSUnavailable
        }
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            throw IMAPError.disconnected
        }

        let tlsOptions = NWProtocolTLS.Options()
        sec_protocol_options_set_tls_server_name(
            tlsOptions.securityProtocolOptions,
            serverName
        )
        let parameters = NWParameters(tls: tlsOptions)
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: parameters)

        withLock {
            self.connection = connection
            self.isReady = false
            self.terminalError = nil
        }

        try await withTimeout(seconds: timeout, timeoutError: IMAPError.timeout("connect")) {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let box = ResumeBox<Void>()
                connection.stateUpdateHandler = { [weak self] state in
                    switch state {
                    case .ready:
                        self?.setReady()
                        box.resume(continuation, returning: ())
                    case let .failed(error), let .waiting(error):
                        self?.setFailed(error)
                        box.resume(continuation, throwing: error)
                    case .cancelled:
                        self?.setFailed(IMAPError.disconnected)
                        box.resume(continuation, throwing: IMAPError.disconnected)
                    default:
                        break
                    }
                }
                connection.start(queue: .global(qos: .utility))
            }
        }
    }

    func readSome(timeout: TimeInterval) async throws -> Data? {
        let connection = try currentConnection()
        if let error = terminalErrorIfKnown() {
            throw error
        }

        return try await withTimeout(seconds: timeout, timeoutError: IMAPError.timeout("read")) {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data?, any Error>) in
                let box = ResumeBox<Data?>()
                connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
                    if let error {
                        self?.setFailed(error)
                        box.resume(continuation, throwing: error)
                    } else if let data, !data.isEmpty {
                        box.resume(continuation, returning: data)
                    } else if isComplete {
                        box.resume(continuation, returning: nil)
                    } else {
                        box.resume(continuation, throwing: IMAPError.disconnected)
                    }
                }
            }
        }
    }

    func write(_ data: Data, timeout: TimeInterval) async throws {
        let connection = try currentConnection()
        if let error = terminalErrorIfKnown() {
            throw error
        }

        try await withTimeout(seconds: timeout, timeoutError: IMAPError.timeout("write")) {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let box = ResumeBox<Void>()
                connection.send(content: data, completion: .contentProcessed { [weak self] error in
                    if let error {
                        self?.setFailed(error)
                        box.resume(continuation, throwing: error)
                    } else {
                        box.resume(continuation, returning: ())
                    }
                })
            }
        }
    }

    func upgradeToTLS(serverName: String, timeout: TimeInterval) async throws {
        throw IMAPError.startTLSUnavailable
    }

    func isTLSVerified() async -> Bool {
        withLock {
            isReady && terminalError == nil
        }
    }

    func close() async {
        let connection = withLock {
            let current = self.connection
            self.connection = nil
            self.isReady = false
            self.terminalError = IMAPError.disconnected
            return current
        }
        connection?.cancel()
    }

    private func currentConnection() throws -> NWConnection {
        try withLock {
            guard let connection else {
                throw IMAPError.disconnected
            }
            return connection
        }
    }

    private func setReady() {
        withLock {
            isReady = true
            terminalError = nil
        }
    }

    private func setFailed(_ error: any Error) {
        withLock {
            terminalError = error
        }
    }

    private func terminalErrorIfKnown() -> (any Error)? {
        withLock {
            terminalError
        }
    }

    private func withTimeout<T: Sendable>(
        seconds: TimeInterval,
        timeoutError: IMAPError,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(for: .milliseconds(Int(seconds * 1_000)))
                throw timeoutError
            }
            guard let result = try await group.next() else {
                throw timeoutError
            }
            group.cancelAll()
            return result
        }
    }

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}

private final class ResumeBox<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false

    func resume(_ continuation: CheckedContinuation<T, any Error>, returning value: T) {
        guard markResumed() else {
            return
        }
        continuation.resume(returning: value)
    }

    func resume(_ continuation: CheckedContinuation<T, any Error>, throwing error: any Error) {
        guard markResumed() else {
            return
        }
        continuation.resume(throwing: error)
    }

    private func markResumed() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !didResume else {
            return false
        }
        didResume = true
        return true
    }
}
