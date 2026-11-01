<p align="center"><img src="Resources/AppIcon.png" width="128" alt="Keypause icon"></p>

# Keypause

Lock your Mac's keyboard while you clean it. A tiny menu bar app that gets out of your way.

## Features

- **Menu bar only** – no Dock icon, no windows in your way.
- **Locks every key**, including media, volume and brightness keys. Mouse and trackpad keep working.
- **Doesn't interrupt what you're doing** – a small floating pill shows the countdown and an **Unlock** button without stealing focus, so a video keeps playing (even full screen).
- **Notch-aware** – on MacBooks with a notch, the HUD grows out of the notch like an island; on other Macs it's a pill in the top-right corner.
- **Auto-unlock** when the timer ends (30 s, 1, 2, 5 or 10 min).
- **Keeps the display awake** while locked.
- Optional **Dim Screen While Locked** (off by default; you can still click through it).
- Launch at Login.

## Install

Download `Keypause.zip` from [Releases](../../releases), unzip, and move `Keypause.app` to `/Applications`.

The app is ad-hoc signed (not notarized), so the first time: right-click → **Open**, or run
`xattr -dr com.apple.quarantine /Applications/Keypause.app`.

Then allow it in **System Settings → Privacy & Security → Accessibility** (required to intercept key events).

## Build from source

Requires macOS 14+ and Xcode / Swift 6.

```sh
./Scripts/build.sh
open dist/Keypause.app
```

Regenerate the icon with `swift Scripts/make-icon.swift Resources/AppIcon.icns`.

## Notes

- The physical power / Touch ID button can't be blocked by software.
- Rebuilding changes the ad-hoc signature, so macOS may ask you to re-grant Accessibility.

## License

[MIT](LICENSE)
