<p align="center">
  <img src="docs/icon.png" alt="MoveMouse" width="160">
</p>

# MoveMouse

A small macOS menu bar app that smoothly moves the cursor while you are idle, so other programs see user activity (the macOS counterpart of Move Mouse on Windows).

## Features

- Menu bar only (no Dock icon).
- Moves the mouse **only when the user is idle**; the idle threshold is configurable.
- Random direction and random distance (from 1 px up to a configurable maximum), kept within the screen bounds.
- Smooth ease-in-out animation, aborted as soon as the user touches the mouse.
- Configurable interval between movements.
- Schedule: per-day enable switch and working hours (week starts on Monday; ranges crossing midnight are supported).
- The menu bar icon turns green while the app is actually moving the mouse.
- Pauses while the screen is locked or another user is active (fast user switching).
- Optional launch at login (`SMAppService`).
- Settings persist between launches.
- English UI by default; Polish when the system language is Polish. The language can also be chosen in Settings.

## Requirements

- macOS 14 or later
- Xcode to build; optionally [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## Building

```sh
open MoveMouse.xcodeproj
```

or from the command line:

```sh
xcodebuild -project MoveMouse.xcodeproj -scheme MoveMouse -configuration Release -derivedDataPath build build
```

The app is produced at `build/Build/Products/Release/MoveMouse.app`. Set your own Team in *Signing & Capabilities* before running from Xcode.

Project configuration lives in `project.yml`; after changing it, regenerate the project with `xcodegen generate`.

## Distribution

```sh
./scripts/make-dmg.sh
```

Builds a universal (Apple Silicon + Intel) app and creates `build/MoveMouse.dmg` containing the app and an `Applications` shortcut, so users install it by dragging the app onto it. The mounted volume uses the app icon as well.

The app is ad-hoc signed, so Gatekeeper blocks it on other Macs at first launch: right-click the app → *Open* (or allow it in *System Settings → Privacy & Security*). To avoid this, sign with a Developer ID certificate and notarize the DMG (requires a paid Apple Developer account).

## Permissions

Moving the cursor requires the **Accessibility** permission: *System Settings → Privacy & Security → Accessibility*. The app prompts for it from its menu.

For launch at login, copy the app to `/Applications` first.

## Project layout

- `MoveMouse/MoveMouseApp.swift` – the entire app
- `MoveMouse/Assets.xcassets` – app icon (`AppIcon.appiconset`) and rat SVG
- `scripts/make-dmg.sh` – builds the distributable DMG
- `scripts/render-icon.swift` – renders the app icon PNGs from the SVG
- `project.yml` – XcodeGen project definition
- `docs/icon.png` – gray icon used in this README

## License

Released under the [MIT License](LICENSE). Copyright (c) 2026 Adrian Frydmański.
