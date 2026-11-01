<p align="center">
  <img src="Resources/AppIcon.png" width="128" alt="Keypause icon">
</p>

<h1 align="center">Keypause</h1>

<p align="center">
  <b>Wipe your keyboard without typing gibberish, closing windows, or sending half a message.</b><br>
  A tiny menu bar app that locks every key for a few minutes, then gives them back.
</p>

<p align="center">
  <a href="https://github.com/destucr/Keypause/releases/latest"><img alt="Download" src="https://img.shields.io/github/v/release/destucr/Keypause?label=download"></a>
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-blue">
  <img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-green">
</p>

---

## The problem

Cleaning a laptop keyboard means pressing it a hundred times by accident: a stray `⌘W` closes your window, `⌘Q` quits your app, a brush stroke fires off a half-typed message. The usual fixes are to shut the lid (and lose your session), turn the Mac off, or just be careful and hope.

## The fix

Click the keycap in your menu bar, pick a time, and wipe away. Every key is ignored until the timer ends. When it does, your keyboard comes back on its own.

```
Click the menu bar icon  →  Start Cleaning  →  wipe  →  keys unlock automatically
```

## Why it's pleasant to use

- **It stays out of your way.** A small floating HUD shows the countdown and an **Unlock** button. It never steals focus, so a video keeps playing, even full screen, while you clean.
- **Made for the notch.** On notched MacBooks the HUD grows out of the notch like an island and tucks back in when you're done. On other Macs it's a clean pill under the menu bar.
- **Locks *everything*.** Letters, modifiers, function keys, and media, volume and brightness keys. Your mouse and trackpad keep working, so you can always click **Unlock**.
- **Never gets stuck.** The timer always ends (30 s, 1, 2, 5 or 10 min), and the **Unlock** button is one click away.
- **Won't fall asleep on you.** The display stays awake while locked, so the screen saver can't interrupt mid-wipe.
- **Optional focus mode.** *Dim Screen While Locked* darkens your displays (off by default, and you can still click through it).
- **Quiet by design.** Lives in the menu bar only: no Dock icon, no windows, and an optional *Launch at Login*.

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

### Allow it to lock the keys (one time)

To block key presses, macOS requires you to grant permission. Open **System Settings → Privacy & Security → Accessibility** (called *Device Control and Data Access* on newer macOS), switch **Keypause** on, and allow **Input Monitoring** too if it asks. Keypause's welcome window has a **Grant Access…** button that takes you straight there.

## Privacy

Keypause **never reads, stores, or sends your keystrokes**: the lock just drops key events before apps see them. It makes no network connections and collects nothing. The source is small enough to read in one sitting.

## Good to know

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

## Build from source

Requires macOS 14+ and Xcode (Swift 6).

```sh
./Scripts/build.sh        # builds dist/Keypause.app
open dist/Keypause.app

./Scripts/package.sh      # also produces dist/Keypause.zip and .dmg
```

Regenerate the app icon with `swift Scripts/make-icon.swift Resources/AppIcon.icns`.

### How it works

A single `CGEventTap` on the session drops key-down, key-up, modifier and system-defined (media) events while locked. The countdown, the display-sleep prevention (`IOPMAssertion`), and the notch-aware HUD (sized at runtime from `NSScreen.safeAreaInsets`, so it fits every notched Mac) are plain AppKit and SwiftUI. There are no dependencies.

## License

[MIT](LICENSE) © Destu Cikal
