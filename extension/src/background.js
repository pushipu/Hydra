// Hydra background. Перехватывает загрузки и контекстное меню, собирает сессию
// (куки/заголовки) и отдаёт нативному хосту hydra-host.

// Chrome (service worker, классический): подгружаем rules.js.
// Firefox: rules.js уже загружен через manifest.background.scripts.
try {
  if (typeof HydraRules === 'undefined') importScripts('rules.js');
} catch (e) {
  /* в Firefox importScripts недоступен — модуль уже загружен */
}

const HOST_NAME = 'com.hydra.host';
const CONTEXT_MENU_ID = 'hydra-download';

const api = typeof browser !== 'undefined' ? browser : chrome;

// --- Сбор сессии для URL: Cookie + User-Agent + Referer. ---
async function captureSession(url, referrer) {
  let cookieHeader = '';
  try {
    const cookies = await api.cookies.getAll({ url });
    cookieHeader = cookies.map((c) => `${c.name}=${c.value}`).join('; ');
  } catch (e) {
    console.warn('cookies.getAll failed:', e);
  }
  return {
    cookie: cookieHeader,
    userAgent: navigator.userAgent,
    referer: referrer || '',
  };
}

async function sendToHydra({ url, filename, referrer }) {
  const settings = await HydraRules.loadSettings();
  const session = await captureSession(url, referrer);
  const message = {
    type: 'download',
    url,
    filename: filename || '',
    cookie: session.cookie,
    userAgent: session.userAgent,
    referer: session.referer,
    connections: settings.connections || 8,
  };
  try {
    api.runtime.sendNativeMessage(HOST_NAME, message);
  } catch (e) {
    console.error('failed to reach hydra-host:', e);
  }
}

// --- Авто-перехват загрузок. onCreated есть и в Chrome, и в Firefox. ---
api.downloads.onCreated.addListener(async (item) => {
  const settings = await HydraRules.loadSettings();
  const url = item.finalUrl || item.url;
  if (!url || !/^https?:/.test(url)) return;

  if (!HydraRules.shouldIntercept(settings, { url, fileSizeBytes: item.fileSize ?? item.totalBytes ?? -1 })) {
    return;
  }

  // Останавливаем родную загрузку и стираем её из списка браузера.
  try {
    await api.downloads.cancel(item.id);
    await api.downloads.erase({ id: item.id });
  } catch (e) {
    console.warn('cancel/erase failed:', e);
  }

  const filename = item.filename ? item.filename.split('/').pop() : '';
  await sendToHydra({ url, filename, referrer: item.referrer });
});

// --- Контекстное меню. ---
function setupContextMenu(enabled) {
  api.contextMenus.removeAll(() => {
    if (!enabled) return;
    api.contextMenus.create({
      id: CONTEXT_MENU_ID,
      title: 'Download with Hydra',
      contexts: ['link', 'image', 'video', 'audio'],
    }, () => void api.runtime.lastError); // глушим «duplicate id» при гонке стартов
  });
}

api.contextMenus.onClicked.addListener(async (info) => {
  if (info.menuItemId !== CONTEXT_MENU_ID) return;
  const url = info.linkUrl || info.srcUrl;
  if (!url) return;
  await sendToHydra({ url, referrer: info.pageUrl });
});

// Инициализация + реакция на смену настроек.
async function init() {
  const settings = await HydraRules.loadSettings();
  setupContextMenu(settings.contextMenuEnabled);
}
// Меню создаём только на onInstalled/onStartup — оно персистится, пересоздавать
// при каждом пробуждении service worker не нужно (и это вызывало гонку→duplicate).
api.runtime.onInstalled.addListener(init);
api.runtime.onStartup?.addListener(init);
api.storage.onChanged.addListener((changes, area) => {
  if (area === 'sync' && changes.settings) {
    setupContextMenu(changes.settings.newValue?.contextMenuEnabled ?? true);
  }
});
