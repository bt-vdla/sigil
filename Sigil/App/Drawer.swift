import AppKit
import Carbon.HIToolbox
import SwiftUI

enum DrawerSide: String, CaseIterable {
    case left, right
}

/// Shared between the drawer window and the SwiftUI content inside it.
@Observable
final class DrawerState {
    /// Closed longer than this, the next open starts from an empty search.
    static let resetAfter: TimeInterval = 30

    var isOpen = false
    var isPinned = false
    var side = DrawerSide(rawValue: UserDefaults.standard.string(forKey: "drawerSide") ?? "") ?? .left {
        didSet { UserDefaults.standard.set(side.rawValue, forKey: "drawerSide") }
    }
    /// Bumped when the content should drop its search, selection and scroll position.
    var resetToken = 0

    @ObservationIgnored var keyHandler: ((NSEvent) -> Bool)?
    @ObservationIgnored var close: () -> Void = {}
    @ObservationIgnored var openSettings: () -> Void = {}
}

/// Borderless panel that takes typing without activating Sigil, so the app the
/// user came from stays frontmost (and is where the copied icon gets pasted).
private final class DrawerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class DrawerController {
    static let width: CGFloat = 452

    let state: DrawerState
    private let panel: DrawerPanel
    private var mouseMonitor: Any?
    private var keyMonitor: Any?
    private var closedAt = Date.distantPast
    private var hideWork: DispatchWorkItem?

    init<Content: View>(state: DrawerState, @ViewBuilder content: () -> Content) {
        self.state = state
        panel = DrawerPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: DrawerView(state: state, content: content()))

        state.close = { [weak self] in self?.close() }

        // Clicking anywhere outside takes key status from the panel, in any app or Sigil's own windows
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            // The key window is only updated after this notification
            DispatchQueue.main.async { self?.closeUnlessPinned() }
        }
    }

    func toggle() {
        // A status item click can take focus first; don't let that close-then-toggle reopen the drawer
        if !state.isOpen, Date().timeIntervalSince(closedAt) < 0.25 { return }
        state.isOpen ? close() : open()
    }

    private func closeUnlessPinned() {
        // The color panel is part of the drawer's customization controls. While it's up, the
        // global mouse monitor still closes the drawer on clicks in other apps.
        let colorPanelOpen = NSColorPanel.sharedColorPanelExists && NSColorPanel.shared.isVisible
        guard !state.isPinned, !panel.isKeyWindow, !colorPanelOpen else { return }
        close()
    }

    func open() {
        hideWork?.cancel()
        if let app = NSWorkspace.shared.frontmostApplication, app != .current {
            CopyService.targetApp = app
        }

        // Open on the screen the pointer is on, pinned to its edge
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        guard let screen else { return }
        let visible = screen.visibleFrame
        let height = min(visible.height - 40, 820)
        let x = state.side == .left ? screen.frame.minX : screen.frame.maxX - Self.width
        panel.setFrame(NSRect(x: x, y: visible.midY - height / 2, width: Self.width, height: height), display: false)

        if Date().timeIntervalSince(closedAt) > DrawerState.resetAfter {
            state.resetToken += 1
        }
        panel.orderFrontRegardless()
        panel.makeKey()
        state.isOpen = true
        installMonitors()
    }

    func close() {
        guard state.isOpen else { return }
        state.isOpen = false
        state.isPinned = false
        closedAt = Date()
        removeMonitors()
        // Let the morph finish before the window goes away
        let work = DispatchWorkItem { [weak self] in self?.panel.orderOut(nil) }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
    }

    private func installMonitors() {
        removeMonitors()
        // Catches clicks that don't move focus, such as on the desktop or the Dock
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, !self.state.isPinned else { return }
            self.close()
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            return self.state.keyHandler?(event) == true ? nil : event
        }
    }

    private func removeMonitors() {
        [mouseMonitor, keyMonitor].compactMap { $0 }.forEach(NSEvent.removeMonitor)
        mouseMonitor = nil
        keyMonitor = nil
    }
}

// MARK: - Global hotkey

/// System-wide shortcut via Carbon: works in the sandbox and needs no Accessibility permission.
enum HotKey {
    struct Shortcut: Equatable {
        var keyCode: UInt32
        var modifiers: NSEvent.ModifierFlags
        var keyName: String

        static let `default` = Shortcut(keyCode: UInt32(kVK_Space), modifiers: [.control, .shift], keyName: "Space")

        var display: String {
            var s = ""
            if modifiers.contains(.control) { s += "⌃" }
            if modifiers.contains(.option) { s += "⌥" }
            if modifiers.contains(.shift) { s += "⇧" }
            if modifiers.contains(.command) { s += "⌘" }
            return s + keyName
        }

        var carbonModifiers: UInt32 {
            var m: UInt32 = 0
            if modifiers.contains(.command) { m |= UInt32(cmdKey) }
            if modifiers.contains(.option) { m |= UInt32(optionKey) }
            if modifiers.contains(.control) { m |= UInt32(controlKey) }
            if modifiers.contains(.shift) { m |= UInt32(shiftKey) }
            return m
        }

        static var saved: Shortcut {
            let d = UserDefaults.standard
            guard d.object(forKey: "hotKeyCode") != nil else { return .default }
            return Shortcut(
                keyCode: UInt32(d.integer(forKey: "hotKeyCode")),
                modifiers: NSEvent.ModifierFlags(rawValue: UInt(d.integer(forKey: "hotKeyModifiers"))),
                keyName: d.string(forKey: "hotKeyName") ?? "?"
            )
        }

        func save() {
            let d = UserDefaults.standard
            d.set(Int(keyCode), forKey: "hotKeyCode")
            d.set(Int(modifiers.rawValue), forKey: "hotKeyModifiers")
            d.set(keyName, forKey: "hotKeyName")
        }
    }

    private static var ref: EventHotKeyRef?
    private static var action: (() -> Void)?
    private static var handlerInstalled = false

    /// Returns false when another app already owns the shortcut.
    @discardableResult
    static func register(_ shortcut: Shortcut, action: @escaping () -> Void) -> Bool {
        self.action = action
        if !handlerInstalled {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async { HotKey.action?() }
                return noErr
            }, 1, &spec, nil, nil)
            handlerInstalled = true
        }
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        let id = EventHotKeyID(signature: OSType(0x5347_4C31), id: 1) // "SGL1"
        return RegisterEventHotKey(shortcut.keyCode, shortcut.carbonModifiers, id, GetApplicationEventTarget(), 0, &ref) == noErr
    }
}
