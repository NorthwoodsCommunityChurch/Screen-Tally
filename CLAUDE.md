# Screen Tally — Project Context

Native macOS menu-bar app that draws a colored border around a chosen screen based on tally
data from a Ross Carbonite video switcher — red when the monitored source is on Program (live),
green when on Preview. Internal Northwoods AVL tool so ProPresenter operators know on sight when
they're live. Stack: SwiftUI + AppKit + Network framework + Sparkle, menu-bar-only (`LSUIElement`),
built with XcodeGen.

> **Read first:** [SECURITY.md](SECURITY.md) — security review (1 Critical, 2 High; all open as of 2026-03-01).
> [README.md](README.md) for end-user setup and Carbonite/DashBoard config. [CREDITS.md](CREDITS.md) for third-party libs.
> Org release + Sparkle details: `../App Updates/SPARKLE-GUIDE.md` and `../RELEASE-PROCESS.md`.
> If you read one more thing after this file, read **SECURITY.md** — the open findings shape any update-path work.

---

## Status — 2026-07-03
- **Stage:** active (shipping, v1.0.7)
- **Renamed back from "Limbus Live" to "Screen Tally" on 2026-07-03.** The app shipped as
  "Screen Tally" v1.0.0, was rebranded to "Limbus Live" for versions 1.0.1–1.0.5, and is now back
  to "Screen Tally" — same codebase throughout, just the third name change. Bundle ID reverted to
  `com.northwoodschurch.screentally` to match.
- **Production had silently drifted during the Limbus Live era — now fixed.** Investigating the
  rename turned up that the media Mac (`media-mac`, 10.11.1.100) was never actually running Limbus
  Live: it had been running the original Feb-2026 "Screen Tally" v1.0.0 build the entire time,
  missing every fix through 1.0.5. "Limbus Live" existed there only as orphaned prefs/cache and a
  **dangling Login Item** pointing at a deleted app — and the real running app wasn't a login item
  at all, so a reboot would have left the booth with no tally app running. The v1.0.6 release
  fixed this: redeployed to `media-mac`, dangling Login Item removed, Screen Tally re-registered
  as a proper login item. See Document history below for the day-of details.
- **v1.0.7 fixed a port-display bug found during that redeploy**: the port `TextField` used
  `format: .number`, whose default `IntegerFormatStyle` adds a locale thousands-separator (5203
  showed as "5,203"). Fixed with `.number.grouping(.never)` in both `MenuBarView` and
  `SettingsView`.
- **Separately reported "stuck on Listening" status is NOT a code bug — confirmed via tcpdump.**
  After the v1.0.6 redeploy, the connection status stayed on "Listening..." and a manual
  "Restart" appeared to fix it. Investigation (app logs + a raw `tcpdump -i any port 5203`
  capture on `media-mac`) showed **zero packets ever reach port 5203** — the listener is
  correctly bound and the accept/connection code is untouched and working; the Carbonite simply
  isn't attempting to reconnect. Likely cause: killing the old process during the redeploy also
  killed the Carbonite's existing TCP session, and this TSL sender doesn't appear to auto-retry a
  dropped connection. If this recurs, check/re-save the Carbonite's TSL UMD device entry in
  DashBoard (or power-cycle it) rather than looking for a fix in `TSLListener.swift` — the code
  is confirmed correct here.
- **Works:** TSL 5.0 / 3.1 auto-detecting TCP listener; source picker; red (Program) / green (Preview)
  screen-border overlay with configurable thickness; multi-display target selection; menu-bar icon
  reflects tally state; debug mode to force red/green; Sparkle auto-update.
- **In progress / next:** a new Screen Tally-branded app icon — current icon is the "LL" monogram
  from the Limbus Live era, kept as a placeholder rather than blocking this rename.
- **Known issues:**
  - **Two live, conflicting update paths** (see Conventions & gotchas + SECURITY.md LL-03). Sparkle is
    wired in `AppDelegate`/`StatusBarController`, but the custom `UpdateManager` is *also* actively
    called from `MenuBarView`. The custom updater has the CRITICAL command-injection
    finding (LL-01) and does no signature verification. Decide which path to keep before next release.
    Unrelated to the rename — still open, unresolved by this work.
  - All 7 security findings (1 Critical, 2 High, 3 Medium, 1 Low) still **Open**. Finding IDs keep
    the `LL-0x` prefix from the Limbus Live era — not worth relabeling, they're ticket-style
    identifiers, not app references.
  - README links `docs/images/screenshot.png`, but `docs/` is currently empty.

> Fresh Claude: read this Status block + the Update Protocol at the bottom and you're current.

## What it does
Runs quietly in the menu bar on the booth Mac next to ProPresenter. The Ross Carbonite (configured
in DashBoard to send TSL UMD data) connects to this app as a TCP client on a configurable port
(default 5201). The app parses tally state for all switcher sources; when the operator-selected
"Monitor Source" goes to Program it paints a red border around the chosen display, green for Preview.
Gives the operator an unmissable peripheral cue that their output is live without watching a tally light.

## Architecture
SwiftUI/AppKit hybrid, menu-bar-only. `ScreenTallyApp` (@main) is just a `Settings` scene; all real
wiring happens in `AppDelegate.applicationDidFinishLaunching`. Data flow:

```
TSLListener (NWListener TCP server, auto-detects TSL 5.0 vs 3.1, parses tally per source)
   └─▶ @Observable state: monitoredTally, isConnected
AppDelegate.startObserving(): 50ms withObservationTracking loop reads
   AppSettings + listener state (debugTallyOverride wins over live tally), then drives →
     ├─▶ StatusBarController.updateIcon()   (menu-bar circle: white/red/green)
     └─▶ BorderOverlayController.updateTally()  (screen-edge border overlay window)
AppDelegate also creates SPUStandardUpdaterController (Sparkle) and hands its updater
   to StatusBarController.
MenuBarView (popover UI) ALSO drives the separate custom UpdateManager.shared — see gotchas.
```

### Where things live
```
ScreenTally/
├── ScreenTallyApp.swift       @main — Settings scene only; delegates to AppDelegate
├── AppDelegate.swift          lifecycle, Sparkle init, the 50ms observation loop
├── Models/
│   ├── TallyState.swift       enum: program / preview / previewProgram / clear
│   ├── AppSettings.swift      @Observable UserDefaults persistence (port, source, thickness, display, debug override)
│   └── Version.swift          hardcoded "1.0.7", GitHub owner/repo, semver compare (feeds custom UpdateManager)
├── Services/
│   ├── TSLListener.swift      NWListener TCP server, TSL 5.0/3.1 parsing  ← LL-02/04/05/07 live here
│   └── UpdateManager.swift    custom GitHub-release self-updater  ← LL-01/03/06 live here (redundant w/ Sparkle)
├── Views/
│   ├── MenuBarView.swift      popover UI; calls UpdateManager.shared
│   └── SettingsView.swift     Settings window
├── Controllers/
│   ├── StatusBarController.swift   NSStatusItem + popover + holds SPUUpdater
│   └── BorderOverlayController.swift  borderless overlay window per display
├── Assets.xcassets/AppIcon.appiconset   app icon — still the Limbus Live-era "LL" monogram, flagged for redesign
└── Info.plist
Project.yml      ← XcodeGen source of truth (edit this, then regenerate the .xcodeproj)
Icons/           source icon art (svg + 1024 png) — filenames still say limbus-live-*, contents pending redesign
build/           local build output / xcarchive (gitignored)
```

## Key identifiers
| Thing | Value |
|---|---|
| Type / stack | macOS Swift (SwiftUI + AppKit + Network + Sparkle), menu-bar-only (`LSUIElement`) |
| GitHub repo | `NorthwoodsCommunityChurch/Screen-Tally` (was `Limbus-Live` 2026-03 to 2026-07; GitHub forwards the old URL) |
| Bundle ID | `com.northwoodschurch.screentally` |
| Current version | 1.0.7 (CFBundleShortVersionString = CFBundleVersion = 1.0.7; `Version.current` = 1.0.7) |
| Update feed (Sparkle) | `https://northwoodscommunitychurch.github.io/app-updates/appcast-screentally.xml` (app-specific; `appcast-limbuslive.xml` kept as historical record, no longer updated) |
| Sparkle public key | `VIMxKZmmRokdMcHK5d3QU4+qHgBglmkVFP5aAVvxgqM=` (unchanged across the rename — same signing key) |
| Secrets location | none in repo (no credentials; Sparkle public key is safe to commit). Sparkle private signing key lives in OneDrive secrets, never in git |
| Production machine(s) | `media-mac` (10.11.1.100, SSH alias `media-mac` in `~/.ssh/config`) — the booth Mac next to ProPresenter. Confirmed 2026-07-03 after being unrecorded since the project's creation. |
| Deployment / build | macOS 15.0 · Xcode 16.0 · Swift 6.0 · Sparkle 2.0.0+ · ad-hoc signed (`CODE_SIGN_IDENTITY = "-"`) |
| Check for Updates | menu-bar popover button (currently triggers the custom UpdateManager, not Sparkle — see gotchas) |
| Default TSL port | 5201 (configurable) — `media-mac` is actually configured for **5203**, not the default |

## Build / Run / Release
```bash
# Regenerate the Xcode project after editing Project.yml
xcodegen generate

# Build (Release)
xcodebuild -scheme ScreenTally -configuration Release build
# Built app lands in DerivedData (and build/Screen Tally.app from prior archive runs)
```
Release: standard Northwoods Sparkle flow — build, zip, upload to the `app-updates` release,
download the uploaded zip, sign **that** downloaded file (EdDSA signing is randomized), put the
signature in `appcast-screentally.xml` (NOT the shared appcast.xml, NOT the retired
appcast-limbuslive.xml). Full steps:
`../App Updates/SPARKLE-GUIDE.md` and `../RELEASE-PROCESS.md`. Ad-hoc signing means first launch
on a new Mac needs right-click → Open. Ask Aaron before bumping the version.

## Conventions & gotchas
- **XcodeGen is the source of truth** — edit `Project.yml`, not the generated `.xcodeproj` (the
  `.xcodeproj` is gitignored). Version lives in `Project.yml` info properties AND, separately,
  hardcoded in `Models/Version.swift` (`Version.current`) — keep both in sync when bumping.
- **Two update mechanisms exist and both are wired in.** This is the biggest footgun. Sparkle
  (the org standard, signature-verified) is initialized in `AppDelegate`. A hand-rolled
  `UpdateManager` that downloads a GitHub release zip and swaps the .app via a bash trampoline is
  *still called* from `MenuBarView` (manual button at line 166, auto-check at 249). The custom path
  carries the CRITICAL command-injection finding (LL-01) and does no signature verification (LL-03).
  Per the org standard, apps should rely solely on Sparkle — before next release, either remove the
  custom `UpdateManager`/its `MenuBarView` calls or, at minimum, fix LL-01 (POSIX-quote interpolated
  paths) and LL-06 (regex-validate the GitHub tag). Don't ship another version leaving both active.
- **Renamed twice.** Screen Tally (v1.0.0) → Limbus Live (v1.0.1–1.0.5, 2026-03 to 2026-07) →
  Screen Tally again (v1.0.6+). `UpdateManager`'s log subsystem string and the trampoline script
  header have said `com.northwoodschurch.screentally` / "Screen Tally Update Trampoline" the
  whole time — that's now correct again, not a vestige to clean up.
- **TCP listener binds on all interfaces (0.0.0.0)** by design — the Carbonite connects over the
  LAN, so localhost-only won't work (LL-02). No auth on the TSL stream (LL-04) and no receive-buffer
  cap (LL-05). These are largely inherent to the TSL UMD protocol; document as accepted risk or add
  an IP allowlist / 64KB buffer cap rather than ripping out the listener.
- **Tally drive loop is a 50ms `withObservationTracking` poll** in `AppDelegate`, not a pure
  reactive binding — it re-reads settings + listener state every tick. `debugTallyOverride` always
  wins over the live tally (used by debug mode to force red/green for testing).
- **`GENERATE_INFOPLIST_FILE` is not used here** — this target ships an explicit
  `ScreenTally/Info.plist`, so `SUPublicEDKey`/`SUFeedURL` are set there (via `Project.yml` info
  properties), not via `INFOPLIST_KEY_*` build settings.
- **Login Item survival matters here.** This app has no LaunchAgent — it relies on being
  registered as a login item to survive a reboot on the booth Mac. If you ever rename or move
  the bundle again, explicitly re-register it (`AppSettings.launchAtLogin` toggles
  `SMAppService.mainApp`, or use System Events' classic login-item list) rather than assuming
  the old registration carries over — it doesn't; a dangling registration for a deleted app is
  exactly what caused the multi-month production drift documented above.

## Update Protocol
Keep this file honest as you work:

| When you… | Update… |
|---|---|
| ship a version | Status date · Current version (both `Project.yml` AND `Version.swift`) · appcast |
| resolve the dual-update-path issue | Status · Conventions & gotchas · Key identifiers (Check for Updates row) |
| add/rename a service, view, or controller | What it does · Architecture · Where things live |
| close a security finding | SECURITY.md status column · Status block |
| hit & fix a gotcha | Conventions & gotchas |
| change build/release steps | Build / Run / Release |

End a work session with **`/save`** — it commits, pushes, syncs docs, and leaves cross-project notes.

## Document history
| Date | Change |
|---|---|
| 2026-07-03 | v1.0.7: fixed port field showing a thousands separator (`.number` → `.number.grouping(.never)`). Also investigated a separately-reported "stuck on Listening" status post-redeploy — confirmed via `tcpdump` that zero packets reach port 5203, ruling out a code bug; documented as a likely Carbonite-side reconnect issue in Status above. |
| 2026-07-03 | Renamed app back from Limbus Live to Screen Tally (bundle id, GitHub repo, appcast, all docs) at v1.0.6. Investigation surfaced that `media-mac` had been running the original v1.0.0 Screen Tally build the whole Limbus Live era (2026-03–2026-07) — Limbus Live never reached production, only left a dangling Login Item. Fixed as part of this release: redeployed current code to `media-mac`, removed the dangling Login Item, registered Screen Tally as a proper login item, recorded `media-mac` (10.11.1.100) as the production machine in Key Identifiers (previously "unknown — verify"). |
| 2026-05-29 | Rewrote CLAUDE.md to Northwoods standard template (was a 2-line security pointer); documented live dual-update-path divergence |
