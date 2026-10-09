#!/bin/bash
# Baut BeoBar.app aus BeoBar.swift
set -e
cd "$(dirname "$0")"

APP=BeoBar.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

swiftc -O -o "$APP/Contents/MacOS/BeoBar" BeoBar.swift \
    -framework Cocoa -framework WebKit

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>      <string>BeoBar</string>
    <key>CFBundleIdentifier</key>      <string>de.tb.beobar</string>
    <key>CFBundleName</key>            <string>BeoBar</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>1.0</string>
    <key>LSMinimumSystemVersion</key>  <string>12.0</string>
    <key>LSUIElement</key>             <true/>
    <key>NSHighResolutionCapable</key> <true/>
</dict>
</plist>
EOF

# Mit festem Zertifikat signieren, damit macOS-Freigaben (Bedienungshilfen) einen
# Neubau überstehen; ohne Zertifikat ad hoc (Freigabe muss dann neu erteilt werden).
SIGN_ID="BeoBar Local Signing"
if security find-identity -p codesigning | grep -q "\"$SIGN_ID\""; then
    codesign --force --sign "$SIGN_ID" "$APP"
else
    echo "Hinweis: Zertifikat '$SIGN_ID' fehlt – signiere ad hoc"
    codesign --force --sign - "$APP"
fi
echo "Fertig: $(pwd)/$APP"
