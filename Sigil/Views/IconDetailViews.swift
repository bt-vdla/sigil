import SwiftUI

/// Bottom bar: what's highlighted, what Return will copy, and the keys that matter.
struct IconFooter: View {
    let icon: IconModel?
    let isFavourite: Bool
    let onCopy: (OutputFormat) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                if let icon {
                    HStack(spacing: 5) {
                        if isFavourite {
                            Image(systemName: "star.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.yellow.opacity(0.85))
                        }
                        Text(icon.name)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(icon.pack.displayName)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }

                    Spacer(minLength: 8)

                    let current = OutputFormat.effective(for: icon, app: CopyService.targetApp)
                    Menu {
                        ForEach(OutputFormat.allCases.filter { $0.isAvailable(for: icon) }) { format in
                            Button(format.label(for: icon)) { onCopy(format) }
                        }
                    } label: {
                        Text("⏎ \(current.label)")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Copy format for \(CopyService.targetApp?.localizedName ?? "this app"); picking one makes it the default here")
                } else {
                    Text("Type to search")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
            }

            Text("↑↓←→ move  ·  ⌥⏎ formats  ·  ⌘Y preview  ·  ⌘D favourite  ·  ⌘P pin")
                .font(.system(size: 10))
                .foregroundStyle(.quaternary)
                .lineLimit(1)
        }
        .padding(.horizontal, 18)
        .padding(.top, 9)
        .padding(.bottom, 4)
    }
}

/// ⌥⏎ list of formats, driven by the arrow keys from ContentView.
struct FormatPicker: View {
    let icon: IconModel
    let formats: [OutputFormat]
    let highlight: Int
    let onPick: (OutputFormat) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Copy \(icon.name) as")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 10)
                .padding(.bottom, 4)

            ForEach(Array(formats.enumerated()), id: \.element) { index, format in
                Button {
                    onPick(format)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: format.symbol)
                            .font(.system(size: 11))
                            .frame(width: 16)
                            .foregroundStyle(.secondary)
                        Text(format.label(for: icon))
                            .font(.system(size: 12))
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(index == highlight ? Color.accentColor.opacity(0.35) : .clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(white: 0.11)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.1), lineWidth: 0.5))
    }
}

/// ⌘Y: the highlighted icon large, on light and dark, with the same icon from other packs.
struct IconPreview: View {
    let icon: IconModel
    let customization: IconCustomization
    let otherVersions: [IconModel]
    let onCopy: (OutputFormat) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(icon.name).font(.system(size: 14, weight: .semibold))
                    Text(icon.pack.displayName).font(.system(size: 11)).foregroundStyle(.tertiary)
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(.white.opacity(0.1)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close preview")
            }

            HStack(spacing: 0) {
                previewTile(color: .black, background: Color(white: 0.96))
                previewTile(color: .white, background: Color(white: 0.06))
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            if !otherVersions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("In other packs")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                    HStack(spacing: 8) {
                        ForEach(otherVersions.prefix(5)) { other in
                            VStack(spacing: 4) {
                                SVGImage(svg: other.svgString, size: 28, tint: .white)
                                Text(other.pack.displayName)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(width: 60, height: 54)
                            .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.05)))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            FlowButtons(formats: OutputFormat.allCases.filter { $0.isAvailable(for: icon) }, onCopy: onCopy)
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(white: 0.09)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.1), lineWidth: 0.5))
        .padding(.horizontal, 12)
        .padding(.top, 56)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.black.opacity(0.55).onTapGesture(perform: onClose))
    }

    private func previewTile(color: Color, background: Color) -> some View {
        let svg = customization.apply(to: icon.svgString)
        let tint = customization.color == nil && icon.svgString.contains("currentColor") ? color : nil
        return SVGImage(svg: svg, size: 96, tint: tint)
            .frame(maxWidth: .infinity)
            .frame(height: 150)
            .background(background)
    }
}

private struct FlowButtons: View {
    let formats: [OutputFormat]
    let onCopy: (OutputFormat) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 6)], spacing: 6) {
            ForEach(formats) { format in
                Button {
                    onCopy(format)
                } label: {
                    Label(format.label, systemImage: format.symbol)
                        .font(.system(size: 11, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// An SVG rendered at a size; `tint` recolours currentColor icons.
private struct SVGImage: View {
    let svg: String
    let size: CGFloat
    let tint: Color?

    var body: some View {
        if let image = SVGRenderer.renderToImage(svgString: svg, size: NSSize(width: size, height: size)) {
            Image(nsImage: image)
                .renderingMode(tint == nil ? .original : .template)
                .foregroundStyle(tint ?? .primary)
                .frame(width: size, height: size)
        }
    }
}

struct CopiedToast: View {
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Capsule(style: .continuous).fill(Color(white: 0.16)))
        .overlay(Capsule(style: .continuous).strokeBorder(.white.opacity(0.1), lineWidth: 0.5))
    }
}
