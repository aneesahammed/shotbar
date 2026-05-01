import SwiftUI

struct FloatingPreviewView: View {
    @ObservedObject var coordinator: PreviewCoordinator
    @State private var selectedAssetID: UUID?

    private var batch: CaptureBatch? { coordinator.activeBatch }
    private var selectedAsset: CaptureAsset? {
        guard let batch else { return nil }
        if let selectedAssetID,
           let selected = batch.assets.first(where: { $0.id == selectedAssetID }) {
            return selected
        }
        return batch.assets.first
    }

    var body: some View {
        // ViewThatFits picks the first child whose intrinsic size fits the available space.
        // For default text sizes the fixed-VStack layout always wins; only when an extreme
        // accessibility text size or a localized label pushes content past the panel cap
        // does the ScrollView fallback engage. The panel's screen-frame clamp upstream
        // guarantees there is *some* available space to scroll within.
        ViewThatFits(in: .vertical) {
            content
            ScrollView(.vertical, showsIndicators: false) { content }
        }
        .frame(minWidth: 340, idealWidth: 340, maxWidth: 380)
        .background(backgroundView)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? 1.5 : 0.5)
        )
        .onAppear {
            selectedAssetID = batch?.assets.first?.id
            NSAccessibility.post(element: NSApp as Any, notification: .layoutChanged)
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let batch, let selectedAsset {
                thumbnailStrip(batch: batch, selectedAsset: selectedAsset)
                statusLine(for: selectedAsset, total: batch.assets.count)
                actionRow(batch: batch, asset: selectedAsset)
            }
        }
        .padding(12)
    }

    private var backgroundView: some View {
        Group {
            if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
                Color(nsColor: .windowBackgroundColor)
            } else {
                VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
            }
        }
    }

    private func thumbnailStrip(batch: CaptureBatch, selectedAsset: CaptureAsset) -> some View {
        HStack(alignment: .center, spacing: 8) {
            ForEach(batch.assets) { asset in
                Button {
                    selectedAssetID = asset.id
                } label: {
                    Image(nsImage: previewImage(asset.thumbnail))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: batch.assets.count == 1 ? 144 : 72, height: batch.assets.count == 1 ? 96 : 54)
                        .background(Color.black.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(asset.id == selectedAsset.id ? Color.accentColor : Color.clear, lineWidth: 2)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Captured \(asset.kind.rawValue)")
            }
            Spacer(minLength: 0)
            Button {
                coordinator.discard()
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Discard preview")
        }
    }

    private func statusLine(for asset: CaptureAsset, total: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(total > 1 ? "\(total) screenshots captured" : "\(asset.kind.rawValue) captured")
                .font(.headline)
                .lineLimit(1)
            if let message = asset.initialResult?.failureMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            } else if let url = asset.originalSavedURL {
                Text(url.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text("Copied to clipboard")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func actionRow(batch: CaptureBatch, asset: CaptureAsset) -> some View {
        HStack(spacing: 8) {
            PreviewButton(title: "Copy", systemImage: "doc.on.doc") {
                coordinator.copy(asset)
            }

            PreviewButton(title: asset.originalSavedURL == nil ? "Save" : "Saved", systemImage: "square.and.arrow.down") {
                coordinator.save(asset)
            }
            .disabled(asset.originalSavedURL != nil)

            if batch.assets.count > 1 {
                PreviewButton(title: "Save All", systemImage: "square.stack.3d.down.right") {
                    coordinator.saveAll()
                }
            }

            PreviewButton(title: "Edit", systemImage: "pencil.and.outline") {
                coordinator.edit(asset)
            }

            PreviewButton(title: "Reveal", systemImage: "folder") {
                coordinator.reveal(asset)
            }
            .disabled(asset.originalSavedURL == nil)
        }
    }

    private func previewImage(_ cgImage: CGImage) -> NSImage {
        NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}

private struct PreviewButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            // maxWidth: .infinity lets the buttons share the HStack width evenly,
            // preventing localized labels (e.g. "Mostrar en Finder") from breaking the row.
            // minHeight gives a stable click target across icon-only/text-only states.
            .frame(maxWidth: .infinity, minHeight: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(title)
    }
}

private struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
