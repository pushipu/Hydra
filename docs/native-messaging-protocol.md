# Протокол расширение ⇄ hydra-host

Транспорт: стандартный Chrome/Firefox **native messaging** — каждое сообщение
это `uint32` длины (порядок байт хоста, на macOS little-endian) + UTF-8 JSON.
Хост запускается браузером, общение идёт через stdin/stdout.

## Расширение → хост

### download
```json
{
  "type": "download",
  "url": "https://site/file.zip",
  "filename": "file.zip",
  "cookie": "session=abc; csrftoken=xyz",
  "userAgent": "Mozilla/5.0 …",
  "referer": "https://site/page",
  "headers": { "Authorization": "Bearer …" },
  "connections": 8,
  "destination": "/Users/me/Downloads"
}
```
`cookie`/`referer`/`headers` — захваченная сессия; хост повторяет их во всех
параллельных Range-запросах. `destination` опционально (по умолчанию ~/Downloads).

### ping
```json
{ "type": "ping" }
```
Ответ — `{"type":"pong"}` (проверка живости хоста).

## Хост → расширение

### progress
```json
{ "type": "progress", "id": 1, "received": 10485760, "total": 73400320,
  "speed": 5242880.0, "connections": 8 }
```
`total` == -1 если размер неизвестен. Шлётся не чаще ~10 раз/с.

### done
```json
{ "type": "done", "id": 1, "path": "/Users/me/Downloads/file.zip" }
```

### error
```json
{ "type": "error", "id": 1, "message": "httpStatus(403)" }
```

## Заметки по сессии
- `cookie` собирается расширением через `chrome.cookies.getAll({url})` для
  **финального** URL загрузки (после редиректов) — это и есть авторизованная
  сессия.
- Для одноразовых токенов в URL: хост сначала делает probe; если параллельные
  запросы отвергаются — падает в один поток тем же токеном.
- Safari: сообщения идут не в отдельный stdio-хост, а в containing app через
  `browser.runtime.sendNativeMessage` → `SFSafariApplication`. Формат JSON тот
  же; в Phase 3 app выступает приёмником вместо hydra-host.
