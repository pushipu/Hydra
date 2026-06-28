# Hydra — многопоточный менеджер загрузок для macOS

## Компоненты

```
┌─────────────────────┐   native messaging    ┌──────────────────┐
│ Browser Extension   │◀────(stdin/stdout)────▶│  hydra-host      │
│ (Chrome/FF/Safari)  │   JSON, 4-byte len     │ (bridge binary)  │
│  - context menu     │                         └────────┬─────────┘
│  - auto-intercept   │                                  │ XPC / local socket
│  - options (rules)  │                                  ▼
│  - captures cookies │                         ┌──────────────────┐
│    + headers        │                         │  Hydra.app       │
└─────────────────────┘                         │ (SwiftUI + menu  │
                                                │  bar)            │
                                                │  ┌────────────┐  │
                                                │  │ DownloadCore│ │
                                                │  │  - probe    │  │
                                                │  │  - chunks   │  │
                                                │  │  - resume   │  │
                                                │  └────────────┘  │
                                                └──────────────────┘
```

### 1. Browser Extension (`extension/`)
Общий WebExtension-код (MV3) для Chrome и Firefox. Тот же код пакуется в
Safari Web Extension через Xcode (Phase 3).

Задачи расширения:
- **Контекстное меню** «Download with Hydra» на ссылках/медиа (по умолчанию).
- **Авто-перехват** через `chrome.downloads.onDeterminingFilename`: отменяет
  родную загрузку (`downloads.cancel` + `downloads.erase`) и отдаёт задачу
  Hydra — по правилам из настроек (все / по типу / по размеру / по домену).
- **Захват сессии**: на момент перехвата собирает `Cookie` (через `cookies`
  API для финального URL), `User-Agent`, `Referer`, и заголовки исходного
  запроса (через `webRequest`/`declarativeNetRequest` мониторинг). Передаёт их
  нативному хосту, чтобы качать от имени той же авторизованной сессии.
- **Options page**: правила перехвата (whitelist/blacklist доменов, мин. размер,
  список расширений файлов, глобальный тумблер).

### 2. Native Messaging Host (`core/Sources/hydra-host`)
Тонкий бинарь, который браузер запускает по протоколу native messaging
(4 байта длины little-endian + UTF-8 JSON). Принимает задачи `download`,
прокидывает их в `Hydra.app` (Phase 2 — через XPC/Unix-socket; в текущем MVP
качает сам через `DownloadCore` для сквозной проверки), шлёт прогресс обратно.

Регистрируется через native messaging manifest в:
- Chrome:  `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/`
- Firefox: `~/Library/Application Support/Mozilla/NativeMessagingHosts/`
- Safari:  сообщения идут через `SFSafariApplication` → containing app (не host).

### 3. Hydra.app (`app/`) — Phase 2
SwiftUI + menu bar. Единственный владелец очереди загрузок (переживает закрытие
браузера), UI списка/прогресса/пауз, настройки, линкует `DownloadCore`.

### 4. DownloadCore (`core/Sources/DownloadCore`) — ядро, готово в MVP
Переиспользуемый, тестируемый Swift-пакет. Не зависит от UI и браузера.

## Алгоритм многопоточной загрузки (DownloadCore)

1. **Probe** (`HeaderProbe`): ranged GET `Range: bytes=0-0` с заголовками
   сессии. По ответу определяем:
   - `206 Partial Content` → сервер поддерживает Range; общий размер из
     `Content-Range: bytes 0-0/<total>`.
   - `200 OK` → Range не поддержан → фолбэк в один поток.
   - имя файла из `Content-Disposition`, `ETag`/`Last-Modified` для resume.
   Тело не качаем — соединение режется сразу после заголовков (`.cancel`).
2. **Plan**: если Range поддержан и `size ≥ 2·minChunkSize` → бьём на
   `N = min(maxConnections, size/minChunkSize)` непрерывных кусков.
3. **Download**: `TaskGroup`, по `ChunkDownloader` на кусок. Файл
   предварительно аллоцируется на полный размер (`ftruncate`); каждый кусок
   открывает свой `FileHandle`, сикает на свой offset и пишет свой диапазон
   (диапазоны не пересекаются → запись без блокировок).
4. **Session replay**: каждый из параллельных запросов несёт те же
   `Cookie`/`User-Agent`/`Referer`/auth-заголовки, что и исходный → авторизация
   сохраняется. `Accept-Encoding: identity`, чтобы сжатие не ломало арифметику
   диапазонов.
5. **Assemble**: данные пишутся сразу в `<file>.hydrapart` по offset'ам, после
   успеха — атомарный rename в финальное имя.
6. **Fallback**: нет Range / неизвестен размер / одноразовый токен → один поток.

## Граничные случаи
- **Одноразовые/сессионные токены в URL**: повторно использовать токен в N
  соединениях обычно можно (это GET того же ресурса), но если сервер
  инвалидирует токен после первого запроса — детектим по ошибке диапазона и
  падаем в один поток.
- **Нет `Accept-Ranges`** → один поток.
- **Неизвестный `Content-Length`** (chunked) → один поток.
- **Resume** между перезапусками: sidecar `.hydrameta` с диапазонами и
  `ETag` для валидации `If-Range` (Phase 2).
