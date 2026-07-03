import Foundation
import Observation
import OSLog
import AppKit

private let log = Logger(subsystem: "com.northwoodschurch.screentally", category: "Update")

/// Manages checking for and applying app updates from GitHub releases
@Observable
@MainActor
final class UpdateManager {
    static let shared = UpdateManager()

    // MARK: - Observable State

    /// Whether an update check is in progress
    private(set) var isChecking = false

    /// Whether an update is being downloaded/applied
    private(set) var isUpdating = false

    /// Latest available version (nil if not checked or same as current)
    private(set) var availableVersion: String?

    /// Download URL for the update
    private(set) var downloadURL: URL?

    /// Human-readable status message
    private(set) var statusMessage: String?

    /// Last error that occurred
    private(set) var lastError: String?

    // MARK: - Private State

    private var lastCheckTime: Date?
    private let checkCooldown: TimeInterval = 900 // 15 minutes

    private init() {}

    // MARK: - Public API

    /// Check for updates from GitHub releases
    func checkForUpdates(force: Bool = false) async {
        // Respect cooldown unless forced
        if !force, let lastCheck = lastCheckTime,
           Date().timeIntervalSince(lastCheck) < checkCooldown {
            log.debug("Skipping update check - within cooldown period")
            return
        }

        isChecking = true
        lastError = nil
        statusMessage = "Checking for updates..."
        defer { isChecking = false }

        lastCheckTime = Date()

        do {
            let release = try await fetchLatestRelease()

            guard let tagName = release["tag_name"] as? String else {
                statusMessage = "Up to date"
                return
            }

            let comparison = Version.compare(tagName, Version.current)
            if comparison > 0 {
                availableVersion = tagName
                downloadURL = findAssetURL(in: release)
                statusMessage = "Update available: \(tagName)"
                log.info("Update available: \(tagName)")
            } else {
                availableVersion = nil
                downloadURL = nil
                statusMessage = "Up to date"
                log.info("No update available (current: \(Version.current), latest: \(tagName))")
            }
        } catch {
            lastError = error.localizedDescription
            statusMessage = "Check failed"
            log.error("Update check failed: \(error.localizedDescription)")
        }
    }

    /// Download and apply the available update
    func applyUpdate() async {
        guard let url = downloadURL, let version = availableVersion else {
            lastError = "No update available"
            return
        }

        isUpdating = true
        lastError = nil
        statusMessage = "Downloading update..."
        defer { isUpdating = false }

        do {
            // Download the zip
            let (zipURL, _) = try await URLSession.shared.download(from: url)
            statusMessage = "Installing update..."

            // Apply the update via trampoline
            try await installUpdate(from: zipURL, version: version)

        } catch {
            lastError = error.localizedDescription
            statusMessage = "Update failed"
            log.error("Update failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Private Methods

    private func fetchLatestRelease() async throws -> [String: Any] {
        let urlString = "https://api.github.com/repos/\(Version.githubOwner)/\(Version.githubRepo)/releases/latest"
        guard let url = URL(string: urlString) else {
            throw UpdateError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw UpdateError.invalidResponse
        }

        if httpResponse.statusCode == 404 {
            throw UpdateError.noReleases
        }

        guard httpResponse.statusCode == 200 else {
            throw UpdateError.httpError(httpResponse.statusCode)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UpdateError.invalidJSON
        }

        return json
    }

    private func findAssetURL(in release: [String: Any]) -> URL? {
        guard let assets = release["assets"] as? [[String: Any]] else { return nil }

        // Look for our asset pattern
        for asset in assets {
            guard let name = asset["name"] as? String,
                  name.hasPrefix(Version.assetPrefix),
                  name.hasSuffix(".zip"),
                  let urlString = asset["browser_download_url"] as? String,
                  let url = URL(string: urlString) else { continue }
            return url
        }

        return nil
    }

    private func installUpdate(from zipURL: URL, version: String) async throws {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Unzip
        let unzipProcess = Process()
        unzipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzipProcess.arguments = ["-q", zipURL.path, "-d", tempDir.path]
        try unzipProcess.run()
        unzipProcess.waitUntilExit()

        guard unzipProcess.terminationStatus == 0 else {
            throw UpdateError.unzipFailed
        }

        // Find the .app in the extracted contents
        let contents = try fileManager.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
        guard let newAppURL = contents.first(where: { $0.pathExtension == "app" }) else {
            throw UpdateError.noAppInZip
        }

        // Get current app bundle location
        guard let currentAppURL = Bundle.main.bundleURL.deletingLastPathComponent() as URL?,
              Bundle.main.bundlePath.hasSuffix(".app") else {
            throw UpdateError.notRunningFromApp
        }

        let currentApp = Bundle.main.bundleURL

        // Create trampoline script
        let scriptURL = tempDir.appendingPathComponent("update.sh")
        let script = createTrampolineScript(
            pid: ProcessInfo.processInfo.processIdentifier,
            oldApp: currentApp,
            newApp: newAppURL,
            tempDir: tempDir
        )

        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        // Launch trampoline and quit
        log.info("Launching update trampoline")
        let trampolineProcess = Process()
        trampolineProcess.executableURL = URL(fileURLWithPath: "/bin/bash")
        trampolineProcess.arguments = [scriptURL.path]
        trampolineProcess.standardOutput = FileHandle.nullDevice
        trampolineProcess.standardError = FileHandle.nullDevice
        try trampolineProcess.run()

        // Give the script a moment to start
        try await Task.sleep(for: .milliseconds(100))

        // Quit the app
        log.info("Quitting for update to \(version)")
        NSApplication.shared.terminate(nil)
    }

    private func createTrampolineScript(pid: Int32, oldApp: URL, newApp: URL, tempDir: URL) -> String {
        """
        #!/bin/bash
        # Screen Tally Update Trampoline

        # Wait for the app to quit
        while kill -0 \(pid) 2>/dev/null; do
            sleep 0.5
        done

        # Remove old app
        rm -rf "\(oldApp.path)"

        # Move new app into place
        mv "\(newApp.path)" "\(oldApp.path)"

        # Re-sign ad-hoc
        codesign --force --deep --sign - "\(oldApp.path)"

        # Clear quarantine
        xattr -cr "\(oldApp.path)"

        # Relaunch
        open "\(oldApp.path)"

        # Cleanup
        rm -rf "\(tempDir.path)"
        """
    }
}

// MARK: - Errors

enum UpdateError: LocalizedError {
    case invalidURL
    case invalidResponse
    case noReleases
    case httpError(Int)
    case invalidJSON
    case unzipFailed
    case noAppInZip
    case notRunningFromApp

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid update URL"
        case .invalidResponse:
            return "Invalid server response"
        case .noReleases:
            return "No releases found"
        case .httpError(let code):
            return "Server error: \(code)"
        case .invalidJSON:
            return "Invalid release data"
        case .unzipFailed:
            return "Failed to extract update"
        case .noAppInZip:
            return "No app found in update"
        case .notRunningFromApp:
            return "Not running from app bundle"
        }
    }
}
