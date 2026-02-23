import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()

    private let iconStore = IconStore()
    private let customPackStore = CustomPackStore()

    private var eventMonitor: Any?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Wire pack lifecycle callbacks before loading from disk
        customPackStore.onPackAdded = { [weak self] pack in
            guard let self else { return }
            let dir = self.customPackStore.packDirectory(for: pack.id)
            Task { await self.iconStore.loadCustomPack(pack, svgDirectory: dir) }
        }
        customPackStore.onPackRemoved = { [weak self] id in
            self?.iconStore.unloadCustomPack(id: id)
        }

        // Scan Packs/ directory and load any previously imported custom packs
        customPackStore.loadFromDisk()
        for pack in customPackStore.packs {
            let dir = customPackStore.packDirectory(for: pack.id)
            Task { await iconStore.loadCustomPack(pack, svgDirectory: dir) }
        }

        setupStatusItem()
        setupPopover()
        setupGlobalEventMonitor()

        Task { await iconStore.loadIcons() }
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }

        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        if let image = NSImage(systemSymbolName: "seal", accessibilityDescription: "Sigil") {
            button.image = image.withSymbolConfiguration(config)
        }

        button.action = #selector(handleStatusItemClick(_:))
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    // MARK: - Click Handling

    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton?) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showRightClickMenu()
        } else {
            togglePopover()
        }
    }

    private func showRightClickMenu() {
        let menu = NSMenu()

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit Sigil",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    // MARK: - Settings

    @objc private func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 540),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Sigil Settings"
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(
                rootView: SettingsView(
                    customPackStore: customPackStore,
                    iconStore: iconStore
                )
            )
            window.center()
            settingsWindow = window
        }

        if popover.isShown { popover.performClose(nil) }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Popover

    private func setupPopover() {
        let contentView = ContentView(
            iconStore: iconStore,
            customPackStore: customPackStore,
            openPacksSettings: { [weak self] in
                self?.openSettings()
            }
        )
        popover.contentSize = NSSize(width: 400, height: 520)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: contentView)
        popover.delegate = self
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: - Global Event Monitor

    private func setupGlobalEventMonitor() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            guard let self, self.popover.isShown else { return }
            self.popover.performClose(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    // MARK: - NSPopoverDelegate

    func popoverDidClose(_ notification: Notification) {}
}
