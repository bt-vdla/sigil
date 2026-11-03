import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!

    private let iconStore = IconStore()
    private let customPackStore = CustomPackStore()
    private let shelf = IconShelf()
    private var drawer: DrawerController!

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

        let drawerState = DrawerState()
        drawer = DrawerController(state: drawerState) {
            ContentView(iconStore: iconStore, customPackStore: customPackStore, shelf: shelf, drawer: drawerState)
        }
        drawerState.openSettings = { [weak self] in self?.openSettings() }
        registerHotKey(HotKey.Shortcut.saved)

        setupStatusItem()

        Task { await iconStore.loadIcons() }
    }

    @discardableResult
    private func registerHotKey(_ shortcut: HotKey.Shortcut) -> Bool {
        HotKey.register(shortcut) { [weak self] in self?.drawer.toggle() }
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }

        if let image = NSImage(named: "SigilIcon") {
            image.isTemplate = true  // Template so it respects system appearance
            button.image = image
        } else {
            let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
            button.image = NSImage(systemSymbolName: "seal", accessibilityDescription: "Sigil")?.withSymbolConfiguration(config)
        }

        button.action = #selector(handleStatusItemClick(_:))
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton?) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showRightClickMenu()
        } else {
            drawer.toggle()
        }
    }

    private func showRightClickMenu() {
        let menu = NSMenu()

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Sigil", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    // MARK: - Settings

    @objc private func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 620),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Sigil Settings"
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(
                rootView: SettingsView(
                    customPackStore: customPackStore,
                    iconStore: iconStore,
                    drawer: drawer.state,
                    onShortcutChange: { [weak self] in self?.registerHotKey($0) ?? false }
                )
            )
            window.center()
            settingsWindow = window
        }

        drawer.close()
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
