import SwiftUI

// MARK: - Preferences UI
struct PreferencesView_Previews: PreviewProvider {
    static var previews: some View {
        let services = AppServices.shared
        PreferencesView(
            prefs: services.prefs,
            shots: services.shots,
            hotkeys: services.hotkeys
        )
        .frame(width: 400, height: 300)
    }
}

struct PreferencesView: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var shots: ScreenshotManager
    @ObservedObject var hotkeys: HotkeyManager
    
    var body: some View {
        Form {
            
            
            Section("Hotkeys (global)") {
                HotkeyPickerRow(title: "Selection", selection: $prefs.selectionHotkey)
                HotkeyPickerRow(title: "Active Window", selection: $prefs.windowHotkey)
                HotkeyPickerRow(title: "Full Screen(s)", selection: $prefs.screenHotkey)
                if let error = hotkeys.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Text("Tip: Hotkeys use Cmd+Shift with F1-F12. Some keyboards also require holding Fn unless you enable \"Use F1, F2, etc. as standard function keys\".")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.bottom, 3)
            
            Section("Permissions") {
                Button("Check Permission") {
                    ScreenshotManager.promptForPermissionIfNeeded()
                }
                Text("If captures fail, grant permissions in System Settings → Privacy.")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            Section("Preview") {
                Toggle("Show floating preview", isOn: $prefs.previewEnabled)
                HStack {
                    Text("Duration")
                    Slider(
                        value: $prefs.previewDuration,
                        in: AppConstants.previewMinDuration...AppConstants.previewMaxDuration,
                        step: 1
                    )
                    Text("\(Int(prefs.previewDuration))s")
                        .monospacedDigit()
                        .frame(width: 32, alignment: .trailing)
                }
                Picker("Corner", selection: $prefs.previewCorner) {
                    ForEach(PreviewCorner.allCases) { corner in
                        Text(corner.label).tag(corner)
                    }
                }
                Picker("Screen", selection: $prefs.previewScreenChoice) {
                    ForEach(PreviewScreenChoice.allCases) { choice in
                        Text(choice.label).tag(choice)
                    }
                }
            }

            Section("Annotation") {
                Picker("Default color", selection: $prefs.annotationDefaultColor) {
                    ForEach(AnnotationColor.allCases) { color in
                        Text(color.label).tag(color)
                    }
                }
                HStack {
                    Text("Stroke")
                    Slider(value: $prefs.annotationDefaultStrokeWidth, in: 1...24, step: 1)
                    Text("\(Int(prefs.annotationDefaultStrokeWidth))")
                        .monospacedDigit()
                        .frame(width: 28, alignment: .trailing)
                }
            }


        }
        .padding(16)
    }
}

struct HotkeyPickerRow: View {
    let title: String
    @Binding var selection: Hotkey?
    
    var body: some View {
        HStack {
            Text(title)
//            Spacer()
            Picker("", selection: Binding(
                get: { selection?.id ?? "none" },
                set: { newID in
                    if newID == "none" { selection = nil }
                    else if let hk = Hotkey.allFKeys.first(where: { $0.id == newID }) { selection = hk }
                })) {
                    Text("None").tag("none")
                    ForEach(Hotkey.allFKeys) { hk in
                        Text(hk.displayName).tag(hk.id)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 160)
        }
        .padding(.horizontal, 24) // margin from other elements
        
    }
}
