import Foundation

/// Decides whether a file that just appeared in a watched folder is a capture
/// the shelf should take.
public enum CaptureClassifier {
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tif", "tiff", "gif", "pdf", "bmp"]
    static let videoExtensions: Set<String> = ["mov", "mp4", "m4v"]

    /// - Parameters:
    ///   - fileName: the file's name, as it appears in the folder.
    ///   - isTaggedScreenCapture: whether macOS marked it as a screen capture
    ///     (`kMDItemIsScreenCapture`). This is the reliable signal, because the
    ///     names macOS gives screenshots are localised.
    public static func classify(fileName: String, isTaggedScreenCapture: Bool) -> ShelfItem.Source? {
        // screencapture writes a hidden ".Screenshot…" file first and renames it.
        guard !fileName.hasPrefix(".") else { return nil }
        let ext = (fileName as NSString).pathExtension.lowercased()
        let isImage = imageExtensions.contains(ext)
        let isVideo = videoExtensions.contains(ext)
        guard isImage || isVideo else { return nil }

        // The Simulator names its files predictably and doesn't tag them.
        if fileName.hasPrefix("Simulator Screenshot") { return isImage ? .simulatorScreenshot : nil }
        if fileName.hasPrefix("Simulator Screen Recording") { return isVideo ? .simulatorRecording : nil }

        let looksLikeCapture = fileName.hasPrefix("Screenshot")
            || fileName.hasPrefix("Screen Shot")
            || fileName.hasPrefix("Screen Recording")
        guard isTaggedScreenCapture || looksLikeCapture else { return nil }
        return isVideo ? .screenRecording : .screenshot
    }

    public static func isTaggedScreenCapture(_ url: URL) -> Bool {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return false }
            return getxattr(path, "com.apple.metadata:kMDItemIsScreenCapture", nil, 0, 0, 0) >= 0
        }
    }
}
