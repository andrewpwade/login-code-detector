import Foundation

/// Result of evaluating a message for notification-worthiness.
public enum MessageEvaluation: Equatable, Sendable {
    case noCandidate
    case ignoredLowScore(DetectedCode)
    case detected(CodeNotification)
}

/// Applies extraction and score thresholds to a normalized mail event.
public struct MessageEvaluator: Sendable {
    private let extractor: CodeExtractor

    public init(extractor: CodeExtractor = CodeExtractor()) {
        self.extractor = extractor
    }

    public func evaluate(event: MailEvent, config: AppConfig) -> MessageEvaluation {
        guard let detected = extractor.bestCode(in: event, allowlistedSenders: config.allowlistedSenders) else {
            return .noCandidate
        }

        // Preserve sub-threshold detections for logging and tuning so score changes remain explainable.
        guard detected.score >= config.minimumNotificationScore else {
            return .ignoredLowScore(detected)
        }

        return .detected(
            CodeNotification(
                code: detected.code,
                sender: event.sender,
                subject: event.subject,
                receivedAt: event.receivedAt,
                score: detected.score
            )
        )
    }
}
