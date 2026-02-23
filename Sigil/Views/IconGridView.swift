import SwiftUI

struct IconGridView: View {
    let icons: [IconModel]
    @Binding var selectedIcons: Set<String>
    let customization: IconCustomization

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 6)

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(icons) { icon in
                    IconCellView(
                        icon: icon,
                        isSelected: selectedIcons.contains(icon.id),
                        customization: customization,
                        onTap: { modifiers in handleTap(icon: icon, modifiers: modifiers) },
                        // Pass selection state so the context menu can act on all selected icons
                        selectedIcons: selectedIcons,
                        allVisibleIcons: icons
                    )
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
        }
        .scrollContentBackground(.hidden)
    }

    private func handleTap(icon: IconModel, modifiers: NSEvent.ModifierFlags) {
        if modifiers.contains(.command) {
            if selectedIcons.contains(icon.id) {
                selectedIcons.remove(icon.id)
            } else {
                selectedIcons.insert(icon.id)
            }
        } else {
            selectedIcons.removeAll()
            let effective = customization.isCustomized
                ? IconModel(name: icon.name, pack: icon.pack,
                            svgString: customization.apply(to: icon.svgString))
                : icon
            CopyService.smartCopy(icon: effective)
        }
    }
}

extension Notification.Name {
    static let iconCopied = Notification.Name("SigilIconCopied")
}
