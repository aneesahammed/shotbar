import SwiftUI
import AppKit

// MARK: - AppDelegate to run launch-time setup (Scene has no onAppear)

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = AppServices.shared // touch singletons to init
        setupMenuBar()
        setupMainMenu()
        
        // Menu bar only app - no dock icon
        NSApp.setActivationPolicy(.accessory)
    }
    
    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = MenuBarIcon.makeTemplateIcon()
            button.imagePosition = .imageOnly
            button.action = #selector(togglePopover)
            button.target = self
        }
        
        popover = NSPopover()
        popover?.contentSize = NSSize(width: AppConstants.menuMinWidth, height: 300)
        popover?.behavior = .transient
        popover?.contentViewController = NSHostingController(
            rootView: MenuContentView(
                prefs: AppServices.shared.prefs,
                shots: AppServices.shared.shots,
                hotkeys: AppServices.shared.hotkeys
            )
                .frame(minWidth: AppConstants.menuMinWidth)
                .padding(.vertical, AppConstants.menuPadding)
        )
        
        // Listen for hide notification
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(hidePopover),
            name: NSNotification.Name("HideMenuBarPopover"),
            object: nil
        )
    }
    
    private func setupMainMenu() {
        let mainMenu = NSMenu()
        
        // App menu
        let appMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        
        // About menu item
        let aboutItem = NSMenuItem(title: "About ShotBar", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        appMenu.addItem(aboutItem)
        
        appMenu.addItem(NSMenuItem.separator())
        
        // Preferences menu item
        let preferencesItem = NSMenuItem(title: "Preferences...", action: #selector(showPreferences), keyEquivalent: ",")
        preferencesItem.target = self
        appMenu.addItem(preferencesItem)
        
        appMenu.addItem(NSMenuItem.separator())
        
        // Services menu
        let servicesMenu = NSMenu()
        let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        servicesItem.submenu = servicesMenu
        appMenu.addItem(servicesItem)
        
        appMenu.addItem(NSMenuItem.separator())
        
        // Hide and Quit menu items
        let hideItem = NSMenuItem(title: "Hide ShotBar", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(hideItem)
        
        let hideOthersItem = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthersItem)
        
        let showAllItem = NSMenuItem(title: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(showAllItem)
        
        appMenu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit ShotBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenu.addItem(quitItem)
        
        mainMenu.addItem(appMenuItem)
        
        // Set the main menu
        NSApplication.shared.mainMenu = mainMenu
    }
    
    @objc private func togglePopover() {
        if let popover = popover {
            if popover.isShown {
                hidePopover()
            } else {
                showPopover()
            }
        }
    }
    
    @objc private func showPopover() {
        if let button = statusItem?.button {
            popover?.show(relativeTo: button.bounds, of: button, preferredEdge: NSRectEdge.minY)
        }
    }
    
    @objc private func hidePopover() {
        popover?.performClose(nil)
    }
    
    @objc private func showAbout() {
        // Use the standard macOS About panel which will automatically use the AppIcon
        NSApp.orderFrontStandardAboutPanel()
    }
    
    @objc private func showPreferences() {
        // Open the SwiftUI settings window using the proper method
        if let settingsWindow = NSApplication.shared.windows.first(where: { $0.title == "ShotBar Settings" }) {
            settingsWindow.makeKeyAndOrderFront(nil)
        } else {
            // Fallback: try to open the settings window
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
    }
}

// MARK: - App

@main
struct ShotBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // Preferences window
        Settings {
            PreferencesView(
                prefs: AppServices.shared.prefs,
                shots: AppServices.shared.shots,
                hotkeys: AppServices.shared.hotkeys
            )
                .frame(width: AppConstants.preferencesWidth)
        }
    }
}
