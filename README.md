# Ring Desktop Feed

A macOS menu bar app for watching your Ring cameras.

> **Unofficial.** This uses Ring's unofficial API through [`ring-client-api`](https://github.com/dgreif/ring). It isn't affiliated with, endorsed by or supported by Ring or Amazon, and it may break whenever Ring changes its API.

## What it does

- Watch one camera or both side by side from the menu bar, or pop the view out into a floating mini-player. Video comes straight from Ring, with no re-encoding.
- See motion at a glance: the menu bar icon gets a red dot for 5 minutes.
- Get a notification when the doorbell rings, and click it to watch live.
- Optionally launch at login, from Settings (the ⋯ menu in the panel).

Design notes are in [docs/DESIGN.md](docs/DESIGN.md).

## How it works

A small TypeScript helper (bundled with its own Node runtime) signs in to Ring and serves a local web player on `127.0.0.1`. The player's WebRTC offer goes to Ring through the helper, so video streams straight from Ring into the app with no re-encoding.

## Building

You need macOS 26+, Xcode signed in with an Apple Developer account, and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`). Put your team ID in `Local.xcconfig` (created by bootstrap): a stable signature stops macOS asking for Keychain access after every rebuild.

```bash
scripts/bootstrap.sh   # fetches pinned Node, builds the helper, generates the Xcode project
scripts/build.sh       # or open RingDesktopFeed.xcodeproj and run
```

Run `scripts/bootstrap.sh` again after pulling changes to the helper.

There are no prebuilt downloads. Build it yourself.

## Working on the helper alone

```bash
cd helper
npm run sign-in   # email, password, 2FA → saves helper/dev.token (git-ignored)
npm run dev       # serves on 127.0.0.1:8787, token "dev"
npm test
```

Then open `http://127.0.0.1:8787/player#token=dev` in Safari and pick a camera.

## Privacy

- Your Ring password is only held in memory during sign-in.
- The refresh token is stored in your macOS Keychain (or `helper/dev.token` in dev mode).
- The helper only listens on loopback and requires a random per-launch token.
- Logs go to `~/Library/Logs/RingDesktopFeed/`.

## Troubleshooting

- **The icon shows an orange ⚠︎:** the app can't reach Ring. It keeps checking and clears the warning by itself once Ring is back.
- **The sign-in window opens by itself:** Ring ended your session. Motion and doorbell alerts are paused until you sign in again.
- **macOS keeps asking for Keychain access:** the app is probably signed without a team. Check `DEVELOPMENT_TEAM` in `Local.xcconfig` and rebuild.
- **No alerts:** the app has to be running to get them. Check `helper.log` in the logs folder for lines like `motion on Front Door`.

## License

MIT
