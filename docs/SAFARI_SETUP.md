# Safari Extension Setup (Phase 3)

Safari требует Xcode проект. Hydra.app уже готов, нужно добавить Safari Extension target.

## Шаги

1. **Открой Hydra.app в Xcode**:
   ```bash
   # Создай Xcode проект из SwiftPM Package
   cd /Users/pushi/Repos/Hydra/core
   swift package generate-xcodeproj
   open Hydra.xcodeproj
   ```

2. **Добавь Safari Extension target**:
   - File → New → Target → Safari Extension
   - Product Name: `HydraExtension`
   - Language: Swift
   - Embedding app: `HydraApp`

3. **Замени сгенерированный код расширения**:
   - Удали дефолтный `Resources/` и `SafariWebExtensionHandler.swift`
   - Скопируй `extension/src/` → `HydraExtension/Resources/`
   - Скопируй `extension/manifest.chrome.json` → `HydraExtension/Resources/manifest.json`
   - Убери `browser_specific_settings` из манифеста (Safari не нужен)

4. **Обнови Info.plist Safari Extension**:
   - `NSExtensionPointIdentifier` = `com.apple.Safari.web-extension`
   - `SFSafariWebsiteAccess` → `Allowed Domains` = `<all_urls>`

5. **Убери native messaging host из Safari**:
   Safari расширение общается с containing app напрямую через `browser.runtime.sendNativeMessage`, не через stdio-хост. Добавь в HydraApp:

   ```swift
   // HydraApp.swift
   import SafariServices

   extension HydraApp {
       func application(_ application: NSApplication,
                       didFinishLaunchingWithOptions launchOptions: [NSApplication.LaunchOptionsKey: Any]?) -> Bool {
           SFSafariExtensionManager.getStateOfSafariExtension(withIdentifier: "com.hydra.app.HydraExtension") { state, _ in
               // enable extension if needed
           }
           return true
       }
   }
   ```

6. **Собери и установи**:
   - Build `HydraApp` scheme
   - Запусти `Hydra.app`
   - Safari → Preferences → Extensions → включи `Hydra`

## Отличия Safari от Chrome/Firefox

- **Native messaging**: Safari не использует stdio-хост. Сообщения идут через `browser.runtime.sendNativeMessage` → `SFSafariApplication` → containing app. Код в `extension/src/background.js` уже использует `api.runtime.sendNativeMessage`, который Safari перенаправит в HydraApp.

- **Манифест**: Safari игнорирует `browser_specific_settings`, но требует те же permissions.

- **Установка**: Safari extension должен быть подписан (для разработки — automatic signing в Xcode).

## Ponytail note

Safari Extension — единственная часть, требующая Xcode GUI. Всё остальное (движок, хост, расширение Chrome/Firefox, Hydra.app) собирается через SwiftPM CLI.
