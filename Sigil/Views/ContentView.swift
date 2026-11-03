import Carbon.HIToolbox
import Combine
import SwiftUI

struct ContentView: View {
    let iconStore: IconStore
    let customPackStore: CustomPackStore
    let shelf: IconShelf
    let drawer: DrawerState

    @State private var searchText = ""
    @State private var selectedIcons: Set<String> = []
    @State private var sections: [GridSection] = []
    @State private var flatIcons: [IconModel] = []
    @State private var highlight = 0
    @State private var scrollRequest = ScrollRequest()
    @State private var customization = IconCustomization()
    @State private var toast: String?
    @State private var showPreview = false
    @State private var formatPicker: Int?  // highlighted row while the picker is open
    @State private var otherPackMatches = 0
    @State private var suggestion: String?
    /// Pointer position at the last keyboard move; hovers that didn't move the pointer are ignored,
    /// otherwise scrolling under a still pointer would steal the highlight.
    @State private var pointerAtKeyMove: CGPoint?

    @AppStorage("packFilter") private var packFilterRaw = ""
    @AppStorage("gridDensity") private var densityRaw = GridDensity.medium.rawValue
    @FocusState private var searchFocused: Bool

    @State private var searchDebounce = PassthroughSubject<Void, Never>()

    private var packFilter: Set<String> {
        get { Set(packFilterRaw.split(separator: ",").map(String.init)) }
        nonmutating set { packFilterRaw = newValue.sorted().joined(separator: ",") }
    }

    private var density: GridDensity { GridDensity(rawValue: densityRaw) ?? .medium }

    private var highlighted: IconModel? {
        flatIcons.indices.contains(highlight) ? flatIcons[highlight] : nil
    }

    private var pickerFormats: [OutputFormat] {
        guard let icon = highlighted else { return [] }
        return OutputFormat.allCases.filter { $0.isAvailable(for: icon) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            SearchBarView(text: $searchText, isFocused: $searchFocused)
                .padding(.horizontal, 14)
                .padding(.bottom, 10)

            PackFilterBar(
                selectedPacks: Binding(get: { packFilter }, set: { packFilter = $0 }),
                allPacks: customPackStore.visiblePacksOrdered,
                packCounts: iconStore.loadedPackCounts,
                onAddPack: { drawer.openSettings() }
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 4)

            CustomizationBar(customization: customization)

            Divider().opacity(0.3)

            if iconStore.isLoading {
                loadingView
            } else if flatIcons.isEmpty {
                emptyStateView
            } else {
                IconGridView(
                    sections: sections,
                    density: density,
                    highlight: highlight,
                    selectedIcons: selectedIcons,
                    customization: customization,
                    shelf: shelf,
                    scrollRequest: scrollRequest,
                    onTap: handleTap,
                    onHover: { index in
                        guard NSEvent.mouseLocation != pointerAtKeyMove else { return }
                        highlight = index
                    },
                    onCopy: { icon, format in copy(icon, format: format) },
                    onPreview: { index in
                        highlight = index
                        showPreview = true
                    }
                )
            }

            Divider().opacity(0.3)

            if selectedIcons.count > 1 {
                BulkActionBar(
                    selectedCount: selectedIcons.count,
                    onCopyFiles: { CopyService.bulkCopyFiles(icons: selectedEffectiveIcons()) },
                    onCopyCode: { CopyService.bulkCopySVGCode(icons: selectedEffectiveIcons()) },
                    onDeselectAll: { selectedIcons.removeAll() }
                )
            } else {
                IconFooter(
                    icon: highlighted,
                    isFavourite: highlighted.map { shelf.isFavourite($0.id) } ?? false,
                    onCopy: { format in highlighted.map { copy($0, format: format) } }
                )
            }
        }
        .overlay(alignment: .bottom) {
            if let format = formatPicker, let icon = highlighted {
                FormatPicker(icon: icon, formats: pickerFormats, highlight: format) { picked in
                    formatPicker = nil
                    copy(icon, format: picked)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 64)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay {
            if showPreview, let icon = highlighted {
                IconPreview(
                    icon: icon,
                    customization: customization,
                    otherVersions: iconStore.allIcons.filter { $0.nameLowercased == icon.nameLowercased && $0.id != icon.id },
                    onCopy: { copy(icon, format: $0) },
                    onClose: { showPreview = false }
                )
                .transition(.scale(scale: 0.96).combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottom) {
            if let toast {
                CopiedToast(text: toast)
                    .padding(.bottom, 56)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: selectedIcons.count > 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.82), value: toast)
        .animation(.spring(response: 0.3, dampingFraction: 0.86), value: formatPicker)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: showPreview)
        .onAppear {
            drawer.keyHandler = handleKey
            if !iconStore.isLoading { runSearch() }
        }
        .onChange(of: drawer.resetToken) { _, _ in
            searchText = ""
            selectedIcons = []
            runSearch()
        }
        .onChange(of: drawer.isOpen) { _, isOpen in
            guard isOpen else { return }
            showPreview = false
            formatPicker = nil
            if searchText.isEmpty { runSearch() }  // picks up new recents
            searchFocused = true
            // Quick reopen keeps the last search, selected so typing replaces it
            if !searchText.isEmpty {
                DispatchQueue.main.async { NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil) }
            }
        }
        .onChange(of: searchText) { _, _ in searchDebounce.send() }
        .onChange(of: packFilterRaw) { _, _ in runSearch() }
        .onChange(of: iconStore.isLoading) { _, isLoading in
            if !isLoading { runSearch() }
        }
        .onChange(of: iconStore.loadedPackCounts) { _, _ in runSearch() }
        .onChange(of: shelf.favourites) { _, _ in runSearch(keepPosition: true) }
        // Drop removed or hidden packs from the filter
        .onChange(of: customPackStore.visiblePacksOrdered.map(\.id)) { _, visible in
            let kept = packFilter.intersection(visible)
            if kept != packFilter { packFilter = kept }
            runSearch()
        }
        .onReceive(searchDebounce.debounce(for: .milliseconds(80), scheduler: RunLoop.main)) { _ in
            runSearch()
        }
    }

    // MARK: - Search

    private func runSearch(keepPosition: Bool = false) {
        let hidden = customPackStore.hiddenPackIds
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let results = iconStore.search(query: query, packs: packFilter, hidden: hidden, boost: shelf.boost)

        var built: [GridSection] = []
        if query.isEmpty {
            let mine = { (ids: [String]) in ids.compactMap(iconStore.icon(id:)).filter { !hidden.contains($0.pack.id) } }
            let favourites = mine(shelf.favourites)
            let recents = mine(shelf.recents)
            if !favourites.isEmpty { built.append(GridSection(id: "favourites", title: "Favourites", icons: favourites)) }
            if !recents.isEmpty { built.append(GridSection(id: "recents", title: "Recent", icons: recents)) }
            built.append(GridSection(id: "all", title: built.isEmpty ? nil : "All icons", icons: results))
        } else {
            built.append(GridSection(id: "results", title: nil, icons: results))
        }

        var offset = 0
        for i in built.indices {
            built[i].offset = offset
            offset += built[i].icons.count
        }
        sections = built
        flatIcons = built.flatMap(\.icons)

        otherPackMatches = results.isEmpty && !packFilter.isEmpty
            ? iconStore.search(query: query, hidden: hidden).count
            : 0
        suggestion = results.isEmpty && otherPackMatches == 0 ? iconStore.suggestion(for: query) : nil

        if keepPosition {
            highlight = min(highlight, max(flatIcons.count - 1, 0))
        } else {
            highlight = 0
            scrollRequest = ScrollRequest(toTop: true, token: scrollRequest.token + 1)
        }
    }

    // MARK: - Copy

    /// Copies in `format`, or in the app's remembered format when nil.
    /// Picking a format explicitly makes it that app's default.
    private func copy(_ icon: IconModel, format: OutputFormat? = nil, stayOpen: Bool = false) {
        let app = CopyService.targetApp
        let chosen = format ?? OutputFormat.effective(for: icon, app: app)
        CopyService.copy(icon, as: chosen, customization: customization)
        if format != nil { OutputFormat.remember(chosen, for: app) }
        shelf.recordUse(icon.id)

        toast = "\(icon.name) · \(chosen.label)"
        let shown = toast
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if toast == shown { toast = nil }
        }

        if !stayOpen && !drawer.isPinned {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { drawer.close() }
        }
    }

    private func handleTap(index: Int, modifiers: NSEvent.ModifierFlags) {
        guard flatIcons.indices.contains(index) else { return }
        let icon = flatIcons[index]
        highlight = index
        if modifiers.contains(.command) {
            if selectedIcons.contains(icon.id) {
                selectedIcons.remove(icon.id)
            } else {
                selectedIcons.insert(icon.id)
            }
        } else {
            selectedIcons.removeAll()
            copy(icon)
        }
    }

    private func selectedEffectiveIcons() -> [IconModel] {
        flatIcons
            .filter { selectedIcons.contains($0.id) }
            .reduce(into: [IconModel]()) { result, icon in
                if !result.contains(icon) { result.append(icon) }
            }
            .map { customization.isCustomized ? $0.withSVG(customization.apply(to: $0.svgString)) : $0 }
    }

    // MARK: - Keyboard

    /// Called for every key press in the drawer. Returns true when the key was handled.
    private func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .shift, .control])
        let key = Int(event.keyCode)

        // Format picker takes over the arrows and Return while it's open
        if let row = formatPicker {
            switch key {
            case kVK_UpArrow: formatPicker = max(row - 1, 0)
            case kVK_DownArrow: formatPicker = min(row + 1, pickerFormats.count - 1)
            case kVK_Return, kVK_ANSI_KeypadEnter:
                if let icon = highlighted, pickerFormats.indices.contains(row) {
                    formatPicker = nil
                    copy(icon, format: pickerFormats[row])
                }
            case kVK_Escape: formatPicker = nil
            default: return false
            }
            return true
        }

        switch (key, flags) {
        case (kVK_UpArrow, []): moveVertically(-1)
        case (kVK_DownArrow, []): moveVertically(1)
        case (kVK_LeftArrow, []): move(by: -1)
        case (kVK_RightArrow, []): move(by: 1)
        case (kVK_LeftArrow, .command): cyclePack(by: -1)
        case (kVK_RightArrow, .command): cyclePack(by: 1)
        case (kVK_Return, []), (kVK_ANSI_KeypadEnter, []):
            if let icon = highlighted { copy(icon) }
        case (kVK_Return, .command):
            if let icon = highlighted { copy(icon, stayOpen: true) }
        case (kVK_Return, .option):
            if highlighted != nil { formatPicker = 0 }
        case (kVK_Escape, _):
            if showPreview { showPreview = false }
            else if !searchText.isEmpty { searchText = "" }
            else if !selectedIcons.isEmpty { selectedIcons.removeAll() }
            else { drawer.close() }
        case (kVK_ANSI_0, .command): packFilter = []
        case (kVK_ANSI_D, .command):
            if let icon = highlighted { shelf.toggleFavourite(icon.id) }
        case (kVK_ANSI_Y, .command): showPreview.toggle()
        case (kVK_ANSI_P, .command): drawer.isPinned.toggle()
        case (kVK_ANSI_Equal, .command), (kVK_ANSI_Equal, [.command, .shift]):
            densityRaw = min(densityRaw + 1, GridDensity.large.rawValue)
        case (kVK_ANSI_Minus, .command): densityRaw = max(densityRaw - 1, GridDensity.small.rawValue)
        case (kVK_ANSI_Comma, .command): drawer.openSettings()
        default: return false
        }
        return true
    }

    private func move(by delta: Int) {
        guard !flatIcons.isEmpty else { return }
        moveHighlight(to: highlight + delta)
    }

    /// Up/down keep the column, and step between sections (Favourites, Recent, All) row by row.
    private func moveVertically(_ direction: Int) {
        let filled = sections.filter { !$0.icons.isEmpty }
        guard let current = filled.lastIndex(where: { $0.offset <= highlight }) else { return }
        let section = filled[current]
        let columns = density.columns
        let local = highlight - section.offset
        let column = local % columns
        let target = local + direction * columns

        if section.icons.indices.contains(target) {
            moveHighlight(to: section.offset + target)
        } else if direction > 0, local / columns < (section.icons.count - 1) / columns {
            moveHighlight(to: section.offset + section.icons.count - 1)  // shorter last row
        } else if direction > 0, filled.indices.contains(current + 1) {
            let next = filled[current + 1]
            moveHighlight(to: next.offset + min(column, next.icons.count - 1))
        } else if direction < 0, current > 0 {
            let previous = filled[current - 1]
            let lastRowStart = (previous.icons.count - 1) / columns * columns
            moveHighlight(to: previous.offset + min(lastRowStart + column, previous.icons.count - 1))
        }
    }

    private func moveHighlight(to index: Int) {
        highlight = min(max(index, 0), flatIcons.count - 1)
        pointerAtKeyMove = NSEvent.mouseLocation
        scrollRequest = ScrollRequest(index: highlight, toTop: false, token: scrollRequest.token + 1)
    }

    /// ⌘← / ⌘→ step through packs one at a time, starting from "All".
    private func cyclePack(by delta: Int) {
        let ids = customPackStore.visiblePacksOrdered.map(\.id)
        guard !ids.isEmpty else { return }
        let current = packFilter.count == 1 ? ids.firstIndex(of: packFilter.first!) : nil
        let next = current.map { $0 + delta } ?? (delta > 0 ? 0 : ids.count - 1)
        packFilter = ids.indices.contains(next) ? [ids[next]] : []
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(spacing: 10) {
            Text("Sigil")
                .font(.system(size: 15, weight: .semibold, design: .rounded))

            if !iconStore.isLoading {
                Text("\(iconStore.totalCount)")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.quaternary)
            }

            Spacer()

            Button {
                drawer.isPinned.toggle()
            } label: {
                Image(systemName: drawer.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(drawer.isPinned ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
                    .rotationEffect(.degrees(drawer.isPinned ? 0 : 35))
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: drawer.isPinned)
            }
            .buttonStyle(.plain)
            .help(drawer.isPinned ? "Unpin (⌘P)" : "Keep open while you drag icons out (⌘P)")
            .accessibilityLabel(drawer.isPinned ? "Unpin drawer" : "Pin drawer")

            Button {
                drawer.openSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Settings (⌘,)")
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 10)
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.8)
            Text("Loading icons…")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateView: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.quaternary)

            if otherPackMatches > 0 {
                let names = customPackStore.visiblePacksOrdered.filter { packFilter.contains($0.id) }.map(\.displayName)
                Text("No match in \(ListFormatter.localizedString(byJoining: names))")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Button("Show \(otherPackMatches) in other packs") { packFilter = [] }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            } else {
                Text("No icons for “\(searchText)”")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                if let suggestion {
                    Button("Search “\(suggestion)” instead") { searchText = suggestion }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
