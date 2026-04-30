import SwiftUI

// MARK: - Menu UI (menubar popover)

struct MenuContentView: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var shots: ScreenshotManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection
            Divider()
            settingsSection
            Divider()
            actionsSection
            Divider()
            footerSection
        }
        .frame(minWidth: AppConstants.menuMinWidth)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: Header

    private var headerSection: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 32, height: 32)
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text("ShotBar")
                    .font(.headline)
                Text(saveLocationDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(shots.saveDirectory?.path ?? "")
            }

            Spacer()

            SettingsLink {
                Image(systemName: "gearshape")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help("Open Settings")
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var saveLocationDescription: String {
        guard let dir = shots.saveDirectory else { return "Save to: Documents/" }
        return "Save to: \(dir.lastPathComponent)/"
    }

    // MARK: Settings (Format / Destination)

    private var settingsSection: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Format")
                    .font(.subheadline)
                    .frame(width: 96, alignment: .leading)

                Picker("Format", selection: $prefs.imageFormat) {
                    ForEach(ImageFormat.allCases) { format in
                        Text(format.id).tag(format)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 160)

                Spacer()
            }

            HStack {
                Text("Destination")
                    .font(.subheadline)
                    .frame(width: 96, alignment: .leading)

                Picker("Destination", selection: $prefs.destination) {
                    ForEach(Destination.allCases) { dest in
                        Text(dest.rawValue.capitalized).tag(dest)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 200)

                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: Capture actions

    private var actionsSection: some View {
        VStack(spacing: 0) {
            MenuRow(
                icon: "selection.pin.in.out",
                title: "Capture Selection",
                shortcut: shortcutLabel(for: prefs.selectionHotkey)
            ) {
                shots.captureSelection()
            }

            MenuRow(
                icon: "macwindow.on.rectangle",
                title: "Capture Active Window",
                shortcut: shortcutLabel(for: prefs.windowHotkey)
            ) {
                shots.storePreviousActiveApp()
                shots.captureActiveWindow()
            }

            MenuRow(
                icon: "display",
                title: "Capture Full Screen(s)",
                shortcut: shortcutLabel(for: prefs.screenHotkey)
            ) {
                shots.captureFullScreens()
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: Footer (utility actions)

    private var footerSection: some View {
        VStack(spacing: 0) {
            MenuRow(icon: "folder", title: "Reveal Save Folder") {
                shots.revealSaveLocationInFinder()
            }

            HStack(spacing: 10) {
                Image(systemName: prefs.soundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.tint)
                    .frame(width: 20)

                Toggle("Shutter sound", isOn: $prefs.soundEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)

            Divider()
                .padding(.vertical, 2)

            MenuRow(icon: "power", title: "Quit ShotBar", role: .destructive) {
                NSApp.terminate(nil)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: Helpers

    private func shortcutLabel(for hotkey: Hotkey?) -> String? {
        guard let hotkey else { return nil }
        return hotkey.displayName
    }
}

// MARK: - Row

private enum MenuRowRole {
    case normal, destructive
}

private struct MenuRow: View {
    let icon: String
    let title: String
    var shortcut: String? = nil
    var role: MenuRowRole = .normal
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(role == .destructive ? Color.red : Color.accentColor)
                    .frame(width: 20)

                Text(title)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let shortcut, !shortcut.isEmpty {
                    Text(shortcut)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovering ? Color.accentColor.opacity(0.18) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .onHover { hovering in
            isHovering = hovering
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}
