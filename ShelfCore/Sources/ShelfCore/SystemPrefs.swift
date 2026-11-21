import Foundation

/// The macOS and Simulator settings the shelf reads (and, for the screenshot
/// preview thumbnail, writes when asked to).
public enum SystemPrefs {
    static let screencapture = "com.apple.screencapture" as CFString
    static let simulator = "com.apple.iphonesimulator" as CFString

    private static func value(_ key: String, in domain: CFString) -> Any? {
        CFPreferencesAppSynchronize(domain)
        return CFPreferencesCopyAppValue(key as CFString, domain)
    }

    private static var desktop: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
    }

    private static func directory(_ raw: Any?) -> URL {
        guard let path = raw as? String, !path.isEmpty else { return desktop }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
    }

    /// Where ⇧⌘3/4/5 save. Defaults to the Desktop.
    public static var screenshotDirectory: URL {
        directory(value("location", in: screencapture))
    }

    /// Where the iOS Simulator's ⌘S saves. Defaults to the Desktop.
    public static var simulatorDirectory: URL {
        directory(value("ScreenShotSaveLocation", in: simulator))
    }

    /// The floating thumbnail macOS shows after a screenshot. While it is on,
    /// the file is only written once the thumbnail goes away (about 5 seconds),
    /// which delays the shelf by the same amount.
    public static var showsScreenshotThumbnail: Bool {
        get { (value("show-thumbnail", in: screencapture) as? Bool) ?? true }
        set {
            CFPreferencesSetAppValue("show-thumbnail" as CFString, newValue as CFBoolean, screencapture)
            CFPreferencesAppSynchronize(screencapture)
        }
    }
}
