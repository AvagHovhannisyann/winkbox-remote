#!/bin/bash
# Builds WinkBox Remote into WinkRemote.ipa. Normally this runs on GitHub's Mac machines, which have Xcode (see
# .github/workflows/build.yml), and the finished WinkRemote.ipa is published as the "latest" release. Without Xcode
# it can also build here, with the Mac's own Swift and the iPhone SDK pulled out of an Xcode .xip by
# Tools/extract-sdk.py into sdk/. Then `./install.sh` signs it with your Apple ID and puts it on the iPhone.
set -euo pipefail
cd "$(dirname "$0")"

if SDK=$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null); then
  SWIFTC=(xcrun --sdk iphoneos swiftc)
  SDK_VERSION=$(xcrun --sdk iphoneos --show-sdk-version)
else
  DEVROOT=sdk
  SDK=$DEVROOT/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk
  XTC=$DEVROOT/Toolchains/XcodeDefault.xctoolchain/usr/lib
  CLT=/Library/Developer/CommandLineTools/usr/lib
  [ -d "$SDK" ] || { echo "No Xcode and no iPhone SDK in $SDK (Tools/extract-sdk.py Xcode_14.2.xip sdk)."; exit 1; }
  # Swift's resource folder for iPhone builds: the Mac's shims plus Xcode's iPhone runtime pieces and clang folder.
  RES=.build/swift-resource
  if [ ! -d "$RES/iphoneos" ]; then
    mkdir -p "$RES"
    ln -sfn "$PWD/$XTC/swift/iphoneos" "$RES/iphoneos"
    ln -sfn "$CLT/swift/shims" "$RES/shims"
    ln -sfn "$PWD/$(ls -d $XTC/clang/* | head -1)" "$RES/clang"
  fi
  SWIFTC=(/Library/Developer/CommandLineTools/usr/bin/swiftc -resource-dir "$RES")
  SDK_VERSION=$(/usr/libexec/PlistBuddy -c "Print :Version" "$SDK/SDKSettings.plist")
fi

OUT=.build/ios
APP=$OUT/Payload/WinkRemote.app
rm -rf "$OUT"
mkdir -p "$APP"

echo "Compiling against the iOS $SDK_VERSION SDK…"
"${SWIFTC[@]}" \
  -target arm64-apple-ios16.0 -sdk "$SDK" -swift-version 5 \
  -module-name WinkRemote -parse-as-library -O -wmo \
  -module-cache-path .build/ModuleCache \
  App/Core/*.swift App/UI/*.swift App/Main/*.swift \
  -o "$APP/WinkRemote"

cp App/Icon/AppIcon??x??@?x.png "$APP/"
cp App/Info.plist "$APP/Info.plist"
plutil -replace DTPlatformVersion -string "$SDK_VERSION" "$APP/Info.plist"
plutil -replace DTSDKName -string "iphoneos$SDK_VERSION" "$APP/Info.plist"
printf 'APPL????' > "$APP/PkgInfo"

rm -f WinkRemote.ipa
(cd "$OUT" && zip -qry ../../WinkRemote.ipa Payload)
echo "Built $(pwd)/WinkRemote.ipa ($(du -h WinkRemote.ipa | cut -f1))"
