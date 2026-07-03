import Foundation

/// Application version information
enum Version {
    /// Current app version (semantic versioning)
    static let current = "1.0.7"

    /// GitHub repository for update checks
    static let githubOwner = "NorthwoodsCommunityChurch"
    static let githubRepo = "screen-tally"

    /// Asset name pattern for this app
    static let assetPrefix = "ScreenTally-"

    /// Compare two semantic version strings
    /// Returns: negative if v1 < v2, positive if v1 > v2, zero if equal
    static func compare(_ v1: String, _ v2: String) -> Int {
        let clean1 = v1.hasPrefix("v") ? String(v1.dropFirst()) : v1
        let clean2 = v2.hasPrefix("v") ? String(v2.dropFirst()) : v2

        // Split version and pre-release
        let parts1 = clean1.split(separator: "-", maxSplits: 1).map(String.init)
        let parts2 = clean2.split(separator: "-", maxSplits: 1).map(String.init)

        let version1 = parts1[0].split(separator: ".").compactMap { Int($0) }
        let version2 = parts2[0].split(separator: ".").compactMap { Int($0) }

        // Pad versions to same length
        let maxLen = max(version1.count, version2.count)
        let padded1 = version1 + Array(repeating: 0, count: maxLen - version1.count)
        let padded2 = version2 + Array(repeating: 0, count: maxLen - version2.count)

        // Compare numeric parts
        for (a, b) in zip(padded1, padded2) {
            if a != b { return a - b }
        }

        // Same version number - check pre-release
        let prerelease1 = parts1.count > 1 ? parts1[1] : nil
        let prerelease2 = parts2.count > 1 ? parts2[1] : nil

        // Release > pre-release of same version
        if prerelease1 == nil && prerelease2 != nil { return 1 }
        if prerelease1 != nil && prerelease2 == nil { return -1 }

        // Compare pre-release alphabetically
        if let pr1 = prerelease1, let pr2 = prerelease2 {
            return pr1.compare(pr2).rawValue
        }

        return 0
    }
}
