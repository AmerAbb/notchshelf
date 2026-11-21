import Foundation
import UniformTypeIdentifiers

/// One thing parked on the shelf. The file itself lives in the shelf directory
/// under `fileName`; this is the bookkeeping kept alongside it.
public struct ShelfItem: Codable, Identifiable, Hashable, Sendable {
    public enum Source: String, Codable, Sendable {
        case screenshot
        case screenRecording
        case simulatorScreenshot
        case simulatorRecording
        /// Dragged onto the notch by hand.
        case dropped
    }

    public enum Kind: Sendable {
        case image, video, other
    }

    public let id: UUID
    public var fileName: String
    public var addedAt: Date
    public var source: Source
    public var pinned: Bool

    public init(id: UUID = UUID(), fileName: String, addedAt: Date, source: Source, pinned: Bool = false) {
        self.id = id
        self.fileName = fileName
        self.addedAt = addedAt
        self.source = source
        self.pinned = pinned
    }

    public var kind: Kind {
        let ext = (fileName as NSString).pathExtension
        guard let type = UTType(filenameExtension: ext) else { return .other }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .audiovisualContent) { return .video }
        return .other
    }

    public var isFromSimulator: Bool {
        source == .simulatorScreenshot || source == .simulatorRecording
    }
}

public enum RelativeTime {
    /// Compact age for a thumbnail caption: "now", "4m", "3h", "2d".
    public static func short(_ date: Date, now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<45: return "now"
        case ..<3600: return "\(max(1, Int((seconds / 60).rounded())))m"
        case ..<86_400: return "\(Int(seconds / 3600))h"
        default: return "\(Int(seconds / 86_400))d"
        }
    }
}
