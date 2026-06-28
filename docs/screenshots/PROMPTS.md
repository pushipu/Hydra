# Промпты для генерации скриншотов (GLM)

Цель — 6 PNG в `docs/screenshots/`, на которые ссылаются README. UI на английском
(дефолтный язык приложения). Стиль везде одинаковый — см. преамбулу.

**Общая преамбула (приклеивать к каждому промту):**

> Realistic macOS Sequoia UI screenshot, native SwiftUI/AppKit look. System blue
> accent color #0A84FF. SF Pro font. Translucent vibrancy/material backgrounds,
> rounded corners (~12–16px), thin hairline separators, soft shadows. Numbers in
> tabular figures. Crisp high-DPI (2x). No browser chrome, no cursor. Clean,
> Apple-quality, uncluttered. Filenames are realistic (.dmg, .zip, .mp4, .iso).

---

## 1. `popover.png` — поповер в строке меню
Aspect ~380×432 (portrait card).

> A compact macOS menu-bar popover, 380×432px, translucent light material. Header
> row: small rounded-square blue app icon with a white download arrow, title
> "Hydra" in semibold, on the right a tiny blue dot + speed "12.4 MB/s", and three
> faint toolbar icons (pin, drop-arrow, gear). Summary line: "2 active · 1 queued"
> left, "3 completed" right. A vertical list of download rows; each row: a small
> rounded file-type badge (DMG/ZIP/MP4) in soft blue, filename in medium weight,
> a subtitle host like "releases.example.com", a circular pause button on the
> right. Active rows show "1.50 GB of 2.41 GB   62%" and a defrag grid of tiny
> square blocks (some solid blue = done, some pale blue = downloading, some grey =
> pending) plus "318 / 512 blocks · 8 threads · 4m 12s left". Footer with a
> "Pause all" link and a blue "+ Add" pill button.

## 2. `window.png` — окно загрузок
Aspect ~900×580 (landscape).

> A macOS app window, 900×580px, NavigationSplitView layout. Left sidebar with
> sections "Library" (All, Active, Completed, Errors) and "Sources" (domains),
> monochrome SF symbols, one row selected with blue highlight. Main area: a native
> macOS table of downloads with columns Name, Status, Size; rows mixing states —
> some downloading with inline progress, some "Completed" with green check, one
> red "Error". Top toolbar with a title "Downloads", a search field, and a sort
> control. Bottom status bar: "24 downloads · 2 active · 18.0 MB/s". Light theme,
> native vibrancy.

## 3. `settings.png` — настройки
Aspect ~680×460.

> A macOS Settings window, 680×460px, System-Settings-style. Left sidebar list with
> monochrome SF symbol rows: Downloads (down-arrow), Capture (link), On finish
> (check), Folders (folder), System (gear) — "System" selected with blue
> highlight. Right pane: a grouped form with small-caps section header "GENERAL"
> over a white rounded card containing a "Language" popup showing "English", a
> "Launch at login" toggle (on, blue), and a "Floating link-drop window" toggle.
> Clean, native, light theme.

## 4. `drop.png` — плавающее окно-приёмник (круг-ловушка)
Aspect square ~300×300, transparent or soft desktop blur behind.

> A small floating circular drop target on a blurred macOS desktop, ~150px circle.
> A frosted translucent disc with a solid 2px blue ring (#0A84FF) around the edge,
> a smaller dashed blue ring inside, six small blue dots evenly spaced on the
> dashed ring, and a central soft-blue filled circle with a bold blue downward
> arrow. Below/over the lower edge a small frosted pill tooltip reads "Drop a link
> — or an address from the browser". Minimal, elegant, lots of transparency.

## 5. `extension.png` — попап браузерного расширения
Aspect ~360×420 (narrow popup).

> A browser extension popup, ~360px wide, light theme. Header: small blue rounded
> square logo + "Hydra" + a green status dot with "Connected" on the right. A list
> of 2–3 download rows: file-type badge, filename, "host · 8 threads", and a right
> status like "62%" or "Paused", each with a thin progress bar. Footer line:
> "Auto-capture on" with a "Settings…" link. Clean WebExtension styling matching
> the macOS app.

## 6. `notification.png` — нативное уведомление
Aspect ~360×100 (banner).

> A native macOS notification banner, top-right style, translucent. Left: the
> Hydra app icon (blue rounded square with white download arrow). Title "Download
> complete", body "macOS Sequoia installer.dmg · 2.41 GB", with action buttons
> "Show in Finder". System notification look, rounded corners, soft shadow.

---

Сохрани результаты строго под этими именами в `docs/screenshots/`:
`popover.png`, `window.png`, `settings.png`, `drop.png`, `extension.png`,
`notification.png`.
