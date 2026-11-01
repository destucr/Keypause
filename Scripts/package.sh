#!/bin/bash
# Builds the app and packages dist/Keypause.zip and dist/Keypause.dmg.
set -euo pipefail
cd "$(dirname "$0")/.."
./Scripts/build.sh

rm -f dist/Keypause.zip dist/Keypause.dmg
ditto -c -k --keepParent dist/Keypause.app dist/Keypause.zip

STAGE="$(mktemp -d)"
cp -R dist/Keypause.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Keypause" -srcfolder "$STAGE" -ov -format UDZO dist/Keypause.dmg >/dev/null
rm -rf "$STAGE"
shasum -a 256 dist/Keypause.zip dist/Keypause.dmg
