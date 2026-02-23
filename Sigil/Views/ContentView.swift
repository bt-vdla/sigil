import SwiftUI
import Combine

struct ContentView: View {
    let iconStore: IconStore
    let customPackStore: CustomPackStore
    var openPacksSettings: (() -> Void)? = nil

    @State private var searchText = ""
    @State private var selectedPack: IconPack? = nil
    @State private var selectedIcons: Set<String> = []
    @State private var filteredIcons: [IconModel] = []
    @State private var customization = IconCustomization()

    @State private var searchDebounce = PassthroughSubject<Void, Never>()

    private var isBulkMode: Bool {
        selectedIcons.count > 1
    }

    private var allPacks: [IconPack] {
        customPackStore.visiblePacksOrdered
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSection

            Divider()
                .opacity(0.5)

            PackFilterBar(
                selectedPack: $selectedPack,
                allPacks: allPacks,
                packCounts: iconStore.loadedPackCounts,
                onAddPack: openPacksSettings
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 7)

            CustomizationBar(customization: customization)

            Divider()
                .opacity(0.3)

            if iconStore.isLoading {
                loadingView
            } else if filteredIcons.isEmpty && !searchText.isEmpty {
                emptyStateView
            } else {
                IconGridView(
                    icons: filteredIcons,
                    selectedIcons: $selectedIcons,
                    customization: customization
                )
            }

            if isBulkMode {
                Divider()
                BulkActionBar(
                    selectedCount: selectedIcons.count,
                    onCopyFiles: { bulkCopyFiles() },
                    onCopyCode: { bulkCopyCode() },
                    onDeselectAll: { selectedIcons.removeAll() }
                )
            }
        }
        .frame(width: 400, height: 520)
        .background(.ultraThinMaterial)
        .animation(.spring(response: 0.28, dampingFraction: 0.88), value: isBulkMode)
        .onAppear {
            if !iconStore.isLoading { runSearch() }
        }
        .onChange(of: searchText) { _, _ in searchDebounce.send() }
        .onChange(of: selectedPack) { _, _ in runSearch() }
        .onChange(of: iconStore.isLoading) { _, isLoading in
            if !isLoading { runSearch() }
        }
        // Re-run search whenever pack counts change (covers custom pack loads)
        .onChange(of: iconStore.loadedPackCounts) { _, _ in runSearch() }
        // Clear selected pack if it is removed or hidden
        .onChange(of: customPackStore.packs) { _, newPacks in
            if let selected = selectedPack,
               !selected.isBuiltIn,
               !newPacks.contains(selected) {
                selectedPack = nil
            }
        }
        .onChange(of: customPackStore.hiddenPackIds) { _, hidden in
            if let selected = selectedPack, hidden.contains(selected.id) {
                selectedPack = nil
            }
            runSearch()
        }
        .onReceive(
            searchDebounce
                .debounce(for: .milliseconds(120), scheduler: RunLoop.main)
        ) { _ in
            runSearch()
        }
    }

    // MARK: - Search

    private func runSearch() {
        let hidden = customPackStore.hiddenPackIds
        filteredIcons = iconStore.search(query: searchText, pack: selectedPack)
            .filter { !hidden.contains($0.pack.id) }
    }

    // MARK: - Subviews

    private var headerSection: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("Sigil")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)

                Spacer()

                if !iconStore.isLoading {
                    Text("\(iconStore.totalCount)")
                        .font(.system(size: 11, weight: .regular).monospacedDigit())
                        .foregroundStyle(.quaternary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 13)
            .padding(.bottom, 9)

            SearchBarView(text: $searchText)
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
                .scaleEffect(0.8)
            Text("Loading icons…")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.quaternary)
            Text("No icons found")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Try a different search term")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func bulkCopyFiles() {
        let icons = filteredIcons.filter { selectedIcons.contains($0.id) }
        if customization.isCustomized {
            let customized = icons.map { icon in
                IconModel(name: icon.name, pack: icon.pack, svgString: customization.apply(to: icon.svgString))
            }
            CopyService.bulkCopyFiles(icons: customized)
        } else {
            CopyService.bulkCopyFiles(icons: icons)
        }
    }

    private func bulkCopyCode() {
        let icons = filteredIcons.filter { selectedIcons.contains($0.id) }
        if customization.isCustomized {
            let customized = icons.map { icon in
                IconModel(name: icon.name, pack: icon.pack, svgString: customization.apply(to: icon.svgString))
            }
            CopyService.bulkCopySVGCode(icons: customized)
        } else {
            CopyService.bulkCopySVGCode(icons: icons)
        }
    }
}
