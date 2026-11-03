import SwiftUI

struct IconCellView: View {
    let icon: IconModel
    let isHighlighted: Bool
    let isSelected: Bool
    let isFavourite: Bool
    let iconSize: CGFloat
    let customization: IconCustomization
    let isInMultiSelection: Bool
    let selectionCount: Int
    let onTap: (NSEvent.ModifierFlags) -> Void
    let onHover: () -> Void
    let onCopy: (OutputFormat) -> Void
    let onPreview: () -> Void
    let onToggleFavourite: () -> Void
    let selectedEffectiveIcons: () -> [IconModel]

    @State private var justCopied = false
    @State private var thumbnail: NSImage?

    private var effectiveSVG: String {
        customization.isCustomized ? customization.apply(to: icon.svgString) : icon.svgString
    }

    private var effectiveIcon: IconModel {
        customization.isCustomized ? icon.withSVG(effectiveSVG) : icon
    }

    /// currentColor renders black, so those icons are tinted to follow the appearance instead
    private var followsAppearance: Bool {
        customization.color == nil && icon.svgString.contains("currentColor")
    }

    private var renderKey: String {
        let custom = customization.isCustomized ? "|\(customization.color?.hexString ?? "")|\(customization.strokeWidth)" : ""
        return "\(icon.id)@\(Int(iconSize))\(custom)"
    }

    var body: some View {
        iconPreview
            .frame(maxWidth: .infinity)
            .frame(height: iconSize + 22)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(backgroundColor)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: isSelected ? 1.5 : 0.5)
            }
            .overlay(alignment: .topTrailing) {
                if isFavourite {
                    Image(systemName: "star.fill")
                        .font(.system(size: 7))
                        .foregroundStyle(.yellow.opacity(0.85))
                        .padding(5)
                        .accessibilityHidden(true)
                }
            }
            .overlay(alignment: .top) {
                if justCopied {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .medium))
                        .symbolRenderingMode(.multicolor)
                        .offset(y: -6)
                        .transition(.scale(scale: 0.3).combined(with: .opacity))
                }
            }
            .padding(2)
            .contentShape(Rectangle())
            .onHover { if $0 { onHover() } }
            .onTapGesture {
                let flags = NSApp.currentEvent?.modifierFlags ?? []
                onTap(flags)
                guard !flags.contains(.command) else { return }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { justCopied = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
                    withAnimation(.easeOut(duration: 0.18)) { justCopied = false }
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
            .task(id: renderKey) {
                let key = renderKey, svg = effectiveSVG, size = iconSize
                if let cached = SVGRenderer.cachedThumbnail(for: key) {
                    thumbnail = cached
                    return
                }
                thumbnail = nil
                // Render off the main thread so fast scrolling doesn't stutter
                let image = await Task.detached(priority: .userInitiated) {
                    SVGRenderer.thumbnail(for: key, svgString: svg, size: size)
                }.value
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.12)) { thumbnail = image }
            }
            .accessibilityLabel(isFavourite ? "\(icon.displayName), favourite" : icon.displayName)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Copy")
    }

    // MARK: - Icon Preview

    @ViewBuilder
    private var iconPreview: some View {
        if let thumbnail {
            Image(nsImage: thumbnail)
                .renderingMode(followsAppearance ? .template : .original)
                .interpolation(.high)
                .foregroundStyle(.primary)
                .frame(width: iconSize, height: iconSize)
                .transition(.opacity)
        } else {
            Color.clear.frame(width: iconSize, height: iconSize)
        }
    }

    private var backgroundColor: Color {
        if isSelected { return Color.accentColor.opacity(0.18) }
        if isHighlighted { return .white.opacity(0.1) }
        return .clear
    }

    private var borderColor: Color {
        if isSelected { return Color.accentColor.opacity(0.85) }
        if isHighlighted { return .white.opacity(0.16) }
        return .clear
    }

    // MARK: - Context Menu: Single icon

    @ViewBuilder
    private var singleSelectionMenuItems: some View {
        Text(icon.name)

        Divider()

        ForEach(OutputFormat.allCases.filter { $0.isAvailable(for: icon) }) { format in
            Button {
                onCopy(format)
            } label: {
                Label("Copy \(format.label(for: icon))", systemImage: format.symbol)
            }
        }

        Divider()

        Button(action: onPreview) {
            Label("Preview", systemImage: "eye")
        }
        Button(action: onToggleFavourite) {
            Label(isFavourite ? "Remove from Favourites" : "Add to Favourites", systemImage: isFavourite ? "star.slash" : "star")
        }

        Divider()

        Text("Pack: \(icon.pack.displayName)")
    }

    // MARK: - Context Menu: Multi-selection

    @ViewBuilder
    private var multiSelectionMenuItems: some View {
        Text("\(selectionCount) icons selected")

        Divider()

        Button {
            CopyService.bulkCopyFiles(icons: selectedEffectiveIcons())
        } label: {
            Label("Copy All \(selectionCount) Files", systemImage: "doc.on.doc.fill")
        }

        Button {
            CopyService.bulkCopySVGCode(icons: selectedEffectiveIcons())
        } label: {
            Label("Copy All as SVG Code", systemImage: "doc.text")
        }

        Divider()

        Button {
            CopyService.bulkExportAndReveal(icons: selectedEffectiveIcons())
        } label: {
            Label("Export \(selectionCount) Files to Folder…", systemImage: "folder")
        }
    }
}
