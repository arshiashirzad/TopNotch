# TopNotch

A geeky Dynamic Island for the MacBook notch. Hover the notch and it springs open into a black HUD panel.

- **AI sessions:** live Claude Code and Codex sessions, with their project, model and current activity. Claude Code prompts can be approved or answered from the notch; Claude usage limits and activity are also available.
- **Music:** Apple Music and Spotify controls, album art and seeking, plus time-synced lyrics from [LRCLIB](https://lrclib.net). The line being sung right now can show big under the notch.
- **Drop shelf:** a liquid tab on the right screen edge, above the Dock. Drag files, images, links or text near it and it swells into a drop target; drag them back out into any app, or share, copy and reveal them. New screenshots pop out of it with a thumbnail to drag into a chat, copy or delete.
- **Clipboard:** history of what you copy. Password-manager copies are skipped, and nothing is stored on disk.
- **Notes:** a scratchpad that saves automatically.
- **Calendar:** the Persian (Solar Hijri) calendar. It shows today in Persian digits next to the clock and a Saturday-first month grid with the Gregorian date under each day. Fridays and the fixed-date official holidays are marked, and it counts down to Nowruz.
- **GitHub:** a last-year contribution calendar for a GitHub username, showing public activity without signing in.

- **System:** live CPU, memory and network with two-minute sparklines, battery (time left, cycles, health, charger watts), free disk, thermal pressure, uptime and the top processes. The notch flashes when you plug in or unplug, when the battery drops to 20/10/5%, and when the Mac runs hot; a pegged CPU shows on the closed notch.
- **Messages:** WhatsApp, Telegram and Slack notifications show up instantly as a card on the notch, with each app's unread badge on the closed notch.

Native SwiftUI. No dependencies, no Xcode project.

## Download

**[⬇ TopNotch.dmg (latest)](https://github.com/arshiashirzad/TopNotch/releases/latest/download/TopNotch.dmg)**: macOS 14+ on Apple Silicon.

Open the DMG and drag **TopNotch** onto **Applications**. The app isn't notarized, so the first launch is blocked: go to **System Settings → Privacy & Security → Open Anyway** (or run `xattr -dr com.apple.quarantine /Applications/TopNotch.app`).

## Build

Requires macOS 14+ on Apple Silicon and the Xcode Command Line Tools.

```bash
./build.sh
```

This builds a release binary, wraps it in `/Applications/TopNotch.app`, signs it and launches it.

## Permissions

| Feature | Permission |
|---|---|
| Music control | Automation → Music / Spotify (asked on first use) |
| Jump to Claude session | Automation → the session's terminal app (asked on first use) |
| Messages (history) | Full Disk Access (reads Notification Center's database) |
| Messages (instant) | Accessibility (reads the banner while it's on screen) |

Builds with ad-hoc signatures lose these permissions on every rebuild. To keep them, create a self-signed code-signing certificate named **TopNotch Dev** in your login keychain; `build.sh` uses it automatically when it's present.

## Release

```bash
./release.sh 1.1.0 "what changed"
```

This builds the app, packages a styled drag-to-install DMG (`dmg.sh`), tags `v1.1.0` and publishes a GitHub release with the DMG attached.

## Self-test

```bash
/Applications/TopNotch.app/Contents/MacOS/TopNotch --selftest
```

## License

MIT. See [LICENSE](LICENSE).
