# Keypause help

**Keypause still asks for permission, but the switch is already on.**
macOS can keep an outdated entry after an update. Reset it and grant again:

```sh
tccutil reset Accessibility com.destucr.Keypause
tccutil reset ListenEvent   com.destucr.Keypause
```

Then reopen Keypause and click **Grant Access…**.

**"Keypause can't be opened."**
Right-click the app → **Open**, or run `xattr -dr com.apple.quarantine /Applications/Keypause.app`.

**Quit it from Terminal.** `pkill -x Keypause`

**Remove everything.**
```sh
brew uninstall --cask --zap keypause
tccutil reset All com.destucr.Keypause
```

The power / Touch ID button can't be blocked by software.
