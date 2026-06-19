import Foundation
import Security

/// `Stream`-based IMAP transport used by the default client implementation.
/// It encapsulates run-loop scheduling, TLS promotion, and polling-based read/write coordination.
final class StreamIMAPTransport: NSObject, IMAPTransport, StreamDelegate, @unchecked Sendable {
    private static let pollInterval = Duration.milliseconds(50)

    private let state = StreamTransportState()
    private var inputStream: InputStream?
    private var outputStream: OutputStream?

    func connect(
        host: String,
        port: Int,
        security: IMAPAccount.Security,
        serverName: String,
        timeout: TimeInterval
    ) async throws {
        state.prepareForNewConnection()
        var readStream: InputStream?
        var writeStream: OutputStream?
        Stream.getStreamsToHost(withName: host, port: port, inputStream: &readStream, outputStream: &writeStream)
        guard let readStream, let writeStream else {
            throw IMAPError.disconnected
        }

        inputStream = readStream
        outputStream = writeStream
        readStream.delegate = self
        writeStream.delegate = self
        StreamRunLoop.shared.schedule(readStream)
        StreamRunLoop.shared.schedule(writeStream)
        if security == .implicitTLS {
            Self.configureTLS(readStream: readStream, writeStream: writeStream, serverName: serverName)
        }

        readStream.open()
        writeStream.open()
        try await pollUntil(timeout: timeout, timeoutError: .timeout("connect")) {
            if let terminal = state.terminalErrorIfKnown() {
                throw terminal
            }
            return state.openCountValue() >= 2
        }
    }

    func readSome(timeout: TimeInterval) async throws -> Data? {
        guard let inputStream else {
            throw IMAPError.disconnected
        }

        return try await pollUntilResult(timeout: timeout, timeoutError: .timeout("read")) {
            if let terminal = state.terminalErrorIfKnown() {
                throw terminal
            }
            if state.isEnded() && !inputStream.hasBytesAvailable {
                return .ready(nil)
            }
            guard inputStream.hasBytesAvailable else {
                return .pending
            }

            var bytes = [UInt8](repeating: 0, count: 65_536)
            let count = inputStream.read(&bytes, maxLength: bytes.count)
            if count > 0 {
                refreshTLSVerification()
                return .ready(Data(bytes.prefix(count)))
            }
            if count == 0 {
                state.markEnded()
                return .ready(nil)
            }
            throw inputStream.streamError ?? IMAPError.disconnected
        }
    }

    func write(_ data: Data, timeout: TimeInterval) async throws {
        guard let outputStream else {
            throw IMAPError.disconnected
        }

        var totalWritten = 0
        try await pollUntil(timeout: timeout, timeoutError: .timeout("write")) {
            if let terminal = state.terminalErrorIfKnown() {
                throw terminal
            }
            guard totalWritten < data.count else {
                refreshTLSVerification()
                return true
            }
            guard outputStream.hasSpaceAvailable else {
                return false
            }

            let written = data.withUnsafeBytes { bytes in
                outputStream.write(
                    bytes.baseAddress!.assumingMemoryBound(to: UInt8.self).advanced(by: totalWritten),
                    maxLength: data.count - totalWritten
                )
            }
            if written > 0 {
                totalWritten += written
                return totalWritten >= data.count
            }
            if written < 0 {
                throw outputStream.streamError ?? IMAPError.disconnected
            }
            return false
        }
    }

    func upgradeToTLS(serverName: String, timeout: TimeInterval) async throws {
        guard let inputStream, let outputStream else {
            throw IMAPError.disconnected
        }

        Self.configureTLS(readStream: inputStream, writeStream: outputStream, serverName: serverName)
        try await pollUntil(timeout: timeout, timeoutError: .timeout("starttls")) {
            refreshTLSVerification()
            if let terminal = state.terminalErrorIfKnown() {
                throw terminal
            }
            return state.isTLSVerified()
        }
    }

    func isTLSVerified() async -> Bool {
        state.isTLSVerified()
    }

    func close() async {
        inputStream?.close()
        outputStream?.close()
        if let inputStream {
            StreamRunLoop.shared.unschedule(inputStream)
        }
        if let outputStream {
            StreamRunLoop.shared.unschedule(outputStream)
        }
        inputStream = nil
        outputStream = nil
        state.close()
    }

    func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        if eventCode.contains(.openCompleted) {
            state.markOpen()
        }
        if eventCode.contains(.endEncountered) {
            state.markEnded()
        }
        if eventCode.contains(.errorOccurred) {
            state.fail(aStream.streamError ?? IMAPError.disconnected)
        }
        refreshTLSVerification()
    }

    private func refreshTLSVerification() {
        state.setTLSVerified(Self.isPeerTrustVerified(in: inputStream) || Self.isPeerTrustVerified(in: outputStream))
    }

    private func pollUntil(
        timeout: TimeInterval,
        timeoutError: IMAPError,
        check: () throws -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if try check() {
                return
            }
            try Task.checkCancellation()
            try await Task.sleep(for: Self.pollInterval)
        }
        throw timeoutError
    }

    private func pollUntilResult<T>(
        timeout: TimeInterval,
        timeoutError: IMAPError,
        check: () throws -> PollResult<T>
    ) async throws -> T {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            switch try check() {
            case let .ready(value):
                return value
            case .pending:
                try Task.checkCancellation()
                try await Task.sleep(for: Self.pollInterval)
            }
        }
        throw timeoutError
    }

    private static func configureTLS(readStream: InputStream, writeStream: OutputStream, serverName: String) {
        let settings: [String: NSObject] = [
            kCFStreamSSLPeerName as String: serverName as NSString,
            kCFStreamSSLValidatesCertificateChain as String: kCFBooleanTrue
        ]
        let sslSettingsKey = Stream.PropertyKey(rawValue: kCFStreamPropertySSLSettings as String)
        readStream.setProperty(settings, forKey: sslSettingsKey)
        writeStream.setProperty(settings, forKey: sslSettingsKey)
        readStream.setProperty(StreamSocketSecurityLevel.negotiatedSSL, forKey: .socketSecurityLevelKey)
        writeStream.setProperty(StreamSocketSecurityLevel.negotiatedSSL, forKey: .socketSecurityLevelKey)
    }

    private static func isPeerTrustVerified(in stream: Stream?) -> Bool {
        guard let stream else {
            return false
        }
        let key = Stream.PropertyKey(rawValue: kCFStreamPropertySSLPeerTrust as String)
        guard let trust = stream.property(forKey: key) else {
            return false
        }
        let trustRef = trust as CFTypeRef
        guard CFGetTypeID(trustRef) == SecTrustGetTypeID() else {
            return false
        }
        return SecTrustEvaluateWithError(trustRef as! SecTrust, nil)
    }
}

/// Internal polling state used by the stream transport's timeout loops.
private enum PollResult<T> {
    case pending
    case ready(T)
}
