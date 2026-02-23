import SwiftUI

struct PackFilterBar: View {
    @Binding var selectedPack: IconPack?
    let allPacks: [IconPack]
    let packCounts: [IconPack: Int]
    var onAddPack: (() -> Void)? = nil

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                FilterChip(
                    label: "All",
                    count: packCounts.values.reduce(0, +),
                    isSelected: selectedPack == nil,
                    accentColor: .primary
                ) {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedPack = nil
                    }
                }

                ForEach(allPacks) { pack in
                    FilterChip(
                        label: pack.displayName,
                        count: packCounts[pack] ?? 0,
                        isSelected: selectedPack == pack,
                        accentColor: Color(hex: pack.accentHex)
                    ) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedPack = selectedPack == pack ? nil : pack
                        }
                    }
                }

                if let onAddPack {
                    Button(action: onAddPack) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 13, weight: .light))
                            .foregroundStyle(.quaternary)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 2)
                    .help("Add icon pack")
                }
            }
        }
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
                    .fill(isSelected ? accentColor.opacity(0.15) : .primary.opacity(0.04))
            }
            .overlay {
                if isSelected {
                    Capsule(style: .continuous)
                        .strokeBorder(accentColor.opacity(0.45), lineWidth: 0.5)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? AnyShapeStyle(accentColor) : AnyShapeStyle(.tertiary))
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
