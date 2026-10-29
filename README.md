# Ring Desktop Feed

A macOS menu bar app for watching your Ring cameras live, with a widget on the way.

> **Unofficial.** This uses Ring's unofficial API through [`ring-client-api`](https://github.com/dgreif/ring). It isn't affiliated with, endorsed by or supported by Ring or Amazon, and it may break whenever Ring changes its API.

Status: **tracer bullet**. You can sign in and watch one camera at a time in the menu bar popover. The widget, motion snapshots, the floating player and settings come next. See [docs/DESIGN.md](docs/DESIGN.md).

## How it works

A small TypeScript helper (bundled with its own Node runtime) signs in to Ring and serves a local web player on `127.0.0.1`. The player's WebRTC offer goes to Ring through the helper, so video streams straight from Ring into the app with no re-encoding.

## Building

You need macOS 26+, Xcode, and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

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

## License

MIT
