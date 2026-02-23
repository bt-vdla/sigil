import SwiftUI

struct BulkActionBar: View {
    let selectedCount: Int
    let onCopyFiles: () -> Void
    let onCopyCode: () -> Void
    let onDeselectAll: () -> Void

    @State private var filesCopied = false
    @State private var codeCopied = false

    var body: some View {
        HStack(spacing: 8) {
            Text("\(selectedCount) selected")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Spacer()

            // Secondary: icon replaces with checkmark, label turns green
            Button {
                guard !codeCopied else { return }
                onCopyCode()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.62)) {
                    codeCopied = true
                }
                Task {
                    try? await Task.sleep(for: .seconds(1.6))
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.84)) {
                        codeCopied = false
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: codeCopied ? "checkmark" : "doc.text")
                        .contentTransition(.symbolEffect(.replace.downUp))
                    Text("Copy Code")
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(codeCopied ? AnyShapeStyle(Color.green) : AnyShapeStyle(.secondary))
                .animation(.spring(response: 0.3, dampingFraction: 0.74), value: codeCopied)
            }
            .buttonStyle(.plain)
            .help("Copy all SVG code to clipboard")
            .accessibilityLabel("Copy code for \(selectedCount) icons")

            // Primary: capsule background morphs accent→green, label shrinks to "Copied!"
            Button {
                guard !filesCopied else { return }
                onCopyFiles()
                withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                    filesCopied = true
                }
                Task {
                    try? await Task.sleep(for: .seconds(1.6))
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.84)) {
                        filesCopied = false
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    // Explicit frame prevents different SF Symbol glyph heights from
                    // causing the capsule to shift height during the icon swap
                    Image(systemName: filesCopied ? "checkmark.circle.fill" : "doc.on.doc.fill")
                        .frame(width: 11, height: 11)
                        .contentTransition(.symbolEffect(.replace.downUp))
                    // No .contentTransition(.interpolate) — it fights the spring layout
                    // animation and causes a double-height glitch. The spring's cross-fade
                    // handles the visual text swap cleanly on its own.
                    Text(filesCopied ? "Copied!" : "Copy All Files")
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background {
                    Capsule(style: .continuous)
                        .fill(filesCopied ? Color.green : Color.accentColor)
                }
                // drives capsule color + width morph; higher dampingFraction prevents
                // bounce-back overshoot when the capsule shrinks to "Copied!" width
                .animation(.spring(response: 0.32, dampingFraction: 0.82), value: filesCopied)
            }
            .buttonStyle(.plain)
            .help("Copy all selected icons as SVG file references")
            .accessibilityLabel(filesCopied ? "Copied" : "Copy all \(selectedCount) files")

            // Deselect
            Button {
                onDeselectAll()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Deselect all")
            .accessibilityLabel("Deselect all")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
