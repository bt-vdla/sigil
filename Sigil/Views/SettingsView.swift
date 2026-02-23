import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - SettingsView

struct SettingsView: View {
    let customPackStore: CustomPackStore
    let iconStore: IconStore

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Window header
            HStack(alignment: .firstTextBaseline) {
                Text("Icon Packs")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Spacer()
                Text("v\(appVersion)")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.quaternary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider().opacity(0.5)

            PacksSettingsView(customPackStore: customPackStore, iconStore: iconStore)
        }
        .frame(width: 480, height: 540)
        .background(.windowBackground)
    }
}

// MARK: - Packs Settings View

struct PacksSettingsView: View {
    let customPackStore: CustomPackStore
    let iconStore: IconStore

    @State private var showingFolderPicker = false
    @State private var normalizeOnImport = true
    @State private var isDragTargeted = false
    @State private var localImportError: String? = nil

    // Delete confirmation
    @State private var deletionTarget: IconPack? = nil

    // Drag-to-reorder
    @State private var draggedPackId: String? = nil
    @State private var dragTargetId: String? = nil

    // Inline name editing
    @State private var editingPackId: String? = nil
    @State private var editingName = ""
    @FocusState private var nameFieldFocused: Bool

    // Inline URL import
    @State private var urlInputText = ""
    @FocusState private var urlFieldFocused: Bool

    private var isRemoteImporting: Bool {
        switch customPackStore.importProgress {
        case .idle, .done, .failed: return false
        default: return true
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                // MARK: Icon Packs — all packs merged, drag-to-reorder
                sectionHeader("Icon Packs")

                VStack(spacing: 0) {
                    ForEach(customPackStore.allPacksOrdered) { pack in
                        packRow(pack)
                            .onDrag {
                                draggedPackId = pack.id
                                return NSItemProvider(object: pack.id as NSString)
                            }
                            .onDrop(
                                of: [UTType.plainText],
                                isTargeted: Binding(
                                    get: { dragTargetId == pack.id },
                                    set: { dragTargetId = $0 ? pack.id : nil }
                                )
                            ) { _, _ in
                                guard let src = draggedPackId, src != pack.id else { return false }
                                customPackStore.movePack(src, before: pack.id)
                                draggedPackId = nil
                                dragTargetId = nil
                                return true
                            }
                            .opacity({
                                if draggedPackId == pack.id { return 0.35 }
                                if customPackStore.hiddenPackIds.contains(pack.id) { return 0.5 }
                                return 1
                            }())
                            .background(
                                dragTargetId == pack.id
                                    ? Color.accentColor.opacity(0.08)
                                    : Color.clear
                            )
                    }

                    // Invisible end-of-list drop target so you can drag a row to last position
                    Color.clear
                        .frame(height: 8).frame(maxWidth: .infinity)
                        .onDrop(
                            of: [UTType.plainText],
                            isTargeted: Binding(
                                get: { dragTargetId == "__end__" },
                                set: { dragTargetId = $0 ? "__end__" : nil }
                            )
                        ) { _, _ in
                            guard let src = draggedPackId else { return false }
                            customPackStore.movePack(src, before: nil)
                            draggedPackId = nil; dragTargetId = nil
                            return true
                        }
                        .background(
                            dragTargetId == "__end__"
                                ? Color.accentColor.opacity(0.06)
                                : Color.clear
                        )
                }
                .padding(.bottom, 4)

                Divider()
                    .padding(.vertical, 10)

                // MARK: Import
                sectionHeader("Import")

                dropZone
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)

                urlImportSection
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)

                Toggle(isOn: $normalizeOnImport) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Normalize colors on import")
                            .font(.system(size: 12))
                        Text("Converts hardcoded black fills to currentColor so the color picker works")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                }
                .toggleStyle(.checkbox)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)

                if let err = localImportError {
                    HStack(spacing: 5) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                        Text(err)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
                }

                Divider()
                    .padding(.vertical, 10)

                // MARK: GitHub token
                githubTokenSection
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
        }
        .frame(maxWidth: .infinity)
        .fileImporter(
            isPresented: $showingFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handleFolderImport(result)
        }
        // Confirm delete
        .confirmationDialog(
            "Remove \"\(deletionTarget?.displayName ?? "")\"?",
            isPresented: Binding(
                get: { deletionTarget != nil },
                set: { if !$0 { deletionTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove Pack", role: .destructive) {
                if let pack = deletionTarget { customPackStore.removePack(pack.id) }
                deletionTarget = nil
            }
            Button("Cancel", role: .cancel) { deletionTarget = nil }
        } message: {
            if let pack = deletionTarget {
                Text("This will permanently delete \(customPackStore.svgCount(for: pack)) icons.")
            }
        }
        // Auto-clear URL field after a successful remote import
        .onChange(of: customPackStore.importProgress) { _, newProgress in
            if case .done = newProgress {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                    urlInputText = ""
                    customPackStore.importProgress = .idle
                }
            }
        }
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.tertiary)
            .tracking(0.5)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }

    // MARK: - Unified Pack Row

    @ViewBuilder
    private func packRow(_ pack: IconPack) -> some View {
        let isHidden = customPackStore.hiddenPackIds.contains(pack.id)

        HStack(spacing: 8) {

            // Drag handle — always visible to signal draggability
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.quaternary)
                .frame(width: 14)
                .accessibilityHidden(true)

            // Color swatch
            if pack.isBuiltIn {
                Circle()
                    .fill(Color(hex: pack.accentHex).opacity(0.85))
                    .frame(width: 10, height: 10)
                    .accessibilityHidden(true)
            } else {
                // Clip the macOS color-well, overlay our own clean swatch on top
                ColorPicker("", selection: Binding(
                    get: { Color(hex: pack.accentHex) },
                    set: { customPackStore.recolorPack(pack.id, hex: $0.hexString) }
                ), supportsOpacity: false)
                .labelsHidden()
                .frame(width: 20, height: 20)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color(hex: pack.accentHex))
                        .allowsHitTesting(false)
                )
                .accessibilityLabel("Accent color for \(pack.displayName)")
            }

            // Name — tap-to-edit for custom packs, read-only for built-in
            if !pack.isBuiltIn, editingPackId == pack.id {
                TextField("", text: $editingName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($nameFieldFocused)
                    .onSubmit { commitRename() }
                    .onChange(of: nameFieldFocused) { _, focused in
                        if !focused { commitRename() }
                    }
            } else {
                Text(pack.displayName)
                    .font(.system(size: 13))
                    .onTapGesture {
                        guard !pack.isBuiltIn else { return }
                        editingPackId = pack.id
                        editingName = pack.displayName
                        nameFieldFocused = true
                    }
                    .help(pack.isBuiltIn ? "" : "Click to rename")
            }

            Spacer()

            if let count = iconStore.loadedPackCounts[pack] {
                Text("\(count)")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.quaternary)
            }

            // Visibility toggle — orange accent when hidden makes state obvious
            Button { customPackStore.toggleVisibility(pack.id) } label: {
                Image(systemName: isHidden ? "eye.slash" : "eye")
                    .font(.system(size: 12))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(RowActionButtonStyle(accentColor: isHidden ? .orange : nil))
            .accessibilityLabel(isHidden ? "Show \(pack.displayName)" : "Hide \(pack.displayName)")
            .help(isHidden ? "Show" : "Hide")

            // Delete — custom packs only, guarded by confirmation dialog
            if !pack.isBuiltIn {
                Button { deletionTarget = pack } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(RowActionButtonStyle())
                .accessibilityLabel("Remove \(pack.displayName)")
                .help("Remove pack")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
    }

    private func commitRename() {
        guard let id = editingPackId else { return }
        let trimmed = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { customPackStore.renamePack(id, to: trimmed) }
        editingPackId = nil
    }

    // MARK: - Drop Zone

    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    isDragTargeted ? Color.accentColor.opacity(0.7) : .primary.opacity(0.12),
                    style: StrokeStyle(lineWidth: 1, dash: [4])
                )
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isDragTargeted ? Color.accentColor.opacity(0.06) : .primary.opacity(0.02))
                )

            VStack(spacing: 6) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(.quaternary)
                    .accessibilityHidden(true)
                Text("Drop a folder of SVGs here")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Button("Browse…") { showingFolderPicker = true }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.vertical, 18)
        }
        .onDrop(of: [.fileURL], isTargeted: $isDragTargeted) { providers in
            handleDrop(providers: providers)
        }
        .animation(.easeInOut(duration: 0.15), value: isDragTargeted)
        .accessibilityLabel("Drop zone. Drop a folder of SVGs here or activate to browse.")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Inline URL Import

    private var urlImportSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "link")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .frame(width: 14)
                    .accessibilityHidden(true)

                TextField(
                    "github.com/owner/repo  or  lucide-react  or  .zip URL",
                    text: $urlInputText
                )
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .focused($urlFieldFocused)
                .disabled(isRemoteImporting)
                .onSubmit { startRemoteImport() }
                .accessibilityLabel("GitHub URL, npm package name, or zip link")

                Button("Import") { startRemoteImport() }
                    .disabled(urlInputText.trimmingCharacters(in: .whitespaces).isEmpty || isRemoteImporting)
                    .accessibilityLabel("Import from URL")
            }

            remoteProgressView
        }
    }

    @ViewBuilder
    private var remoteProgressView: some View {
        switch customPackStore.importProgress {
        case .idle:
            EmptyView()

        case .resolving:
            statusRow(spinning: true, text: "Resolving source…")

        case .downloading(let current, let total):
            VStack(alignment: .leading, spacing: 4) {
                statusRow(spinning: false, text: "Downloading \(current) of \(total) icons…")
                ProgressView(value: Double(current), total: Double(max(total, 1)))
                    .progressViewStyle(.linear)
            }

        case .normalizing:
            statusRow(spinning: true, text: "Normalizing colors…")

        case .done(let pack):
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                Text("Imported \"\(pack.displayName)\" — \(customPackStore.svgCount(for: pack)) icons")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Import successful. \(pack.displayName) added with \(customPackStore.svgCount(for: pack)) icons.")

        case .failed(let message):
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityLabel("Import failed. \(message)")
        }
    }

    private func statusRow(spinning: Bool, text: String) -> some View {
        HStack(spacing: 6) {
            if spinning {
                ProgressView()
                    .scaleEffect(0.65)
                    .frame(width: 14, height: 14)
            }
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .accessibilityLabel(text)
    }

    // MARK: - GitHub Token Section

    private var githubTokenSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text("GitHub Token")
                    .font(.system(size: 12, weight: .medium))
                Text("— optional, for large packs (60 req/hr unauthenticated)")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            SecureField("ghp_xxxxxxxxxxxxxxxxxxxx", text: Binding(
                get: { customPackStore.githubToken },
                set: { customPackStore.githubToken = $0 }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 12, design: .monospaced))
            .accessibilityLabel("GitHub personal access token")
        }
    }

    // MARK: - Import Handlers

    private func startRemoteImport() {
        let input = urlInputText.trimmingCharacters(in: .whitespaces)
        guard !input.isEmpty, !isRemoteImporting else { return }
        Task { await customPackStore.importFromRemote(input) }
    }

    private func handleFolderImport(_ result: Result<[URL], Error>) {
        localImportError = nil
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            Task {
                do {
                    try customPackStore.importFromFolder(url, normalizeColors: normalizeOnImport)
                } catch {
                    localImportError = error.localizedDescription
                }
            }
        case .failure(let error):
            localImportError = error.localizedDescription
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil),
                  url.hasDirectoryPath else { return }
            Task { @MainActor in
                do {
                    try customPackStore.importFromFolder(url, normalizeColors: normalizeOnImport)
                } catch {
                    localImportError = error.localizedDescription
                }
            }
        }
        return true
    }
}

// MARK: - Row action button style

private struct RowActionButtonStyle: ButtonStyle {
    /// Override the idle foreground. Used for the eye.slash "hidden" state (orange tint).
    var accentColor: Color? = nil

    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(
                configuration.isPressed ? Color.primary.opacity(0.85)
                    : isHovered          ? Color.primary.opacity(0.55)
                                         : accentColor ?? Color.primary.opacity(0.30)
            )
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill((isHovered || configuration.isPressed)
                          ? Color.primary.opacity(0.08)
                          : Color.clear)
            )
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .animation(.easeInOut(duration: 0.1), value: isHovered)
    }
}
