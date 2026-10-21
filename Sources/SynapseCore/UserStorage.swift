import Foundation

/// Path safety without lossy identity normalization. Existing space-named
/// directories remain in place; ambiguous historical aliases need an explicit
/// choice by the owner, not an automatic migration that could claim another user.
enum UserStorage {
    enum ValidationError: LocalizedError {
        case invalidIdentifier
        case ambiguousLegacy(String)
        case conflictingOwner

        var errorDescription: String? {
            switch self {
            case .invalidIdentifier:
                return "Use a single name containing a letter or digit, without path separators, colon, or control characters (at most 200 UTF-8 bytes)."
            case .ambiguousLegacy(let key):
                return "Existing state uses the legacy name '\(key)'. Select that stored name explicitly or back up and rename its directory; ownership cannot be inferred safely."
            case .conflictingOwner:
                return "This directory belongs to a different identifier. Use its exact stored name."
            }
        }
    }

    static func validate(_ user: String, usersDir: URL) throws {
        let forbidden = CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "/\\:"))
        guard !user.isEmpty, user.utf8.count <= 200,
              user.rangeOfCharacter(from: forbidden) == nil,
              user.rangeOfCharacter(from: .alphanumerics) != nil,
              // The nonthrowing built-in default initializer owns this namespace.
              user.lowercased() != "default" || user == "default" else {
            throw ValidationError.invalidIdentifier
        }
        let fm = FileManager.default
        let directory = usersDir.appendingPathComponent(user)
        if fm.fileExists(atPath: directory.path) {
            // Refuse case/normalization aliases on case-insensitive volumes even
            // if the old directory has no profile. Never overwrite its identity.
            let names = try fm.contentsOfDirectory(atPath: usersDir.path)
            guard names.contains(user) else { throw ValidationError.conflictingOwner }
            let profileURL = directory.appendingPathComponent("profile.json")
            if fm.fileExists(atPath: profileURL.path) {
                let profile = try JSONDecoder().decode(UserProfile.self, from: Data(contentsOf: profileURL))
                guard profile.id == user else { throw ValidationError.conflictingOwner }
            }
        } else {
            let legacy = user.components(separatedBy: CharacterSet(charactersIn: "/\\:.")).joined()
            if legacy != user, !legacy.isEmpty,
               fm.fileExists(atPath: usersDir.appendingPathComponent(legacy).path) {
                throw ValidationError.ambiguousLegacy(legacy)
            }
        }
    }
}
