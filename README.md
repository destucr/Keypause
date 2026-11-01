<p align="center">
  <img src="Resources/AppIcon.png" width="128" alt="Keypause icon">
</p>

<h1 align="center">Keypause</h1>

<p align="center">
  <b>Press one button. Wipe your keyboard. Done.</b><br>
  A tiny menu bar app that locks every key while you wipe, then gives them back.
</p>

<p align="center">
  <a href="https://github.com/destucr/Keypause/releases/latest"><img alt="Download" src="https://img.shields.io/github/v/release/destucr/Keypause?label=download"></a>
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-blue">
  <img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-green">
</p>

---

You're about to wipe down your keyboard. One slip and `⌘W` closes your window, `⌘Q` quits your app, and a brush stroke sends half a message.

Keypause switches the keys off for a minute. Wipe away. They come back on their own.

```
⌃⌥⌘K  →  wipe  →  keys are back
```

## What you get

- **A lock that stays out of the way.** A small HUD shows the countdown and an **Unlock** button. It never steals focus, so your video keeps playing, even full screen.
- **Every key, actually off.** Letters, shortcuts, function keys, even media, volume and brightness. Your mouse and trackpad still work, so **Unlock** is always one click away.
- **No way to get stuck.** Pick 30 s, 1, 2, 5 or 10 minutes. When the timer ends, the keys return.
- **The screen stays on.** No screen saver halfway through a wipe.
- **One keystroke to start.** `⌃⌥⌘K` from anywhere, or use the menu bar icon. (Unlock is the on-screen button or the timer, since the keys are off.)
- **Scriptable.** Start it from Terminal, Raycast or Shortcuts. See below.
- **On a notched MacBook, it comes out of the notch.** Everywhere else it's a neat pill under the menu bar.
- **Optional dimming.** *Dim Screen While Locked* darkens your displays if you want it. Off by default.
- **Stays out of your Dock.** It lives in the menu bar, with an optional *Launch at Login*.

## Install

### Homebrew (recommended)

```sh
brew install --cask destucr/tap/keypause
```

### Download

Grab `Keypause.dmg` from [**Releases**](https://github.com/destucr/Keypause/releases/latest), open it, and drag **Keypause** to **Applications**.

> **First launch:** Keypause isn't notarized by Apple (that requires a paid developer account), so macOS may say it can't verify the app. Right-click the app and choose **Open**, or run:
> ```sh
> xattr -dr com.apple.quarantine /Applications/Keypause.app
> ```
> The Homebrew install does this for you.

### One-time permission

To block key presses, macOS requires you to grant permission. Open **System Settings → Privacy & Security → Accessibility** (called *Device Control and Data Access* on newer macOS), switch **Keypause** on, and allow **Input Monitoring** too if it asks. Keypause's welcome window has a **Grant Access…** button that takes you straight there.

## Run it from Terminal, Raycast or Shortcuts

```sh
open "keypause://start"               # uses your chosen duration
open "keypause://start?seconds=90"    # lock for 90 seconds
open "keypause://stop"                # unlock early
```

## Privacy

Keypause **never reads, stores, or sends your keystrokes**: the lock just drops key events before apps see them. It makes no network connections and collects nothing. The source is small enough to read in one sitting.

## Heads up

- **The power / Touch ID button can't be blocked** by any software, so it still works.

## Troubleshooting

**macOS still says Keypause needs permission, even though the switch is on.**
macOS ties each grant to the exact app that received it, and a stale entry (often left by an update or an earlier copy of the app) can look enabled while doing nothing. Either remove Keypause from the list with **−** and add it back with **+**, or reset it from Terminal and grant it again:

```sh
tccutil reset Accessibility com.destucr.Keypause
tccutil reset ListenEvent   com.destucr.Keypause
```

Then quit and reopen Keypause and click **Grant Access…**.

**"Keypause can't be opened" / "cannot verify the developer".**
Right-click the app → **Open**, or clear the quarantine flag:

```sh
xattr -dr com.apple.quarantine /Applications/Keypause.app
```

**Keypause is stuck or you want to quit it from Terminal.**

```sh
pkill -x Keypause
```

**Start from scratch** (removes the app, its settings and its permissions):

```sh
brew uninstall --cask --zap keypause   # if installed with Homebrew
tccutil reset All com.destucr.Keypause
```

## Build it yourself

Requires macOS 14+ and Xcode (Swift 6).

```sh
./Scripts/build.sh        # builds dist/Keypause.app
open dist/Keypause.app

./Scripts/package.sh      # also produces dist/Keypause.zip and .dmg
```

Regenerate the app icon with `swift Scripts/make-icon.swift Resources/AppIcon.icns`.

### Under the hood

A single `CGEventTap` on the session drops key-down, key-up, modifier and system-defined (media) events while locked. The countdown, the display-sleep prevention (`IOPMAssertion`), and the notch-aware HUD (sized at runtime from `NSScreen.safeAreaInsets`, so it fits every notched Mac) are plain AppKit and SwiftUI. There are no dependencies.

## License

[MIT](LICENSE) © Destu Cikal
