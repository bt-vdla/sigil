import SwiftUI

/// Pack chips. Several can be on at once; none means all packs. The choice persists,
/// so it doubles as the user's default packs.
struct PackFilterBar: View {
    @Binding var selectedPacks: Set<String>
    let allPacks: [IconPack]
    let packCounts: [IconPack: Int]
    var onAddPack: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    FilterChip(
                        label: "All",
                        count: packCounts.values.reduce(0, +),
                        isSelected: selectedPacks.isEmpty,
                        accentColor: .primary
                    ) {
                        selectedPacks = []
                    }

                    ForEach(allPacks) { pack in
                        FilterChip(
                            label: pack.displayName,
                            count: packCounts[pack] ?? 0,
                            isSelected: selectedPacks.contains(pack.id),
                            accentColor: Color(hex: pack.accentHex)
                        ) {
                            if selectedPacks.contains(pack.id) {
                                selectedPacks.remove(pack.id)
                            } else {
                                selectedPacks.insert(pack.id)
                            }
                        }
                    }

                    if let onAddPack {
                        Button(action: onAddPack) {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 13, weight: .light))
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 2)
                        .help("Add icon pack")
                        .accessibilityLabel("Add icon pack")
                    }
                }
            }

            if !selectedPacks.isEmpty {
                Button {
                    selectedPacks = []
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(.white.opacity(0.1)))
                }
                .buttonStyle(.plain)
                .help("Clear pack filter (⌘0)")
                .accessibilityLabel("Clear pack filter")
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: selectedPacks)
    }
}

// MARK: - Filter Chip

private struct FilterChip: View {
    let label: String
    let count: Int
    let isSelected: Bool
    let accentColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))

                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .regular).monospacedDigit())
                        .foregroundStyle(isSelected ? AnyShapeStyle(accentColor.opacity(0.7)) : AnyShapeStyle(.quaternary))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background {
                Capsule(style: .continuous)
                    .fill(isSelected ? accentColor.opacity(0.18) : .primary.opacity(0.05))
            }
            .overlay {
                if isSelected {
                    Capsule(style: .continuous)
                        .strokeBorder(accentColor.opacity(0.5), lineWidth: 0.5)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? AnyShapeStyle(accentColor) : AnyShapeStyle(.secondary))
        .accessibilityLabel("\(label)\(count > 0 ? ", \(count) icons" : "")\(isSelected ? ", selected" : "")")
    }
}

// MARK: - Hex Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let scanner = Scanner(string: hex)
        var rgbValue: UInt64 = 0
        scanner.scanHexInt64(&rgbValue)

        let r = Double((rgbValue & 0xFF0000) >> 16) / 255.0
        let g = Double((rgbValue & 0x00FF00) >> 8) / 255.0
        let b = Double(rgbValue & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }
}
