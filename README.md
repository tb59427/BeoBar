# BeoBar

A macOS menu bar app for [BeoControl](https://github.com/wolfgangschneider/BeoControl)
and a **BeoLink PC2**: it puts a Beo4-style remote for your MasterLink system
into the menu bar.

- **Native remote:** source keys, digits, colour keys, arrows/GO, volume and
  standby, with a display showing source, state and volume live.
- **Configurable source keys:** nine keys you can label and assign as you
  like (N.MUSIC, CD, the Mac's own input, …), e.g. "RADIO 3".
- **Calls:** when a call starts on the Mac (a microphone records and the
  output that feeds the PC2 plays), the PC2 switches to the Mac's input. The
  MasterLink source is released, so a stream pauses. Afterwards it switches
  back and the music continues. Works with Teams, Zoom, FaceTime and others.
  A headset call leaves the music alone.
- **Media keys:** the keyboard's volume and mute keys control the PC2.
  Play/pause and next/previous go to MasterLink while it plays, and to the
  Mac app that's playing otherwise.
- **Settings window:** source keys, PC2 sound (volume, bass, treble,
  balance, loudness), call switching, media keys, start at login.

BeoBar starts the BeoControl server itself and talks to it over its HTTP API.
BeoControl's own web UI stays available from the menu, e.g. for connecting
the PC2.

## Requirements

- macOS 14 or later
- A BeoLink PC2 on USB, connected to your MasterLink system
- BeoControl **with its HTTP API**. Until those changes are merged upstream
  ([#1](https://github.com/wolfgangschneider/BeoControl/pull/1),
  [#2](https://github.com/wolfgangschneider/BeoControl/pull/2),
  [#4](https://github.com/wolfgangschneider/BeoControl/pull/4),
  [#5](https://github.com/wolfgangschneider/BeoControl/pull/5),
  [#6](https://github.com/wolfgangschneider/BeoControl/pull/6)), build it
  from the `beobar` branch of
  [tb59427/BeoControl](https://github.com/tb59427/BeoControl/tree/beobar),
  which has all of them.
- Xcode or the Command Line Tools (`xcode-select --install`), for `swiftc`

## Install

**1. BeoControl server** (needs the [.NET 10 SDK](https://dotnet.microsoft.com/download)
and libusb, `brew install libusb`):

```sh
git clone -b beobar https://github.com/tb59427/BeoControl.git
cd BeoControl
dotnet publish UI/BeoControlBlazor/BeoControlBlazorServer/BeoControlBlazor.csproj \
  -c Release -f net10.0 -o ~/BeoControlServer
```

BeoBar expects the server in `~/BeoControlServer`.

**2. BeoBar:**

```sh
git clone https://github.com/tb59427/BeoBar.git
cd BeoBar
./build.sh
ditto ~/Library/Caches/BeoBar-build/BeoBar.app /Applications/BeoBar.app
open /Applications/BeoBar.app
```

**3. Connect the PC2:** right-click the menu bar icon → *Web-Oberfläche im
Browser* → set up the PC2 connection in BeoControl once.

**4. Media keys:** allow BeoBar under *System Settings → Privacy & Security
→ Accessibility*. macOS asks on first start.

### Optional: your own menu bar icon

BeoBar shows a speaker symbol. To use your own, put a single-colour image at
`~/Library/Application Support/BeoBar/menubar-icon.svg` (or `.pdf` / `.png`),
drawn in black on transparent; macOS tints it for light and dark menu bars.
It's read at start.

### Optional: keep the Accessibility permission across rebuilds

macOS ties the permission to the app's signature. `build.sh` signs ad hoc
unless a certificate named **BeoBar Local Signing** is in your keychain. With
one, the permission survives rebuilds. To create it: *Keychain Access →
Certificate Assistant → Create a Certificate*, name `BeoBar Local Signing`,
identity type *Self-Signed Root*, certificate type *Code Signing*.

## Settings

Right-click the menu bar icon → *Einstellungen …*, or the gear in the remote's
display:

| Tab | What |
|---|---|
| Quellentasten | Label, BeoControl command (`atape2` = N.MUSIC, `phono` = N.RADIO, `cd`, `radio`, `pc` = the Mac, …) and optional number per key |
| PC2-Klang | Volume, bass, treble, balance, loudness |
| Anruf & Tasten | Call switching on/off, which output feeds the PC2, delays; media keys on/off |
| Allgemein | Start at login; links to BeoControl's web UI and setup |

The UI is in German for now.

## Troubleshooting

BeoBar starts the BeoControl server with a PC2 debug log at
`~/Library/Logs/BeoBar/pc2-debug.log` (USB traffic, mixer state, Masterlink
telegrams; rotates at ~5 MB to `pc2-debug.log.1`). Needs a BeoControl build
with that option (`BEOCONTROL_PC2_LOG`; on the `beobar` branch). The server's
own output goes to `~/BeoControlServer/server.log`.

## How it works

| File | Purpose |
|---|---|
| `main.swift` | App, menu bar item, starts the BeoControl server |
| `BeoClient.swift` | BeoControl HTTP API: `POST /api/command/{cmd}`, live status from `GET /api/events` |
| `RemoteView.swift` | The remote (SwiftUI) |
| `SettingsView.swift`, `Settings.swift` | Settings window and stored settings |
| `Audio.swift` | Call detection (CoreAudio: is a microphone / the PC2's output in use?) and media keys (event tap) |

## Credits

- [BeoControl](https://github.com/wolfgangschneider/BeoControl) by Wolfgang
  Schneider does the actual work with the PC2.
- Bang & Olufsen, BeoLink, Beo4 and MasterLink are trademarks of Bang &
  Olufsen. This project is not affiliated with Bang & Olufsen.

## License

[MIT](LICENSE)
