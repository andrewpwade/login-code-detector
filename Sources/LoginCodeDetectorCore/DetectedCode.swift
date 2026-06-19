import Foundation

/// A candidate code extracted from a message together with its confidence score and scoring rationale.
public struct DetectedCode: Equatable, Sendable {
    public let code: String
    public let score: Int
    public let reason: String
    public let sourceRange: Range<String.Index>

    public init(code: String, score: Int, reason: String, sourceRange: Range<String.Index>) {
        self.code = code
        self.score = score
        self.reason = reason
        self.sourceRange = sourceRange
    }
}

/// Normalized mail data passed through extraction and notification policy.
public struct MailEvent: Equatable, Sendable {
    public let uid: UInt64
    public let sender: String
    public let subject: String
    public let receivedAt: Date
    public let plainTextBody: String
    public let htmlBody: String?

    public init(
        uid: UInt64,
        sender: String,
        subject: String,
        receivedAt: Date,
        plainTextBody: String,
        htmlBody: String? = nil
    ) {
        self.uid = uid
        self.sender = sender
        self.subject = subject
        self.receivedAt = receivedAt
        self.plainTextBody = plainTextBody
        self.htmlBody = htmlBody
    }
}
