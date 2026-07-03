import AppKit
import SwiftUI
import Sparkle

/// Manages the menu bar status item and popover
@MainActor
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private var eventMonitor: Any?

    var tslListener: TSLListener?
    var updater: SPUUpdater?

    // MARK: - Init

    override init() {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()

        super.init()

        setupStatusItem()
        setupEventMonitor()
    }

    func configure(tslListener: TSLListener, updater: SPUUpdater) {
        self.tslListener = tslListener
        self.updater = updater
        setupPopover()
    }

    // MARK: - Setup

    private func setupStatusItem() {
        guard let button = statusItem.button else { return }

        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        // Set initial icon
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let image = NSImage(systemSymbolName: "circle", accessibilityDescription: "Tally Status")?
            .withSymbolConfiguration(config)
        image?.isTemplate = true
        button.image = image
    }

    private func setupPopover() {
        guard let listener = tslListener else { return }

        popover.contentSize = NSSize(width: 280, height: 400)
        popover.behavior = .transient
        popover.animates = true

        let menuBarView = MenuBarView(tslListener: listener)
        popover.contentViewController = NSHostingController(rootView: menuBarView)
    }

    private func setupEventMonitor() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            if self?.popover.isShown == true {
                self?.popover.performClose(nil)
            }
        }
    }

    // MARK: - Icon Updates

    func updateIcon(for tally: TallyState, isConnected: Bool) {
        guard let button = statusItem.button else { return }

        let symbolName: String
        if !isConnected {
            symbolName = "circle"
        } else {
            symbolName = "circle.fill"
        }

        let color: NSColor
        if !isConnected {
            color = .white
        } else {
            switch tally {
            case .program, .previewProgram:
                color = .systemRed
            case .preview:
                color = .systemGreen
            case .clear:
                color = .white
            }
        }

        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            .applying(.init(paletteColors: [color]))

        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Tally Status")?
            .withSymbolConfiguration(config) {
            image.isTemplate = false
            button.image = image
        }
    }

    // MARK: - Click Handling

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit Screen Tally", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
        statusItem.button?.performClick(nil)

        DispatchQueue.main.async { [weak self] in
            self?.statusItem.menu = nil
        }
    }

    // MARK: - Cleanup

    func teardown() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}
