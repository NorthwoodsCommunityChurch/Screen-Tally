import Foundation
import Observation
import ServiceManagement

/// Manages persistent app settings via UserDefaults
@Observable
@MainActor
final class AppSettings {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let port = "tslPort"
        static let monitoredSourceIndex = "monitoredSourceIndex"  // Legacy single source
        static let monitoredSourceIndices = "monitoredSourceIndices"  // New multi-source
        static let borderThickness = "borderThickness"
        static let showBorderOnPreview = "showBorderOnPreview"
        static let selectedScreenIndex = "selectedScreenIndex"
    }

    // MARK: - Settings

    /// TSL listener port (default 5201)
    var port: Int {
        didSet {
            defaults.set(port, forKey: Keys.port)
        }
    }

    /// The source indices to monitor for tally (empty = none selected)
    var monitoredSourceIndices: Set<Int> {
        didSet {
            let array = Array(monitoredSourceIndices)
            defaults.set(array, forKey: Keys.monitoredSourceIndices)
        }
    }

    /// Legacy single source support - returns first selected index or nil
    var monitoredSourceIndex: Int? {
        get { monitoredSourceIndices.first }
        set {
            if let index = newValue {
                monitoredSourceIndices = [index]
            } else {
                monitoredSourceIndices = []
            }
        }
    }

    /// Border thickness in points (default 8)
    var borderThickness: Int {
        didSet {
            defaults.set(borderThickness, forKey: Keys.borderThickness)
        }
    }

    /// Whether to show border on preview (default true)
    var showBorderOnPreview: Bool {
        didSet {
            defaults.set(showBorderOnPreview, forKey: Keys.showBorderOnPreview)
        }
    }

    /// Selected screen index (0 = primary/main screen)
    var selectedScreenIndex: Int {
        didSet {
            defaults.set(selectedScreenIndex, forKey: Keys.selectedScreenIndex)
        }
    }

    /// Launch app at login
    var launchAtLogin: Bool {
        get {
            SMAppService.mainApp.status == .enabled
        }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("Failed to \(newValue ? "enable" : "disable") launch at login: \(error)")
            }
        }
    }

    // MARK: - Debug

    /// Debug override for tally state (not persisted). Set to non-nil to override actual tally.
    var debugTallyOverride: TallyState? = nil

    // MARK: - Init

    private init() {
        // Register defaults
        defaults.register(defaults: [
            Keys.port: 5201,
            Keys.borderThickness: 8,
            Keys.showBorderOnPreview: true,
            Keys.selectedScreenIndex: 0
        ])

        // Load saved values
        self.port = defaults.integer(forKey: Keys.port)
        self.borderThickness = defaults.integer(forKey: Keys.borderThickness)
        self.showBorderOnPreview = defaults.bool(forKey: Keys.showBorderOnPreview)
        self.selectedScreenIndex = defaults.integer(forKey: Keys.selectedScreenIndex)

        // Load monitored source indices (with migration from legacy single source)
        if let savedArray = defaults.array(forKey: Keys.monitoredSourceIndices) as? [Int] {
            self.monitoredSourceIndices = Set(savedArray)
        } else if defaults.object(forKey: Keys.monitoredSourceIndex) != nil {
            // Migrate from legacy single source
            let legacyIndex = defaults.integer(forKey: Keys.monitoredSourceIndex)
            self.monitoredSourceIndices = [legacyIndex]
            // Save in new format
            defaults.set([legacyIndex], forKey: Keys.monitoredSourceIndices)
            defaults.removeObject(forKey: Keys.monitoredSourceIndex)
        } else {
            self.monitoredSourceIndices = []
        }
    }
}
