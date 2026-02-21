# Cambiador
A simple macOS menu bar app for switching your default browser. Pick a browser, and all your links open there. Need to switch? Click the menu bar and choose a different one.

## Why Cambiador?
Inspired by tools like Choosy, Finicky, and Browserosaurus, Cambiador takes a simpler approach. **No rules to configure. No prompts on every link click.** Just pick your browser from the menu bar, and all links go there. When you need to switch, click the menu bar icon and choose a different one.

Perfect for when you want Safari for personal browsing and Chrome for work, or when you're testing web apps across different browsers.

## How It Works
Cambiador registers itself as a **browser application**. On first launch, it becomes your system default browser (one-time macOS confirmation). After that, every link click flows through Cambiador, which immediately forwards the URL to whichever real browser you've selected in the menu bar.

Once Cambiador is your default browser, switching which real browser handles your links is just an internal setting change. No system prompts, no delays. Instant and silent.

```
Link clicked anywhere in macOS
        ↓
macOS routes to Cambiador (the "default browser")
        ↓
Cambiador forwards to your chosen real browser
        ↓
URL opens in Chrome / Safari / Firefox / etc.
```

## Features
- **Menu bar icon** — shows the icon of your currently selected browser
- **One-click switching** — pick any browser from the dropdown, no OS confirmation
- **Auto-detection** — discovers installed browsers via Launch Services
- **Browser icons** — app icons displayed next to each browser name
- **URL validation** — only forwards `http` and `https` URLs; blocks `file://`, `javascript://`, etc.
- **Safe fallback** — falls back to Safari directly if the selected browser can't be found (no infinite loops)
- **Launch at Login** — toggle in the menu (macOS 13+)
- **Reclaim default** — if something else takes over as default browser, a menu item lets you reclaim it
- **Lightweight** — native Swift/AppKit, no external dependencies, minimal resource usage

## Installation
```bash
git clone https://github.com/yourusername/cambiador.git
cd cambiador
open Cambiador.xcodeproj
```

Build and run in Xcode (⌘R). No Apple Developer account needed.

## First Launch
1. Build and run (⌘R) or open the built `.app`
2. macOS will ask **once** if you want Cambiador as your default browser — say yes
3. Cambiador remembers your previous default browser and pre-selects it
4. The menu bar icon appears — you're done

## Usage
1. Click the Cambiador icon in the menu bar
2. Select any browser from the "Forward Links To" list
3. The checkmark moves instantly — no confirmation dialog
4. All links now open in your selected browser

## Requirements
- macOS 12.0 (Monterey) or later
- Xcode to build

## Security
- **URL scheme validation** — only `http` and `https` URLs are forwarded; all other schemes are blocked and logged
- **No infinite loops** — fallback paths open Safari directly by app URL, never through `NSWorkspace.shared.open(url)` which would route back to Cambiador
- **Sandbox disabled** — required for Launch Services API access; the app has no network activity of its own
- **Preferences in UserDefaults** — selected browser stored as a bundle ID string in standard UserDefaults

## License
MIT License

## Contributing
This is intentionally a minimal tool, but improvements to browser detection, UI polish, and bug fixes are always appreciated.
