import Foundation
import Combine

enum Lang: String, CaseIterable, Identifiable {
    case en, ru, zh
    var id: String { rawValue }
    var nativeName: String {
        switch self {
        case .en: return "English"
        case .ru: return "Русский"
        case .zh: return "中文"
        }
    }
}

/// Простой локализатор. Ключ — русский литерал (исходный язык кода), таблица даёт
/// en/zh; для ru возвращается сам ключ. Реактивный: views, наблюдающие Localizer,
/// перерисовываются при смене языка. По умолчанию — английский (первый запуск).
final class Localizer: ObservableObject {
    static let shared = Localizer()
    @Published var lang: Lang {
        didSet { UserDefaults.standard.set(lang.rawValue, forKey: "language") }
    }
    private init() {
        if let raw = UserDefaults.standard.string(forKey: "language"), let l = Lang(rawValue: raw) {
            lang = l
        } else {
            lang = .en   // первый запуск — английский
        }
    }
}

/// Перевод по русскому ключу.
func L(_ ru: String) -> String {
    let lang = Localizer.shared.lang
    if lang == .ru { return ru }
    return table[ru]?[lang.rawValue] ?? ru
}

private let table: [String: [String: String]] = [
    // — Поповер / общее —
    "Все загрузки":            ["en": "All downloads", "zh": "所有下载"],
    "Настройки":               ["en": "Settings", "zh": "设置"],
    "Настройки…":              ["en": "Settings…", "zh": "设置…"],
    "Настройки Hydra":         ["en": "Hydra Settings", "zh": "Hydra 设置"],
    "Окно перетаскивания":     ["en": "Drop window", "zh": "拖放窗口"],
    "Окно перетаскивания ссылок": ["en": "Link drop window", "zh": "链接拖放窗口"],
    "Закрепить попап":         ["en": "Pin popover", "zh": "固定弹窗"],
    "Бросьте ссылку":          ["en": "Drop a link", "zh": "拖入链接"],
    "Отпустите":               ["en": "Release", "zh": "松开"],
    "или адрес из браузера":   ["en": "or an address from the browser", "zh": "或浏览器中的地址"],
    "добавим в Hydra":         ["en": "we’ll add it to Hydra", "zh": "将添加到 Hydra"],
    "Скачать из буфера":       ["en": "Download from clipboard", "zh": "从剪贴板下载"],
    "Пауза всех":              ["en": "Pause all", "zh": "全部暂停"],
    "Возобновить всё":         ["en": "Resume all", "zh": "全部恢复"],
    "Возобновить":             ["en": "Resume", "zh": "恢复"],
    "Добавить":                ["en": "Add", "zh": "添加"],
    "Скачать":                 ["en": "Download", "zh": "下载"],
    "Вставить ссылку…":        ["en": "Paste a link…", "zh": "粘贴链接…"],
    "Здесь появятся загрузки": ["en": "Downloads will appear here", "zh": "下载将显示在此"],
    "Нажмите «Скачать через Hydra» в браузере\nили вставьте ссылку вручную":
        ["en": "Click “Download with Hydra” in your browser\nor paste a link manually",
         "zh": "在浏览器中点击“通过 Hydra 下载”\n或手动粘贴链接"],
    // — Состояния строки —
    "В очереди":               ["en": "Queued", "zh": "排队中"],
    "Пауза":                   ["en": "Paused", "zh": "已暂停"],
    "Приостановить":           ["en": "Pause", "zh": "暂停"],
    "Готово":                  ["en": "Done", "zh": "完成"],
    "Отменено":                ["en": "Cancelled", "zh": "已取消"],
    "Ошибка":                  ["en": "Error", "zh": "错误"],
    "Один поток":              ["en": "Single thread", "zh": "单线程"],
    "Скачивается":             ["en": "Downloading", "zh": "下载中"],
    "Завершено":               ["en": "Completed", "zh": "已完成"],
    "Показать в Finder":       ["en": "Show in Finder", "zh": "在访达中显示"],
    "Повторить":               ["en": "Retry", "zh": "重试"],
    "Скачать заново":          ["en": "Download again", "zh": "重新下载"],
    "Копировать ссылку":       ["en": "Copy link", "zh": "复制链接"],
    // — Детали загрузки (экран 05) —
    "Сегменты файла по потокам": ["en": "File segments by thread", "zh": "按线程划分的文件分段"],
    "Сводка":                  ["en": "Summary", "zh": "摘要"],
    "Осталось":                ["en": "Left", "zh": "剩余"],
    "Прошло":                  ["en": "Elapsed", "zh": "已用"],
    "Скачано":                 ["en": "Downloaded", "zh": "已下载"],
    "Потоков":                 ["en": "Threads", "zh": "线程"],
    "Отмена":                  ["en": "Cancel", "zh": "取消"],
    "средняя":                 ["en": "avg", "zh": "平均"],
    "осталось":                ["en": "left", "zh": "剩余"],
    "В очереди · приоритет":   ["en": "Queued · priority", "zh": "排队 · 优先级"],
    "блоков":                  ["en": "blocks", "zh": "块"],
    "потоков":                 ["en": "threads", "zh": "线程"],
    "активна":                 ["en": "active", "zh": "进行中"],
    "активны":                 ["en": "active", "zh": "进行中"],
    "в очереди":               ["en": "queued", "zh": "排队中"],
    "завершено":               ["en": "completed", "zh": "已完成"],
    "готово":                  ["en": "done", "zh": "完成"],
    // — Меню статус-бара —
    "Открыть окно загрузок":   ["en": "Open downloads window", "zh": "打开下载窗口"],
    "Выйти из Hydra":          ["en": "Quit Hydra", "zh": "退出 Hydra"],
    // — Главное окно —
    "Загрузки":                ["en": "Downloads", "zh": "下载"],
    "Все":                     ["en": "All", "zh": "全部"],
    "Активные":                ["en": "Active", "zh": "进行中"],
    "Завершённые":             ["en": "Completed", "zh": "已完成"],
    "Готовые":                 ["en": "Done", "zh": "已完成"],
    "Ошибки":                  ["en": "Errors", "zh": "错误"],
    "Библиотека":              ["en": "Library", "zh": "资料库"],
    "Источники":               ["en": "Sources", "zh": "来源"],
    "Имя":                     ["en": "Name", "zh": "名称"],
    "Статус":                  ["en": "Status", "zh": "状态"],
    "Размер":                  ["en": "Size", "zh": "大小"],
    "Поиск":                   ["en": "Search", "zh": "搜索"],
    "Сортировка":              ["en": "Sort", "zh": "排序"],
    "По добавлению":           ["en": "By date added", "zh": "按添加时间"],
    "По имени":                ["en": "By name", "zh": "按名称"],
    "По размеру":              ["en": "By size", "zh": "按大小"],
    "Очистить историю":        ["en": "Clear history", "zh": "清除历史"],
    "Удалить":                 ["en": "Delete", "zh": "删除"],
    "удалить":                 ["en": "delete", "zh": "删除"],
    "загрузок":                ["en": "downloads", "zh": "个下载"],
    // — Настройки —
    "Загрузка":                ["en": "Downloads", "zh": "下载"],
    "Перехват":                ["en": "Capture", "zh": "拦截"],
    "Завершение":              ["en": "On finish", "zh": "完成时"],
    "Папки":                   ["en": "Folders", "zh": "文件夹"],
    "Одновременные загрузки":  ["en": "Concurrent downloads", "zh": "同时下载"],
    "Качать одновременно":     ["en": "Download at once", "zh": "同时下载数"],
    "Потоков на файл":         ["en": "Threads per file", "zh": "每文件线程数"],
    "Скорость":                ["en": "Speed", "zh": "速度"],
    "Ограничивать скорость":   ["en": "Limit speed", "zh": "限制速度"],
    "Перехват из браузера":    ["en": "Browser capture", "zh": "浏览器拦截"],
    "Перехватывать автоматически": ["en": "Capture automatically", "zh": "自动拦截"],
    "Минимальный размер файла": ["en": "Minimum file size", "zh": "最小文件大小"],
    "Типы файлов":             ["en": "File types", "zh": "文件类型"],
    "Эти настройки применяются и в браузерном расширении — оно читает их из приложения.":
        ["en": "These settings also apply to the browser extension — it reads them from the app.",
         "zh": "这些设置同样应用于浏览器扩展——它从应用读取。"],
    "По завершении":           ["en": "On completion", "zh": "完成后"],
    "Действие":                ["en": "Action", "zh": "操作"],
    "Открыть папку":           ["en": "Open folder", "zh": "打开文件夹"],
    "Звук":                    ["en": "Sound", "zh": "声音"],
    "Ничего":                  ["en": "Nothing", "zh": "无"],
    "Тихий режим (без уведомлений, кроме ошибок)":
        ["en": "Quiet mode (no notifications except errors)", "zh": "安静模式（错误除外无通知）"],
    "Система":                 ["en": "System", "zh": "系统"],
    "Общие":                   ["en": "General", "zh": "通用"],
    "Язык":                    ["en": "Language", "zh": "语言"],
    "Запуск при входе в систему": ["en": "Launch at login", "zh": "登录时启动"],
    "Плавающее окно для перетаскивания ссылок":
        ["en": "Floating link-drop window", "zh": "链接拖放浮窗"],
    "Папка загрузок по умолчанию": ["en": "Default downloads folder", "zh": "默认下载文件夹"],
    "Выбрать…":                ["en": "Choose…", "zh": "选择…"],
    // — Уведомления —
    "Загрузка завершена":      ["en": "Download complete", "zh": "下载完成"],
    "Ошибка загрузки":         ["en": "Download failed", "zh": "下载失败"],
    "Требуется вход":          ["en": "Sign-in required", "zh": "需要登录"],
    "Войти":                   ["en": "Sign in", "zh": "登录"],
    "сессия истекла во время загрузки":
        ["en": "session expired during download", "zh": "下载期间会话已过期"],
    // — Ошибки —
    "Неподдерживаемая ссылка": ["en": "Unsupported link", "zh": "不支持的链接"],
    "Файл на сервере изменился — нужно заново":
        ["en": "File changed on server — restart needed", "zh": "服务器文件已更改——需重新下载"],
    "Недостаточно места на диске": ["en": "Not enough disk space", "zh": "磁盘空间不足"],
    "Папка назначения недоступна для записи":
        ["en": "Destination folder is not writable", "zh": "目标文件夹不可写"],
    "Папка назначения недоступна — нет файла или каталога":
        ["en": "Destination unavailable — no such file or directory", "zh": "目标不可用——无此文件或目录"],
    // — Единицы —
    "Б":  ["en": "B",  "zh": "B"],
    "КБ": ["en": "KB", "zh": "KB"],
    "МБ": ["en": "MB", "zh": "MB"],
    "ГБ": ["en": "GB", "zh": "GB"],
    "ТБ": ["en": "TB", "zh": "TB"],
    "ч":  ["en": "h",  "zh": "小时"],
    "мин": ["en": "min", "zh": "分"],
    "с":  ["en": "s",  "zh": "秒"],
    "из": ["en": "of", "zh": "/"],
]
