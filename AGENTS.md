# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## Project Overview

ShotBarApp is a macOS screenshot utility application built with SwiftUI that provides:
- Selection capture (similar to macOS ⇧⌘4)  
- Active window capture with intelligent window prioritization
- Full screen capture across all displays
- Global hotkey support (F1-F12 keys)
- Menu bar integration with popover interface
- Clipboard or file destination options

## Development Commands

### Building
```bash
# Build the app
xcodebuild -scheme ShotBarApp -configuration Debug

# Build for release
xcodebuild -scheme ShotBarApp -configuration Release

# Clean build folder
xcodebuild clean -scheme ShotBarApp
```

### Running
The app must be run from Xcode or the built .app bundle as it requires:
- Screen Recording permissions (macOS prompts automatically)
- Menu bar integration
- Global hotkey registration

## Architecture

The app uses a **modular architecture** with clear separation of concerns across multiple files:

### Service Layer (`Services/`)
- **`AppServices.swift`**: Singleton coordinator managing all services with reactive bindings
- **`ScreenshotManager.swift`**: Screenshot capture using ScreenCaptureKit with intelligent window detection
- **`HotkeyManager.swift`**: Global hotkey registration using Carbon Event Manager

### Model Layer (`Models/`)
- **`Preferences.swift`**: UserDefaults-backed settings with automatic persistence
- **`Hotkey.swift`**: Hotkey configuration model with JSON encoding
- **`Enums.swift`**: Core enums (ImageFormat, Destination, HotkeyID)
- **`Protocols.swift`**: Protocol definitions for dependency injection

### UI Layer (`UI/`)
- **`PreferencesView.swift`**: Settings interface with hotkey binding
- **`MenuContentView.swift`**: Menu bar popover content

### Components (`Components/`)
- **`SelectionOverlay.swift`**: Full-screen overlay for drag-to-select with dotted rectangle
- **`Toast.swift`**: HUD notifications for capture feedback

### Key Technical Components

**Screenshot System Architecture**:
- **ScreenCaptureKit Integration**: Modern capture API replacing deprecated CGWindowList methods
- **Multi-Display Support**: Handles scaled displays, Sidecar, and multiple monitors correctly
- **Intelligent Window Selection**: Prioritizes windows from previously active apps, filters system windows
- **Selection Capture**: Cross-screen overlay with precise pixel coordinate mapping

**State Management Pattern**:
- **Reactive Coordination**: `AppServices` uses Combine to coordinate preference changes with hotkey rebinding
- **Published Properties**: All UI state uses `@Published` with automatic persistence
- **Dependency Injection**: Services are injected through `AppServices.shared`

### System Frameworks Used
- **ScreenCaptureKit**: Modern screenshot capture (replaces legacy CGDisplayCapture)
- **SwiftUI**: Declarative UI framework
- **AppKit**: Menu bar integration, window management, file operations
- **Carbon.HIToolbox**: Global hotkey registration (legacy but necessary)
- **Combine**: Reactive programming for state coordination

### Permissions & Sandboxing
- **Screen Recording**: Required for ScreenCaptureKit, system prompts automatically
- **Sandbox Entitlements**: User-selected file access, downloads folder access
- **No Accessibility**: App no longer requires accessibility permissions

## Key Technical Implementation Details

### Screenshot Capture Workflow
1. **Selection Mode**: `SelectionOverlay` presents cross-screen windows → user drags → coordinates converted to pixel-perfect display regions → `SCScreenshotManager.captureImage`
2. **Window Mode**: `SCShareableContent` queries all windows → filters system/ShotBar windows → prioritizes by previous active app and window size → captures with proper pixel scaling
3. **Full Screen Mode**: Iterates through `SCDisplay` objects → captures each display at native resolution

### Global Hotkey Implementation
- **Carbon Event Manager**: Uses legacy but stable Carbon APIs for system-wide hotkey capture
- **Event Signature**: `'SHK1'` signature prevents conflicts with other apps
- **Hot Swapping**: Hotkeys can be changed at runtime without restart

### File Management & Save Logic
- **System Integration**: Reads macOS screenshot location from `com.apple.screencapture` domain preferences
- **Fallback Strategy**: Desktop directory if system preference unavailable
- **Format Support**: PNG (lossless) and JPG (92% quality) with user preference
- **Filename Convention**: `"Screenshot YYYY-MM-DD at HH.mm.ss [Type].[ext]"`

### Window Detection Algorithm
The app implements sophisticated window prioritization:
1. Store previous active app before menu becomes active (`storePreviousActiveApp()`)
2. Filter out system windows, ShotBar itself, and invalid windows
3. Prioritize windows from the previously active application
4. Secondary sort by window size and screen position for main windows

## Development Notes

### Permission Handling
- ScreenCaptureKit automatically triggers system permission prompts
- No manual permission checking required - capture attempts will fail gracefully with error messages
- Permissions persist across app restarts

### Multi-Display Considerations
- App handles display scaling factors correctly (Retina, scaled displays, Sidecar)
- Selection overlay spans all connected displays simultaneously
- Pixel coordinate mapping accounts for different display DPI and positioning

### State Architecture Patterns
- **Service Coordination**: `AppServices.init()` sets up reactive bindings between preferences and hotkeys
- **UI State Flow**: Settings changes → `@Published` updates → automatic persistence → hotkey rebinding
- **Error Handling**: Toast notifications instead of blocking alerts for better UX