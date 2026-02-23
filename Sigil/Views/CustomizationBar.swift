import SwiftUI
import AppKit

struct CustomizationBar: View {
    @Bindable var customization: IconCustomization
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            // Toggle row
            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.76)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "paintbrush.pointed")
                        .font(.system(size: 10, weight: .medium))
                    Text("Customize")
                        .font(.system(size: 11, weight: .medium))

                    if customization.isCustomized {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 5, height: 5)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(customization.isCustomized ? "Customize, customized" : "Customize")
            .accessibilityHint(isExpanded ? "Collapse" : "Expand")

            if isExpanded {
                VStack(spacing: 10) {
                    colorRow
                    strokeRow
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.95, anchor: .top)),
                    removal:   .opacity.combined(with: .scale(scale: 0.97, anchor: .top))
                ))
            }
        }
    }

    // MARK: - Color Row

    private static let colorNames = [
        "White", "Black", "Red", "Orange", "Yellow",
        "Green", "Blue", "Purple", "Pink", "Gray"
    ]

    private var colorRow: some View {
        HStack(spacing: 0) {
            Text("Color")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
                .frame(width: 44, alignment: .leading)

            // Preset swatches
            HStack(spacing: 5) {
                ForEach(Array(IconCustomization.presetColors.enumerated()), id: \.offset) { index, preset in
                    swatchButton(
                        color: preset,
                        name: index < Self.colorNames.count ? Self.colorNames[index] : preset.hexString
                    )
                }

                // "More colors…" swatch — opens NSColorPanel directly
                Button {
                    openColorPanel()
                } label: {
                    Circle()
                        .fill(
                            AngularGradient(
                                colors: [.red, .orange, .yellow, .green, .blue, .purple, .red],
                                center: .center
                            )
                        )
                        .frame(width: 18, height: 18)
                        .overlay {
                            Circle()
                                .strokeBorder(.white.opacity(0.2), lineWidth: 0.5)
                        }
                }
                .buttonStyle(.plain)
                .help("Custom color…")
                .accessibilityLabel("Custom color")
            }

            Spacer()

            if customization.isCustomized {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        customization.reset()
                    }
                } label: {
                    Text("Reset")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Reset customization")
            }
        }
    }

    private func swatchButton(color: Color, name: String) -> some View {
        let isActive = customization.color.hexString == color.hexString && customization.isCustomized

        return Button {
            customization.color = color
            customization.isCustomized = true
        } label: {
            Circle()
                .fill(color)
                .frame(width: 18, height: 18)
                .overlay {
                    Circle()
                        .strokeBorder(
                            isActive ? Color.accentColor : .white.opacity(0.15),
                            lineWidth: isActive ? 2 : 0.5
                        )
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isActive ? "\(name), selected" : name)
    }

    // MARK: - Stroke Row

    private var strokeRow: some View {
        HStack(spacing: 0) {
            Text("Stroke")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
                .frame(width: 44, alignment: .leading)

            Slider(value: $customization.strokeWidth, in: 0.5...4.0, step: 0.5)
                .controlSize(.mini)
                .onChange(of: customization.strokeWidth) { _, _ in
                    customization.isCustomized = true
                }
                .accessibilityLabel("Stroke width")

            Text(String(format: "%.1f", customization.strokeWidth))
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 24, alignment: .trailing)
        }
    }

    // MARK: - NSColorPanel

    /// Opens the native macOS Color Panel and subscribes to its color changes.
    private func openColorPanel() {
        let panel = NSColorPanel.shared
        panel.isContinuous = true
        panel.setTarget(nil)
        panel.setAction(nil)
        panel.makeKeyAndOrderFront(nil)

        NotificationCenter.default.addObserver(
            forName: NSColorPanel.colorDidChangeNotification,
            object: panel,
            queue: .main
        ) { [weak panel] _ in
            guard let nsColor = panel?.color,
                  let srgb = nsColor.usingColorSpace(.sRGB) else { return }
            customization.color = Color(nsColor: srgb)
            customization.isCustomized = true
        }
    }
}
