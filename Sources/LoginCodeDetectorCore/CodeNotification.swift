import Foundation

/// Notification-ready representation of a detected code and the mail metadata shown to the user.
public struct CodeNotification: Codable, Equatable, Sendable {
    public let id: String
    public let code: String
    public let sender: String
    public let subject: String
    public let receivedAt: Date
    public let score: Int

    public init(
        id: String = UUID().uuidString,
        code: String,
        sender: String,
        subject: String,
        receivedAt: Date = Date(),
        score: Int
    ) {
        self.id = id
        self.code = code
        self.sender = sender
        self.subject = subject
        self.receivedAt = receivedAt
        self.score = score
    }
}
