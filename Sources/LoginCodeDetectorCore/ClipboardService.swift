import AppKit
import Foundation

@MainActor
/// Thin wrapper around the macOS pasteboard used for copying detected codes.
public struct ClipboardService {
    public init() {}

    public func copy(_ value: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }
}
