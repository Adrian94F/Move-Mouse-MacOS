#!/bin/bash
# Builds a universal Release app and packages it into a drag-to-Applications DMG with a custom volume icon.
set -euo pipefail
cd "$(dirname "$0")/.."
xcodebuild -project MoveMouse.xcodeproj -scheme MoveMouse -configuration Release \
  -derivedDataPath build ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO build | tail -1
APP=build/Build/Products/Release/MoveMouse.app
ICONS=MoveMouse/Assets.xcassets/AppIcon.appiconset
STAGE=build/dmg
RW=build/MoveMouse-rw.dmg
rm -rf "$STAGE" build/MoveMouse.iconset "$RW" build/MoveMouse.dmg && mkdir -p "$STAGE" build/MoveMouse.iconset
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

I=build/MoveMouse.iconset
cp $ICONS/icon_16.png   $I/icon_16x16.png;      cp $ICONS/icon_32.png   $I/icon_16x16@2x.png
cp $ICONS/icon_32.png   $I/icon_32x32.png;      cp $ICONS/icon_64.png   $I/icon_32x32@2x.png
cp $ICONS/icon_128.png  $I/icon_128x128.png;    cp $ICONS/icon_256.png  $I/icon_128x128@2x.png
cp $ICONS/icon_256.png  $I/icon_256x256.png;    cp $ICONS/icon_512.png  $I/icon_256x256@2x.png
cp $ICONS/icon_512.png  $I/icon_512x512.png;    cp $ICONS/icon_1024.png $I/icon_512x512@2x.png
iconutil -c icns $I -o "$STAGE/.VolumeIcon.icns"

hdiutil create -volname MoveMouse -srcfolder "$STAGE" -ov -format UDRW "$RW" >/dev/null
MNT=$(hdiutil attach "$RW" -nobrowse -noverify | awk -F'\t' '/\/Volumes\//{print $NF}')
SetFile -a C "$MNT"
hdiutil detach "$MNT" >/dev/null
hdiutil convert "$RW" -format UDZO -o build/MoveMouse.dmg >/dev/null
rm -f "$RW"
echo "Created build/MoveMouse.dmg"
