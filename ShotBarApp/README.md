# ShotBar App - Modular Structure

This app has been refactored from a monolithic file into a clean, modular architecture.

## Folder Structure

```
ShotBarApp/
├── Models/           # Data models and enums
│   ├── Hotkey.swift
│   ├── Preferences.swift
│   └── Enums.swift
├── Services/         # Business logic and managers
│   ├── AppServices.swift
│   ├── HotkeyManager.swift
│   └── ScreenshotManager.swift
├── UI/              # SwiftUI views
│   ├── PreferencesView.swift
│   └── MenuContentView.swift
├── Components/       # Reusable UI components
│   ├── SelectionOverlay.swift
│   └── Toast.swift
├── Utils/           # Utility functions (empty for now)
├── Extensions/      # Swift extensions (empty for now)
└── ShotBarAppApp.swift  # Main app entry point
```

## Architecture Overview

### Models
- **Hotkey**: Represents a Cmd+Shift+F-key shortcut
- **Preferences**: User settings with persistence via UserDefaults
- **Enums**: ImageFormat, Destination, and HotkeyID definitions

### Services
- **AppServices**: Main coordinator that wires all services together
- **HotkeyManager**: Global hotkey registration using Carbon framework
- **ScreenshotManager**: Screen capture using ScreenCaptureKit

### UI Components
- **PreferencesView**: Settings interface
- **MenuContentView**: Menubar popover content
- **SelectionOverlay**: Drag-to-select rectangle overlay
- **Toast**: HUD notification system

### Key Features
- **Modular Design**: Each component has a single responsibility
- **Dependency Injection**: Services are injected where needed
- **Clean Separation**: UI, business logic, and data models are separated
- **Maintainable**: Easy to modify individual components without affecting others

## Benefits of Refactoring

1. **Readability**: Code is easier to understand and navigate
2. **Maintainability**: Changes can be made to specific components
3. **Testability**: Individual components can be tested in isolation
4. **Reusability**: Components can be reused in other parts of the app
5. **Scalability**: New features can be added without cluttering existing code

## Usage

The main app file (`ShotBarAppApp.swift`) is now very clean and just sets up the app structure. All functionality is properly organized into the appropriate modules.

To add new features:
- Add models to `Models/`
- Add business logic to `Services/`
- Add UI components to `UI/` or `Components/`
- Update `AppServices` to wire new components together
