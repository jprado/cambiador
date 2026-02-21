import Cocoa
import CoreServices
import ServiceManagement

// MARK: - Browser Info

struct BrowserInfo {
    let bundleID: String
    let name: String
    let icon: NSImage?
    let url: URL
}

// MARK: - App Delegate

@objc class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "globe", accessibilityDescription: "Arre")
        }

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        updateStatusIcon()
    }

    // MARK: - Browser Discovery

    private func installedBrowsers() -> [BrowserInfo] {
        let handlerIDs: [String]
        if let cfArray = LSCopyAllHandlersForURLScheme("https" as CFString)?.takeRetainedValue() {
            handlerIDs = cfArray as? [String] ?? []
        } else {
            handlerIDs = []
        }

        // De-duplicate (case-insensitive)
        var seen = Set<String>()
        var browsers: [BrowserInfo] = []

        for rawID in handlerIDs {
            let key = rawID.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)

            guard let urls = LSCopyApplicationURLsForBundleIdentifier(rawID as CFString, nil)?
                    .takeRetainedValue() as? [URL],
                  let appURL = urls.first else { continue }

            let name = fileNameWithoutExtension(appURL)
            let icon = NSWorkspace.shared.icon(forFile: appURL.path)
            icon.size = NSSize(width: 18, height: 18)

            browsers.append(BrowserInfo(bundleID: rawID, name: name, icon: icon, url: appURL))
        }

        browsers.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return browsers
    }

    private func currentDefaultBrowserID() -> String? {
        guard let cfStr = LSCopyDefaultHandlerForURLScheme("https" as CFString)?.takeRetainedValue() else {
            return nil
        }
        return (cfStr as String).lowercased()
    }

    // MARK: - Menu Building

    private func rebuildMenu() {
        guard let menu = statusItem.menu else { return }
        menu.removeAllItems()

        let browsers = installedBrowsers()
        let currentID = currentDefaultBrowserID()

        // Header
        let header = NSMenuItem(title: "Default Browser", action: nil, keyEquivalent: "")
        header.attributedTitle = NSAttributedString(
            string: "Default Browser",
            attributes: [.font: NSFont.boldSystemFont(ofSize: 13)]
        )
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        // Browser list
        if browsers.isEmpty {
            let empty = NSMenuItem(title: "No browsers found", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for browser in browsers {
                let item = NSMenuItem(
                    title: browser.name,
                    action: #selector(browserSelected(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = browser.bundleID
                item.image = browser.icon

                if browser.bundleID.lowercased() == currentID {
                    item.state = .on
                }

                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        // Refresh
        let refresh = NSMenuItem(title: "Refresh Browsers", action: #selector(refreshClicked), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)

        // Launch at Login (macOS 13+)
        if #available(macOS 13.0, *) {
            let loginItem = NSMenuItem(
                title: "Launch at Login",
                action: #selector(toggleLaunchAtLogin(_:)),
                keyEquivalent: ""
            )
            loginItem.target = self
            let service = SMAppService.mainApp
            loginItem.state = (service.status == .enabled) ? .on : .off
            menu.addItem(loginItem)
        }

        menu.addItem(.separator())

        // Quit
        let quit = NSMenuItem(title: "Quit Arre", action: #selector(quitClicked), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    // MARK: - Status Icon

    private func updateStatusIcon() {
        guard let button = statusItem.button else { return }
        let currentID = currentDefaultBrowserID()
        let browsers = installedBrowsers()

        if let id = currentID,
           let browser = browsers.first(where: { $0.bundleID.lowercased() == id }),
           let icon = browser.icon {
            let copy = icon.copy() as! NSImage
            copy.size = NSSize(width: 18, height: 18)
            copy.isTemplate = false
            button.image = copy
        } else {
            button.image = NSImage(systemSymbolName: "globe", accessibilityDescription: "Arre")
        }
    }

    // MARK: - Actions

    @objc private func browserSelected(_ sender: NSMenuItem) {
        guard let bundleID = sender.representedObject as? String else { return }

        let schemes: [CFString] = ["http" as CFString, "https" as CFString]
        for scheme in schemes {
            LSSetDefaultHandlerForURLScheme(scheme, bundleID as CFString)
        }

        updateStatusIcon()
    }

    @objc private func refreshClicked() {
        rebuildMenu()
        updateStatusIcon()
    }

    @available(macOS 13.0, *)
    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
                sender.state = .off
            } else {
                try service.register()
                sender.state = .on
            }
        } catch {
            NSLog("Arre: launch-at-login toggle failed: \(error)")
        }
    }

    @objc private func quitClicked() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Helpers

    private func fileNameWithoutExtension(_ url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
        return name.isEmpty ? url.lastPathComponent : name
    }
}

// MARK: - NSMenuDelegate

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }
}
