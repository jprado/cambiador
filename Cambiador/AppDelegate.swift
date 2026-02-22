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

// MARK: - UserDefaults Keys

private enum Defaults {
    static let selectedBrowser = "CambiadorSelectedBrowserID"
    static let hasClaimedDefault = "CambiadorHasClaimedDefault"
    static let previousDefault = "CambiadorPreviousDefaultBrowserID"
}

// MARK: - App Delegate

@objc class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private let selfBundleID = Bundle.main.bundleIdentifier ?? "com.jprado.cambiador"
    private var pendingURLs: [URL] = []
    private var isReady = false

    // MARK: - Init (register URL handler ASAP, before app.run() processes events)

    override init() {
        super.init()
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(_:withReply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // On first launch: remember the user's current default and claim the role
        if !UserDefaults.standard.bool(forKey: Defaults.hasClaimedDefault) {
            captureAndClaimDefault()
        }

        // Set up the menu bar
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "globe", accessibilityDescription: "Cambiador")
        }

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        updateStatusIcon()

        // Now process any URLs that arrived during launch
        isReady = true
        for url in pendingURLs {
            openURLInSelectedBrowser(url)
        }
        pendingURLs.removeAll()
    }

    // MARK: - First-Launch: Capture Previous Default & Claim

    private func captureAndClaimDefault() {
        // Remember whatever browser was default before Cambiador
        if let current = systemDefaultBrowserID(), current.lowercased() != selfBundleID.lowercased() {
            UserDefaults.standard.set(current, forKey: Defaults.previousDefault)
            // Pre-select that browser so links keep going to the same place
            if UserDefaults.standard.string(forKey: Defaults.selectedBrowser) == nil {
                UserDefaults.standard.set(current, forKey: Defaults.selectedBrowser)
            }
        }

        // Set Cambiador as the system default browser (one-time OS confirmation)
        let selfURL = Bundle.main.bundleURL
        let schemes = ["http", "https"]
        let group = DispatchGroup()
        let syncQueue = DispatchQueue(label: "com.jprado.cambiador.claimDefault")
        var anySucceeded = false

        for scheme in schemes {
            group.enter()
            NSWorkspace.shared.setDefaultApplication(at: selfURL,
                                                     toOpenURLsWithScheme: scheme) { error in
                if let error = error {
                    NSLog("Cambiador: failed to set default for \(scheme): \(error)")
                } else {
                    syncQueue.sync { anySucceeded = true }
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            let succeeded = syncQueue.sync { anySucceeded }
            if succeeded {
                UserDefaults.standard.set(true, forKey: Defaults.hasClaimedDefault)
            }
        }
    }

    // MARK: - URL Handling (Proxy)

    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: urlString) else { return }

        // Only forward http and https URLs — reject file://, javascript://, etc.
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            NSLog("Cambiador: blocked non-HTTP URL scheme: \(url.scheme ?? "nil")")
            return
        }

        if isReady {
            openURLInSelectedBrowser(url)
        } else {
            // App is still launching — buffer the URL
            pendingURLs.append(url)
        }
    }

    private func openURLInSelectedBrowser(_ url: URL) {
        let targetID = selectedBrowserID()

        guard let appURL = applicationURL(forBundleID: targetID) else {
            // Fallback: open in Safari directly to avoid infinite loop (we are the default browser)
            openInSafariFallback(url)
            return
        }

        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: config) { _, error in
            if let error = error {
                NSLog("Cambiador: failed to open URL in \(targetID): \(error)")
                // Fallback to Safari to avoid infinite loop
                self.openInSafariFallback(url)
            }
        }
    }

    private func openInSafariFallback(_ url: URL) {
        let safariID = "com.apple.safari"
        guard let safariURL = applicationURL(forBundleID: safariID) else {
            NSLog("Cambiador: Safari not found, cannot open URL")
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([url], withApplicationAt: safariURL, configuration: config, completionHandler: nil)
    }

    // MARK: - Selected Browser (Internal Preference)

    private func selectedBrowserID() -> String {
        if let stored = UserDefaults.standard.string(forKey: Defaults.selectedBrowser) {
            return stored
        }
        // Fallback to whatever was default before Cambiador, or Safari
        return UserDefaults.standard.string(forKey: Defaults.previousDefault) ?? "com.apple.safari"
    }

    // MARK: - Browser Discovery

    private func installedBrowsers() -> [BrowserInfo] {
        guard let probeURL = URL(string: "https://example.com") else {
            NSLog("Cambiador: failed to create probe URL for browser discovery")
            return []
        }
        let appURLs = NSWorkspace.shared.urlsForApplications(toOpen: probeURL)

        // De-duplicate (case-insensitive), exclude ourselves
        var seen = Set<String>()
        var browsers: [BrowserInfo] = []

        for appURL in appURLs {
            guard let bundle = Bundle(url: appURL),
                  let rawID = bundle.bundleIdentifier else { continue }

            let key = rawID.lowercased()
            guard key != selfBundleID.lowercased() else { continue }
            guard !seen.contains(key) else { continue }
            seen.insert(key)

            let name = fileNameWithoutExtension(appURL)
            let icon = NSWorkspace.shared.icon(forFile: appURL.path)
            icon.size = NSSize(width: 18, height: 18)

            browsers.append(BrowserInfo(bundleID: rawID, name: name, icon: icon, url: appURL))
        }

        browsers.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return browsers
    }

    private func systemDefaultBrowserID() -> String? {
        guard let probeURL = URL(string: "https://example.com"),
              let appURL = NSWorkspace.shared.urlForApplication(toOpen: probeURL) else {
            return nil
        }
        return Bundle(url: appURL)?.bundleIdentifier
    }

    // MARK: - Menu Building

    private func rebuildMenu() {
        guard let menu = statusItem.menu else { return }
        menu.removeAllItems()

        let browsers = installedBrowsers()
        let selectedID = selectedBrowserID().lowercased()

        // Header
        let header = NSMenuItem(title: "Forward Links To", action: nil, keyEquivalent: "")
        header.attributedTitle = NSAttributedString(
            string: "Forward Links To",
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

                if browser.bundleID.lowercased() == selectedID {
                    item.state = .on
                }

                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        // Reclaim default (in case user changed it elsewhere)
        let sysDefault = systemDefaultBrowserID()?.lowercased()
        if sysDefault != selfBundleID.lowercased() {
            let reclaim = NSMenuItem(
                title: "Set Cambiador as Default Browser",
                action: #selector(reclaimDefault),
                keyEquivalent: ""
            )
            reclaim.target = self
            menu.addItem(reclaim)
            menu.addItem(.separator())
        }

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
        let quit = NSMenuItem(title: "Quit Cambiador", action: #selector(quitClicked), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    // MARK: - Status Icon

    private func updateStatusIcon() {
        guard let button = statusItem.button else { return }
        let selectedID = selectedBrowserID().lowercased()
        let browsers = installedBrowsers()

        if let browser = browsers.first(where: { $0.bundleID.lowercased() == selectedID }),
           let icon = browser.icon {
            guard let copy = icon.copy() as? NSImage else {
                NSLog("Cambiador: failed to copy browser icon for status bar")
                return
            }
            copy.size = NSSize(width: 18, height: 18)
            copy.isTemplate = false
            button.image = copy
        } else {
            button.image = NSImage(systemSymbolName: "globe", accessibilityDescription: "Cambiador")
        }
    }

    // MARK: - Actions

    @objc private func browserSelected(_ sender: NSMenuItem) {
        guard let bundleID = sender.representedObject as? String else { return }
        UserDefaults.standard.set(bundleID, forKey: Defaults.selectedBrowser)
        updateStatusIcon()
    }

    @objc private func reclaimDefault() {
        let selfURL = Bundle.main.bundleURL
        let schemes = ["http", "https"]
        for scheme in schemes {
            NSWorkspace.shared.setDefaultApplication(at: selfURL,
                                                     toOpenURLsWithScheme: scheme) { error in
                if let error = error {
                    NSLog("Cambiador: failed to reclaim default for \(scheme): \(error)")
                }
            }
        }
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
            NSLog("Cambiador: launch-at-login toggle failed: \(error)")
        }
    }

    @objc private func quitClicked() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Helpers

    private func applicationURL(forBundleID bundleID: String) -> URL? {
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

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
