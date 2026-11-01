# Keypause

A tiny macOS menu bar app that disables your keyboard while you clean it.

- Lives in the menu bar (no Dock icon).
- **Start Cleaning** locks every key (including media/function keys) and dims the screen with a countdown.
- The mouse/trackpad keep working, so **Unlock Now** is always one click away; it also unlocks automatically when the timer ends.
- Keeps the display awake during the session.

## Build & run

```sh
./Scripts/build.sh
open dist/Keypause.app
```

On first use, grant **Accessibility** access in System Settings → Privacy & Security.
(Rebuilding changes the ad-hoc signature, so you may need to re-grant after a rebuild.)

Requires macOS 14+.
