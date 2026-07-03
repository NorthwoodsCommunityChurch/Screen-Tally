import AppKit
import Observation
import Sparkle

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor private var tslListener: TSLListener!
    @MainActor private var statusBarController: StatusBarController!
    @MainActor private var borderOverlayController: BorderOverlayController!
    private var observationTask: Task<Void, Never>?

    /// Sparkle updater controller - manages automatic update checks
    private var updaterController: SPUStandardUpdaterController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async { [self] in
            // Initialize Sparkle
            updaterController = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )

            // Initialize components
            MainActor.assumeIsolated {
                statusBarController = StatusBarController()
                tslListener = TSLListener()
                statusBarController.configure(tslListener: tslListener, updater: updaterController.updater)

                borderOverlayController = BorderOverlayController()
                borderOverlayController.setup()

                tslListener.startListening(port: UInt16(AppSettings.shared.port))

                startObserving()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        observationTask?.cancel()
        Task { @MainActor in
            statusBarController?.teardown()
            tslListener?.stopListening()
            borderOverlayController?.teardown()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        return true
    }

    // MARK: - Observation

    @MainActor private func startObserving() {
        observationTask = Task { @MainActor in
            while !Task.isCancelled {
                withObservationTracking {
                    let settings = AppSettings.shared
                    let liveTally = tslListener.monitoredTally
                    let isConnected = tslListener.isConnected
                    let _ = settings.showBorderOnPreview
                    let _ = settings.borderThickness

                    let tally = settings.debugTallyOverride ?? liveTally

                    statusBarController.updateIcon(for: tally, isConnected: isConnected || settings.debugTallyOverride != nil)
                    borderOverlayController.updateTally(tally)
                } onChange: {
                    // Continue loop on change
                }

                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }
}
