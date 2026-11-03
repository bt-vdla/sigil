import SwiftUI

enum GridDensity: Int, CaseIterable {
    case small, medium, large

    var columns: Int { [9, 7, 5][rawValue] }
    var iconSize: CGFloat { [20, 26, 34][rawValue] }
}

/// A titled run of icons in the grid. `offset` is the index of its first icon
/// across all sections, so keyboard navigation can treat the grid as one list.
struct GridSection: Identifiable {
    let id: String
    let title: String?
    let icons: [IconModel]
    var offset = 0
}

struct ScrollRequest: Equatable {
    var index = 0
    var toTop = true
    var token = 0
}

struct IconGridView: View {
    let sections: [GridSection]
    let density: GridDensity
    let highlight: Int
    let selectedIcons: Set<String>
    let customization: IconCustomization
    let shelf: IconShelf
    let scrollRequest: ScrollRequest
    let onTap: (Int, NSEvent.ModifierFlags) -> Void
    let onHover: (Int) -> Void
    let onCopy: (IconModel, OutputFormat) -> Void
    let onPreview: (Int) -> Void

    private var selectedEffectiveIcons: [IconModel] {
        sections.flatMap(\.icons)
            .filter { selectedIcons.contains($0.id) }
            .map { customization.isCustomized ? $0.withSVG(customization.apply(to: $0.svgString)) : $0 }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Color.clear.frame(height: 0).id(-1)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: density.columns), spacing: 0) {
                    ForEach(sections) { section in
                        Section {
                            ForEach(section.icons.indices, id: \.self) { i in
                                let index = section.offset + i
                                let icon = section.icons[i]
                                IconCellView(
                                    icon: icon,
                                    isHighlighted: index == highlight,
                                    isSelected: selectedIcons.contains(icon.id),
                                    isFavourite: shelf.isFavourite(icon.id),
                                    iconSize: density.iconSize,
                                    customization: customization,
                                    isInMultiSelection: selectedIcons.count > 1 && selectedIcons.contains(icon.id),
                                    selectionCount: selectedIcons.count,
                                    onTap: { onTap(index, $0) },
                                    onHover: { onHover(index) },
                                    onCopy: { onCopy(icon, $0) },
                                    onPreview: { onPreview(index) },
                                    onToggleFavourite: { shelf.toggleFavourite(icon.id) },
                                    selectedEffectiveIcons: { selectedEffectiveIcons }
                                )
                                .id(index)
                            }
                        } header: {
                            if let title = section.title {
                                Text(title)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 6)
                                    .padding(.top, section.offset == 0 ? 2 : 12)
                                    .padding(.bottom, 4)
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            .scrollContentBackground(.hidden)
            .onChange(of: scrollRequest) { _, request in
                if request.toTop {
                    proxy.scrollTo(-1, anchor: .top)
                } else {
                    proxy.scrollTo(request.index)
                }
            }
        }
    }
}
