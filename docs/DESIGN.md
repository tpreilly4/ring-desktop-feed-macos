# Ring Desktop Feed: design

A macOS 26+ menu bar app with a floating mini-player and a WidgetKit widget, for watching Ring cameras live from a Mac. This is a personal, open-source project with no prebuilt releases. Bundle ID: `com.tompreilly.ringdesktopfeed`.

Target devices: a Floodlight Cam 1st gen (wired) and a Video Doorbell 2 (battery only), on a Ring Multi plan (which includes event recordings and thumbnails).

## Architecture

```
┌──────────────── Ring Desktop Feed.app ────────────────┐
│  SwiftUI menu bar app                                 │
│   ├─ popover / floating mini-player                   │
│   │    └─ WKWebView player  ◀── WebRTC straight from │
│   │                              Ring (no re-encode)  │
│   ├─ Keychain (refresh token)                         │
│   └─ launches + supervises ─┐                         │
│                             ▼                         │
│  helper/ (TypeScript, bundled Node + ffmpeg)          │
│   ├─ ring-client-api (auth, devices, push events)     │
│   ├─ live view signaling: player offer ⇄ Ring answer │
│   ├─ snapshot service ──▶ App Group container         │
│   └─ HTTP + WebSocket on 127.0.0.1:<random>, token    │
│                                                       │
│  Widget extension reads snapshots from App Group      │
└───────────────────────────────────────────────────────┘
```

- **Helper:** TypeScript on `ring-client-api`. Node and ffmpeg are bundled into the app. The build script downloads both at pinned versions, and neither is committed.
- **App ↔ helper:** HTTP and WebSocket bound to 127.0.0.1 on a random port, with a token that changes every launch, passed on startup.
- **Live video:** The WKWebView player creates the WebRTC offer, and the helper passes it to Ring's live view endpoint (`createSimpleWebRtcSession`). Media then flows directly from Ring to the player, with no relay hop and no re-encoding. That's simpler than the planned media relay and has even less delay. ffmpeg is only used to turn doorbell frames into JPEGs, so it won't be bundled until the snapshot work starts.
- **Project:** Generated with XcodeGen (`project.yml`). The Apple team ID lives in a git-ignored `Local.xcconfig`.

## Auth

A one-time sign-in screen in the app handles email, password and 2FA. The refresh token, which rotates, is kept in the Keychain and renewed automatically. The password is never stored.

## Live view

- Streams only while the popover or mini-player is open, and only one camera at a time.
- Ring cuts streams off after about 10 minutes. The Floodlight then reconnects silently, and the doorbell shows a "Resume live" button.
- Audio starts muted with an unmute toggle. There's no two-way talk.
- The mini-player is resizable, keeps the video's aspect ratio, stays on top (toggleable), remembers its position and size, and has a camera switcher.

## Widget

- A medium size shows both cameras, and a small size shows one chosen camera.
- Snapshots are labeled with their age, such as "Motion · 2 min ago" or "Snapshot · 12 min ago".
- On motion, the image updates within seconds while the app is running (macOS may throttle some reloads). Otherwise it refreshes every 10–15 minutes.
- Doorbell motion goes through three steps: "Motion now" appears first, then a frame grabbed by briefly waking the doorbell (a setting that can be turned off), then Ring's event thumbnail once the recording finishes.
- Clicking a camera opens the mini-player on that camera, live.

## Events and menu bar icon

- A doorbell press updates the widget and shows a macOS notification that opens live view. Motion doesn't notify.
- The icon is a plain camera normally, shows a dot for 5 minutes after motion, switches to a doorbell symbol for 1 minute after a press, and shows a warning variant when it loses contact with Ring.
- The app launches at login.

## Failure handling

- If the helper crashes, the app restarts it automatically.
- If the sign-in expires, a notification appears and the sign-in screen opens.
- If Ring can't be reached, the widget shows its last snapshot with a "stale" badge.
- Logs go to `~/Library/Logs/RingDesktopFeed/`.

## Settings

Doorbell wake on motion, launch at login, fallback snapshot interval, stay-on-top default, and sign out.

## Repo hygiene

- MIT license.
- No binaries, tokens or team IDs are committed.
- The README says this uses Ring's unofficial API and isn't affiliated with Ring.
- No prebuilt downloads, so ffmpeg is never redistributed.

## Build order (tracer bullet first)

1. **Tracer bullet (code we keep):** The real helper signs in and relays the Floodlight's live stream into a bare-bones menu bar app with the web player.
   **Prototype (throwaway):** Check whether the battery doorbell can live stream while it's recording a motion event.
2. The popover and the floating mini-player.
3. Motion and doorbell events, the snapshot service and the widget.
4. Settings, error states and the README.

## Testing

The helper's logic gets automated tests against a fake Ring layer. That covers handling events, choosing snapshots, refreshing tokens and the reconnect rules. The UI and streaming are checked by hand on the real cameras.

## Open risk

Whether a battery doorbell allows a live stream while it's already recording a motion event. If it doesn't, the doorbell's motion snapshot comes from Ring's event thumbnail only.

## v2 candidates

Event recording playback, streaming automatically on motion or a press, and two-way talk.
