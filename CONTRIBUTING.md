# Contributing to Hydra

Thanks for your interest! Hydra is a macOS download manager (SwiftPM) plus browser
extensions. Issues and PRs are welcome.

## Build & test

```bash
./build-all.sh                 # app + extensions → dist/
swift test --package-path core # engine tests (byte-exact, resume, session replay)
```

Requirements: Xcode/Swift toolchain, `rsvg` for icons (`brew install librsvg`).

## Layout

- `core/Sources/DownloadCore` — engine (probe, blocks, resume, session, rate limit, history)
- `core/Sources/HydraApp` — SwiftUI/AppKit UI (popover, window, settings, drop zone)
- `core/Sources/hydra-host` — native-messaging host
- `extension/` — WebExtension (Chrome/Firefox)
- `VERSION` — single source of truth; the build stamps it into the app and extensions

## Guidelines

- Keep changes minimal and match the surrounding style — prefer the standard library
  and platform features over new dependencies.
- Add a test for non-trivial logic (`core/Tests/DownloadCoreTests`).
- Localized UI strings go through `L("…")` (key = Russian literal) with `en`/`zh`
  translations in `Localization.swift`.
- Run `swift test` before opening a PR.

## Reporting bugs

Open an issue with macOS version, steps to reproduce, the URL/site type (if relevant),
and any console output (`Console.app`, filter "Hydra").
