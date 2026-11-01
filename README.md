<p align="center">
  <img src="Resources/AppIcon.png" width="128" alt="Keypause icon">
</p>

<h1 align="center">Keypause</h1>

<p align="center">
  <b>Press one button. Wipe your keyboard. Done.</b><br>
  A menu bar app that turns every key off while you clean, then back on.
</p>

<p align="center">
  <a href="https://github.com/destucr/Keypause/releases/latest"><img alt="Download" src="https://img.shields.io/github/v/release/destucr/Keypause?label=download"></a>
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-blue">
  <img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-green">
</p>

## Features

- **Every key off**, including shortcuts, function keys and media keys. Mouse and trackpad keep working.
- **Doesn't interrupt you.** A small HUD shows the countdown and an **Unlock** button without stealing focus, so video keeps playing.
- **Starts from anywhere** with `⌃⌥⌘K`, the menu bar, or Terminal.
- **Always ends.** Pick 30 s to 10 min. The keys come back when the timer does.
- **Screen stays awake** while locked.
- **Notch-friendly.** The HUD grows out of the notch on MacBooks that have one.

## Install

```sh
brew install --cask destucr/tap/keypause
```

Or download `Keypause.dmg` from [Releases](https://github.com/destucr/Keypause/releases/latest) and drag it to Applications.

Keypause isn't notarized (no paid Apple developer account), so after a manual download, right-click → **Open** the first time. Homebrew handles this for you.

On first run, switch Keypause on in **System Settings → Privacy & Security → Accessibility** (called *Device Control and Data Access* on newer macOS). The welcome window has a button that opens it.

## Terminal

```sh
open "keypause://start"             # your chosen duration
open "keypause://start?seconds=90"  # custom duration
open "keypause://stop"              # unlock early
```

Works with Raycast and Shortcuts too.

## Privacy

Keypause never reads, stores or sends your keystrokes, and makes no network connections.

## Troubleshooting

**Permission is on but Keypause still asks.** macOS can keep a stale entry after an update. Reset it and grant again:

```sh
tccutil reset Accessibility com.destucr.Keypause
tccutil reset ListenEvent   com.destucr.Keypause
```

**"Can't be opened".** `xattr -dr com.apple.quarantine /Applications/Keypause.app`

The power / Touch ID button can't be blocked by software.

## Build

Requires macOS 14+ and Xcode.

```sh
./Scripts/build.sh && open dist/Keypause.app
```

## License

[MIT](LICENSE) © Destu Cikal
