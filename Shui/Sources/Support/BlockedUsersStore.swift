import Foundation

/// Client-side-only block list — comments from a blocked uid are filtered
/// out locally. Explicitly not a real server-side block (per the phase
/// spec, that's a later decision): a blocked user has no idea they're
/// blocked, and unblocking on a different device doesn't carry over.
enum BlockedUsersStore {
    private static let key = "com.shui.blockedUserIDs"

    static func blockedIDs() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }

    static func block(_ uid: String) {
        var ids = blockedIDs()
        ids.insert(uid)
        UserDefaults.standard.set(Array(ids), forKey: key)
    }

    static func unblock(_ uid: String) {
        var ids = blockedIDs()
        ids.remove(uid)
        UserDefaults.standard.set(Array(ids), forKey: key)
    }

    static func isBlocked(_ uid: String) -> Bool {
        blockedIDs().contains(uid)
    }
}
