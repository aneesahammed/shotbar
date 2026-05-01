import SwiftUI

struct AnnotationEditorView: View {
    @ObservedObject var model: AnnotationDocumentModel
    let onSave: () async -> Void
    let onCopy: () async -> Void
    let onCancel: () -> Void

    // `.adaptive(minimum:)` packs as many ~32pt swatch slots as the inspector width allows
    // and reflows to a 2-row layout when the inspector is narrow (current default 190pt).
    // Resilient to future inspector resizing or localization-driven layout shifts that
    // a fixed 4-column grid would not handle gracefully.
    private let paletteColumns: [GridItem] = [
        GridItem(.adaptive(minimum: 28, maximum: 40), spacing: 8, alignment: .center)
    ]

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HStack(spacing: 0) {
                toolPalette
                Divider()
                AnnotationCanvasView(model: model)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .underPageBackgroundColor))
                Divider()
                inspector
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button {
                model.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .disabled(!model.canUndo)
            .help("Undo")

            Button {
                model.redo()
            } label: {
                Image(systemName: "arrow.uturn.forward")
            }
            .disabled(!model.canRedo)
            .help("Redo")

            Spacer()

            if model.isRendering {
                ProgressView()
                    .controlSize(.small)
            }

            Button {
                Task { await onCopy() }
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .disabled(model.isRendering)

            Button {
                Task { await onSave() }
            } label: {
                Label("Save Annotated", systemImage: "square.and.arrow.down")
            }
            .keyboardShortcut("s", modifiers: [.command])
            .disabled(model.isRendering)

            Button("Cancel") {
                onCancel()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var toolPalette: some View {
        VStack(spacing: 8) {
            ForEach(AnnotationToolKind.allCases) { tool in
                Button {
                    model.selectedTool = tool
                } label: {
                    Image(systemName: tool.symbolName)
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 34, height: 34)
                        .background(model.selectedTool == tool ? Color.accentColor.opacity(0.18) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(model.selectedTool == tool ? Color.accentColor : Color.clear, lineWidth: 1.5)
                        )
                }
                .buttonStyle(.plain)
                .help(tool.label)
                .accessibilityLabel(tool.label)
            }
            Spacer()
        }
        .padding(10)
        .frame(width: 58)
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Style")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("Color")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: paletteColumns, spacing: 8) {
                    ForEach(AnnotationColor.allCases) { color in
                        Button {
                            model.selectedColor = color
                        } label: {
                            Circle()
                                .fill(color.swiftUIColor)
                                .frame(width: 22, height: 22)
                                .overlay(
                                    Circle().stroke(
                                        Color.primary.opacity(model.selectedColor == color ? 0.9 : 0.25),
                                        lineWidth: model.selectedColor == color ? 2 : 1
                                    )
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(color.label)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Stroke \(Int(model.strokeWidth))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: $model.strokeWidth, in: 1...24, step: 1)
            }

            Picker("Blur", selection: $model.blurMode) {
                ForEach(AnnotationBlurMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if let message = model.lastMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(14)
        .frame(width: 190)
    }
}
