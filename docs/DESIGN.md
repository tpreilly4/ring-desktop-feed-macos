# Ring Desktop Feed: design

A macOS 26+ menu bar app with a floating mini-player, for watching Ring cameras live from a Mac. This is a personal, open-source project with no prebuilt releases. Bundle ID: `com.tompreilly.ringdesktopfeed`.

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
│  helper/ (TypeScript, bundled Node)                   │
│   ├─ ring-client-api (auth, devices, push events)     │
│   ├─ live view signaling: player offer ⇄ Ring answer │
│   └─ HTTP + WebSocket on 127.0.0.1:<random>, token    │
└───────────────────────────────────────────────────────┘
```

- **Helper:** TypeScript on `ring-client-api`. Node is bundled into the app. The build script downloads it at a pinned version, and it's never committed.
- **App ↔ helper:** HTTP and WebSocket bound to 127.0.0.1 on a random port, with a token that changes every launch, passed on startup.
- **Live video:** The WKWebView player creates the WebRTC offer, and the helper passes it to Ring's live view endpoint (`createSimpleWebRtcSession`). Media then flows directly from Ring to the player, with no relay hop and no re-encoding. That's simpler than the planned media relay and has even less delay.
- **Project:** Generated with XcodeGen (`project.yml`). The Apple team ID lives in a git-ignored `Local.xcconfig`. Signing with a real team keeps the signature stable, so macOS doesn't ask for Keychain access after every rebuild.

## Auth

A one-time sign-in screen in the app handles email, password and 2FA. The refresh token, which rotates, is kept in the Keychain and renewed automatically. The password is never stored.

## Live view

- Streams only while the popover or mini-player is open, and only one camera at a time.
- Ring cuts streams off after about 10 minutes. The Floodlight then reconnects silently, and the doorbell shows a "Resume live" button.
- Audio starts muted with an unmute toggle. There's no two-way talk.
- The popover and the mini-player are one panel (our own `NSStatusItem` + `NSPanel`, not `MenuBarExtra`), so switching between them never restarts the stream.
- **Attached:** the panel hangs under the 🏠 icon, extends right toward the top-right corner, and closes when you click elsewhere.
- **Pop out:** the panel drops slightly, shakes once and becomes the mini-player in place. It's resizable at 16:9 above its control bar, stays on top (toggleable, and follows you across Spaces) and can be dragged by its bar.
- **Back to menu bar:** the button (or clicking 🏠) flies the panel back under the icon with a small overshoot "snap".
- The mini-player always pops out from the popover's position, so it no longer remembers its own position.

## Events and menu bar icon

- A doorbell press shows a macOS notification that opens live view. Motion doesn't notify.
- Push notifications go through `@eneris/push-receiver`. The helper pins 4.4.0 with an npm override, because 4.3.0 (the version `ring-client-api` asks for) misreads Ring's `crypto-key` header and fails to decrypt every push.
- The icon is a plain camera normally, shows a dot for 5 minutes after motion, switches to a doorbell symbol for 1 minute after a press, and shows a warning variant when it loses contact with Ring.

## Failure handling

- If the helper crashes, the app restarts it with growing delays. After 5 failed starts in a row it stops and shows the problem with a "Try Again" button.
- The helper checks its connection to Ring every 2 minutes. `ring-client-api` retries network failures forever, so requests are timed out on our side (the check after 20 seconds, the app's API calls after 30, and starting live view after 30).
- If Ring can't be reached, the menu bar icon and the panel's bar show a warning that clears by itself once Ring is back.
- If Ring refuses the token, a notification appears and the sign-in window opens. The library reports any failed token refresh this way, including an error on Ring's side, so the Keychain token isn't deleted: the next launch tries it again, and a new sign-in replaces it. Only "Sign Out" deletes it.
- An offline camera says so in place of the video.
- Logs go to `~/Library/Logs/RingDesktopFeed/`.

## Settings

A separate window, opened from the panel's ⋯ menu: launch at login (off by default, via `SMAppService`), keep the mini-player on top, sign out, and a shortcut to the logs.

## Repo hygiene

- MIT license.
- No binaries, tokens or team IDs are committed.
- The README says this uses Ring's unofficial API and isn't affiliated with Ring.
- No prebuilt downloads.

## Build order (tracer bullet first)

1. **Tracer bullet (code we keep):** The real helper signs in and relays the Floodlight's live stream into a bare-bones menu bar app with the web player.
   **Prototype (throwaway):** Check whether the battery doorbell can live stream while it's recording a motion event.
2. The popover and the floating mini-player.
3. Motion and doorbell events. (A snapshot widget was built here and then dropped: the menu bar app is enough on its own.)
4. Settings, error states and the README.

## Testing

The helper's logic gets automated tests against a fake Ring layer. That covers sign-in, live view requests and the connection rules (expiry versus lost contact). The UI and streaming are checked by hand on the real cameras.

## v2 candidates

Event recording playback, streaming automatically on motion or a press, and two-way talk.
