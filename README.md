# Screen Tally

A native macOS menu bar app that displays a colored border around your screen based on tally data from a Ross Carbonite video switcher. Helps ProPresenter operators know when they're live.

![Screen Tally Screenshot](docs/images/screenshot.png)

## Features

- **Red border** when source is on Program (live)
- **Green border** when source is on Preview
- **Multi-display support** - choose which screen shows the border
- **TSL 5.0 and 3.1** protocol support with auto-detection
- **Source picker** - select which switcher input to monitor
- **Configurable border thickness** (4pt, 8pt, 12pt, 16pt)
- **Debug mode** - manually trigger red/green borders for testing
- **Menu bar icon** reflects current tally state

## Requirements

- macOS 15.0 or later
- Apple Silicon or Intel Mac
- Ross Carbonite switcher configured to send TSL data

## Installation

1. Download `ScreenTally-v1.0.6-aarch64.zip` from [Releases](../../releases)
2. Extract the zip file
3. Move `Screen Tally.app` to your Applications folder
4. Right-click the app and select "Open" (required for first launch due to ad-hoc signing)

## Usage

### Quick Start

1. Launch Screen Tally - a gray circle appears in your menu bar
2. Click the menu bar icon to open the settings popover
3. Configure your TSL port (default: 5201)
4. On your Ross Carbonite, configure DashBoard to send TSL 5.0 data to this Mac's IP address on port 5201
5. Once connected, select your source from the "Monitor Source" dropdown
6. The border will appear when your source goes to Program (red) or Preview (green)

### Ross Carbonite Configuration

1. Open DashBoard and connect to your Carbonite
2. Go to Configuration > Devices
3. Add Device > Type: TSL UMD > Driver: TSL 5
4. Set the IP address to your Mac's IP
5. Set the port to 5201 (or your configured port)
6. Save

### Settings

| Setting | Description |
|---------|-------------|
| Port | TCP port to listen on (default: 5201) |
| Monitor Source | Which switcher input to watch for tally |
| Show border on Preview | Whether to show green border on preview |
| Border thickness | Width of the border in points |
| Display | Which screen shows the border |

## Building from Source

Requires Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
# Clone the repository
git clone https://github.com/NorthwoodsCommunityChurch/screen-tally.git
cd screen-tally

# Generate Xcode project
xcodegen generate

# Build
xcodebuild -scheme ScreenTally -configuration Release build

# The app will be in DerivedData
```

## Project Structure

```
Screen Tally/
├── Project.yml                    # XcodeGen configuration
├── ScreenTally/
│   ├── ScreenTallyApp.swift       # App entry point
│   ├── AppDelegate.swift          # Lifecycle management
│   ├── Models/
│   │   ├── TallyState.swift       # Tally state enum
│   │   └── AppSettings.swift      # UserDefaults persistence
│   ├── Services/
│   │   └── TSLListener.swift      # TSL 5.0/3.1 TCP listener
│   ├── Views/
│   │   └── SettingsView.swift     # Settings window
│   └── Controllers/
│       ├── StatusBarController.swift    # Menu bar management
│       └── BorderOverlayController.swift # Screen border overlay
└── docs/
    └── images/                    # Screenshots
```

## How It Works

Screen Tally acts as a TSL UMD server. The Ross Carbonite connects to it as a TCP client and sends tally state updates for all sources. The app:

1. Listens on a configurable TCP port
2. Auto-detects TSL 5.0 vs 3.1 protocol framing
3. Parses tally data for all sources
4. Displays a border when the monitored source is on Program or Preview

## License

MIT License - see [LICENSE](LICENSE) for details.

## Credits

See [CREDITS.md](CREDITS.md) for third-party acknowledgments.
