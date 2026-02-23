import SwiftUI

struct IconCellView: View {
    let icon: IconModel
    let isSelected: Bool
    let customization: IconCustomization
    let onTap: (NSEvent.ModifierFlags) -> Void

    // Passed in so the context menu can act on the full selection when >1 icons are selected
    let selectedIcons: Set<String>
    let allVisibleIcons: [IconModel]

    @State private var isHovering = false
    @State private var justCopied = false
    @State private var thumbnail: NSImage?

    private var effectiveSVG: String {
        customization.isCustomized
            ? customization.apply(to: icon.svgString)
            : icon.svgString
    }

    private var customizationKey: String {
        guard customization.isCustomized else { return "" }
        return "|\(customization.color.hexString)|\(customization.strokeWidth)"
    }

    /// True when this icon is part of a multi-selection (not just selected alone)
    private var isInMultiSelection: Bool {
        isSelected && selectedIcons.count > 1
    }

    /// All currently selected icons, with customization applied
    private var selectedEffectiveIcons: [IconModel] {
        allVisibleIcons
            .filter { selectedIcons.contains($0.id) }
            .map { icon in
                guard customization.isCustomized else { return icon }
                return IconModel(name: icon.name, pack: icon.pack,
                                 svgString: customization.apply(to: icon.svgString))
            }
    }

    var body: some View {
        iconPreview
            .frame(width: 44, height: 44)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(backgroundColor)
            }
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.8), lineWidth: 1.5)
                } else if isHovering {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(.primary.opacity(0.1), lineWidth: 0.5)
                }
            }
            .overlay(alignment: .top) {
                if justCopied {
                    copiedBadge
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.3, anchor: .center).combined(with: .opacity),
                            removal:   .scale(scale: 0.85, anchor: .center).combined(with: .opacity)
                        ))
                }
            }
            .padding(3)
            .contentShape(Rectangle())
            .help(icon.name)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.1)) { isHovering = hovering }
            }
            .onTapGesture {
                let flags = NSApp.currentEvent?.modifierFlags ?? []
                onTap(flags)
                if !flags.contains(.command) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.52)) { justCopied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
                        withAnimation(.easeOut(duration: 0.18)) { justCopied = false }
                    }
                }
            }
            .contextMenu {
                if isInMultiSelection {
                    multiSelectionMenuItems
                } else {
                    singleSelectionMenuItems
                }
            }
            .draggable(IconTransferable(icon: effectiveIcon))
            .task(id: "\(icon.id)\(customizationKey)") {
                let svg = effectiveSVG
                let key = "\(icon.id)\(customizationKey)"
                thumbnail = SVGRenderer.thumbnail(for: key, svgString: svg, size: 32)
            }
            .accessibilityLabel(icon.name)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Copy")
    }

    private var effectiveIcon: IconModel {
        guard customization.isCustomized else { return icon }
        return IconModel(name: icon.name, pack: icon.pack, svgString: effectiveSVG)
    }

    // MARK: - Icon Preview

    @ViewBuilder
    private var iconPreview: some View {
        if let thumbnail {
            Image(nsImage: thumbnail)
                .interpolation(.high)
                .frame(width: 32, height: 32)
        } else {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(.quaternary.opacity(0.3))
                .frame(width: 32, height: 32)
        }
    }

    private var backgroundColor: Color {
        if isSelected { return Color.accentColor.opacity(0.14) }
        if isHovering { return .primary.opacity(0.06) }
        return .clear
    }

    // MARK: - Context Menu: Single icon

    @ViewBuilder
    private var singleSelectionMenuItems: some View {
        // Icon name as non-interactive header
        Text(icon.name)
            .font(.system(size: 12, weight: .semibold))

        Divider()

        Button {
            CopyService.copySVGCode(icon: effectiveIcon)
        } label: {
            Label("Copy SVG Code", systemImage: "doc.text")
        }

        Button {
            CopyService.copyAsPNG(icon: effectiveIcon)
        } label: {
            Label("Copy as PNG", systemImage: "photo")
        }

        Button {
            CopyService.copyAsReactComponent(icon: effectiveIcon)
        } label: {
            Label("Copy as React Component", systemImage: "chevron.left.forwardslash.chevron.right")
        }

        Divider()

        Button {
            CopyService.copyFile(icon: effectiveIcon)
        } label: {
            Label("Copy File", systemImage: "doc.on.doc")
        }

        Divider()

        Text("Pack: \(icon.pack.displayName)")
            .font(.caption)
    }

    // MARK: - Context Menu: Multi-selection

    @ViewBuilder
    private var multiSelectionMenuItems: some View {
        Text("\(selectedIcons.count) icons selected")
            .font(.system(size: 11, weight: .semibold))

        Divider()

        Button {
            CopyService.bulkCopyFiles(icons: selectedEffectiveIcons)
        } label: {
            Label("Copy All \(selectedIcons.count) Files", systemImage: "doc.on.doc.fill")
        }

        Button {
            CopyService.bulkCopySVGCode(icons: selectedEffectiveIcons)
        } label: {
            Label("Copy All as SVG Code", systemImage: "doc.text")
        }

        Divider()

        Menu {
            Button {
                CopyService.bulkExportAndReveal(icons: selectedEffectiveIcons)
            } label: {
                Label("Export \(selectedIcons.count) Files to Folder…", systemImage: "folder")
            }
        } label: {
            Label("More…", systemImage: "ellipsis")
        }
    }

    // MARK: - Copied Badge

    private var copiedBadge: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 20, weight: .medium))
            .symbolRenderingMode(.multicolor)
            .symbolEffect(.bounce, value: justCopied)
            .offset(y: -8)
    }
}
