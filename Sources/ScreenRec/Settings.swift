import Foundation

/// Small UserDefaults-backed settings store.
enum Settings {
    private static let folderKey = "saveFolderURL"
    private static let displayKey = "displayID"

    /// Default destination: ~/Movies
    static var defaultFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Movies", isDirectory: true)
    }

    static var saveFolderURL: URL {
        get {
            if let url = UserDefaults.standard.url(forKey: folderKey) {
                return url
            }
            return defaultFolder
        }
        set {
            UserDefaults.standard.set(newValue, forKey: folderKey)
        }
    }

    /// 0 means "first available display".
    static var displayID: Int {
        get { UserDefaults.standard.integer(forKey: displayKey) }
        set { UserDefaults.standard.set(newValue, forKey: displayKey) }
    }
}
