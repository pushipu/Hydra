<div align="center">

<img src="docs/screenshots/icon.png" width="128" alt="Hydra"/>

# Hydra

**English** · [Русский](README.ru.md) · [中文](README.zh.md)

[![Release](https://img.shields.io/github/v/release/pushipu/Hydra?sort=semver)](https://github.com/pushipu/Hydra/releases)
[![Downloads](https://img.shields.io/github/downloads/pushipu/Hydra/total)](https://github.com/pushipu/Hydra/releases)
[![License: MIT](https://img.shields.io/github/license/pushipu/Hydra)](LICENSE)
![Platform: macOS 13+](https://img.shields.io/badge/platform-macOS%2013%2B-blue)
[![Stars](https://img.shields.io/github/stars/pushipu/Hydra?style=social)](https://github.com/pushipu/Hydra/stargazers)

**Multithreaded download manager for macOS with browser-session passthrough.**

Downloads files in several parallel streams (HTTP Range) and replays your
authenticated browser session across every stream — so it downloads faster, and
downloads what only you can access. Lives in the menu bar, pairs with the browser
on its own, no copying ids or editing configs.

macOS 13+ · Swift · native SwiftUI/AppKit

</div>

---

## Features

- **Multithreaded downloads** — the file is split into blocks, a connection pool
  pulls them in parallel (HTTP Range). Speed, ETA and thread count in real time.
- **Session passthrough** — the extension captures `Cookie`, `User-Agent`,
  `Referer` for the link and replays them in **every** stream. Grabs what sits
  behind a login.
- **Pause / resume that survives a restart** — the done-blocks bitmap is written
  to disk; quit with an unfinished download → reopen → it continues from the same spot.
- **Defrag block grid** — the whole file at a glance: done, downloading now,
  ahead, and "X / Y blocks".
- **Queue** — concurrent-download limit, the rest wait; priority, pause-all.
- **History** — completed downloads persist across launches, with search and "Show in Finder".
- **Browser capture** — auto-capture by rules (size, file types) or
  "Download with Hydra" in the context menu.
- **Floating drop window** — always on top; drag a link from anywhere onto it.
- **Native notifications** — completion, error (with "Retry"), sign-in required.
- **Update check** — notifies on launch when a newer release is on GitHub; manual check in Settings/menu.
- **Native macOS look** — system accent, materials/vibrancy, SF, dark/light theme.
- **Localized** — English, Russian, Chinese; switch in Settings → System → Language.

## Why Hydra?

A free, open-source download accelerator for macOS — a native alternative to IDM,
Folx and JDownloader, without the price tag or the Java runtime.

| | Browser built-in | Typical download managers | **Hydra** |
|---|:---:|:---:|:---:|
| Multithreaded (HTTP Range) | ❌ | ✅ | ✅ |
| Replays your logged-in session | ❌ | ⚠️ partial | ✅ cookies + UA + referer |
| Downloads files behind a login | ❌ | ⚠️ | ✅ |
| Pause / resume across restart | ⚠️ | ✅ | ✅ block-level |
| Native menu-bar app | — | varies | ✅ SwiftUI / AppKit |
| Open source, free | — | usually paid | ✅ MIT |

## Screenshots

| Menu-bar popover | Download details (multithreaded) |
|---|---|
| ![popover](docs/screenshots/popover.png) | ![detail](docs/screenshots/detail.png) |

| Downloads window | Per-download actions |
|---|---|
| ![window](docs/screenshots/window.png) | ![menu](docs/screenshots/menu.png) |

| Settings | Floating drop circle |
|---|---|
| ![settings](docs/screenshots/settings.png) | ![drop](docs/screenshots/drop.png) |

## How it works

```
Browser ──(link capture + session)──▶ Extension
                                          │ native messaging
                                          ▼
                                    hydra-host  ──(Unix socket /tmp/hydra.sock)──▶ Hydra.app
                                     (fallback: downloads itself if app isn't running)   │
                                                                                          ▼
                                                                                   DownloadCore
                                                                          probe → blocks → N streams → assemble
```

- **Automatic pairing, no user steps.** The Chrome id is pinned by a key in the
  manifest (deterministic `hfdmeoleepighofjiookfjcjekoopaim`), and Hydra.app
  registers the native-messaging host into every browser on launch. No copying
  ids, no `install.sh`.
- **Two engine cores:** `ResumableDownload` (block-based, pause/resume — for the
  app) and `Downloader` (contiguous chunks, fire-and-forget — for the CLI and the
  host fallback). Both covered by byte-exact tests.

## Install

### Homebrew (easiest)

```bash
brew install --cask --no-quarantine pushipu/tap/hydra
```

`--no-quarantine` is needed while the app is ad-hoc signed (not notarized yet); it
lets the app open without Gatekeeper warnings. Then continue from step 2 below.

### Manual

1. Download the latest `Hydra-*-macos.zip` from [Releases](../../releases), unzip, move
   `Hydra.app` to `/Applications`, launch once — it registers the host into every
   installed browser.
2. Install the extension for your browser — the app bundles both. Open
   **Settings → Capture → Install extension** (or the menu-bar menu → "Install
   extension…"); Finder opens the bundled `chrome/` folder and `hydra-firefox.xpi`:
   - **Chrome / Brave / Edge:** `chrome://extensions` → Developer mode →
     "Load unpacked" → the `chrome/` folder.
   - **Firefox 140+:** `about:debugging` → "Load Temporary Add-on" →
     `hydra-firefox.xpi`. Permanent installation requires an AMO-signed XPI.
   - **Safari:** manual via Xcode for now ([docs/SAFARI_SETUP.md](docs/SAFARI_SETUP.md)).
3. Done — cookies/session and multithreading work right away.

> Distributing to other machines requires notarization (Developer ID). Locally an
> ad-hoc signature is enough — `Hydra.app` launches on your own machine without warnings.

## Build from source

Requires the Xcode/Swift toolchain and `rsvg` (for icons: `brew install librsvg`).

```bash
./build-all.sh
```

Drops into `dist/`: `Hydra.app` (host embedded, self-registering), `chrome/`
(unpacked extension), `hydra-chrome.zip`, `hydra-chrome-store.zip` (without the
store-forbidden manifest key), and `hydra-firefox.xpi`.

Version is single-sourced from the `VERSION` file: the build stamps it into the
app's `Info.plist` and every extension manifest (`CFBundleVersion` = git commit
count). Bump `VERSION`, rebuild — app and extensions stay in lockstep.

```bash
cd core && swift test          # engine tests (byte-exact, resume, filename sanitizing)
.build/release/hydractl URL --out ~/Downloads --connections 8   # CLI
```

## Layout

```
core/Sources/
  DownloadCore/   engine: probe, blocks, resume, session, rate limit, history
  HydraApp/       SwiftUI/AppKit: popover, window, settings, drop zone, notifications
  hydractl/       CLI
  hydra-host/     native messaging host (delegates to app, fallback — downloads itself)
extension/        WebExtension (Chrome/Firefox), pinned key, pairing-status popup
app/build.sh      builds Hydra.app (signing, host embedding, icon)
build-all.sh      ⭐ everything at once → dist/
docs/             ARCHITECTURE.md, SAFARI_SETUP.md, USAGE.md, screenshots/
```

## Browser extension

A thin layer: captures the session with explicit consent, intercepts links, shows
the pairing status and a short local transfer log. Download management lives in the app.
Capture settings (auto-capture, min size, file types, threads) have a single
source of truth in the app; the extension reads them through the host.

## FAQ

**Is Hydra a free IDM / Folx alternative for macOS?**
Yes — open-source (MIT), multithreaded, with browser-session passthrough, native to macOS.

**How does it download files that are behind a login?**
The browser extension captures your `Cookie`, `User-Agent` and `Referer` for the link
and replays them on every parallel connection, so the server sees your authenticated session.

**Which browsers are supported?**
Chrome, Brave, Edge and Firefox via extensions. Safari needs a manual setup for now.

**Is it safe? What does the extension read?**
It reads cookies only to pass your existing session to Hydra on the same Mac. There is
no telemetry or developer-operated data server. See the [Privacy Policy](PRIVACY.md).

**Does pause/resume survive a restart?**
Yes. The done-blocks bitmap is persisted to disk, so you can quit mid-download and continue later.

**macOS says the app "cannot be opened" — why?**
Current GitHub releases are signed with Developer ID and notarized by Apple. Make sure
you downloaded an unmodified release from this repository.

## License

[MIT](LICENSE) © pushipu
