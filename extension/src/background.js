// Hydra background. Перехватывает загрузки и контекстное меню, собирает сессию
// (куки/заголовки) и отдаёт нативному хосту hydra-host.

// Chrome (service worker, классический): подгружаем зависимости.
// Firefox: они уже загружены через manifest.background.scripts.
try {
  if (typeof HydraNative === 'undefined') importScripts('native.js');
  if (typeof HydraRules === 'undefined') importScripts('rules.js');
} catch (e) {
  /* в Firefox importScripts недоступен — модуль уже загружен */
}

const CONTEXT_MENU_ID = 'hydra-download';
const TRANSFER_LOG_KEY = 'transferLog';
const TRANSFER_LOG_LIMIT = 20;

const api = typeof browser !== 'undefined' ? browser : chrome;
let logWrite = Promise.resolve();

function updateActionIcon(enabled) {
  const action = api.action || api.browserAction;
  if (!action) return;
  try {
    const update = action.setIcon({
      path: enabled
        ? { 16: 'icons/icon16.png', 32: 'icons/icon32.png' }
        : { 16: 'icons/icon16-disabled.png', 32: 'icons/icon32-disabled.png' },
    });
    update?.catch?.(() => {}); // Chrome может отменить запрос во время перезагрузки расширения.
  } catch {}
}

// Одна короткая очередь не теряет записи, когда несколько ссылок прилетают вместе.
function editTransferLog(edit) {
  const task = logWrite.catch(() => {}).then(async () => {
    const stored = await api.storage.local.get(TRANSFER_LOG_KEY);
    const items = edit(stored[TRANSFER_LOG_KEY] || []).slice(0, TRANSFER_LOG_LIMIT);
    await api.storage.local.set({ [TRANSFER_LOG_KEY]: items });
  });
  logWrite = task;
  return task;
}

function addTransfer(item) {
  return editTransferLog((items) => [item, ...items]);
}

function updateTransfer(id, status) {
  return editTransferLog((items) => items.map((item) => item.id === id ? { ...item, status } : item));
}

// --- Сбор сессии для URL: Cookie + User-Agent + Referer. ---
async function captureSession(url, referrer) {
  let cookieHeader = '';
  try {
    const cookies = await api.cookies.getAll({ url });
    cookieHeader = cookies.map((c) => `${c.name}=${c.value}`).join('; ');
  } catch (e) {
    console.warn('cookies.getAll failed:', e);
  }
  let userAgent = navigator.userAgent;
  if (typeof browser !== 'undefined') {
    try {
      const granted = (await api.permissions.getAll()).data_collection || [];
      if (!granted.includes('technicalAndInteraction')) userAgent = '';
    } catch { userAgent = ''; }
  }
  return {
    cookie: cookieHeader,
    userAgent,
    referer: referrer || '',
  };
}

async function sendToHydra({ url, filename, referrer, source }) {
  const settings = await HydraRules.loadSettings();
  if (!settings.privacyConsent) return;
  const session = await captureSession(url, referrer);
  const transfer = {
    id: `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
    url,
    filename: filename || '',
    source,
    status: 'sending',
    createdAt: Date.now(),
  };
  await addTransfer(transfer);
  const message = {
    type: 'download',
    url,
    filename: filename || '',
    cookie: session.cookie,
    userAgent: session.userAgent,
    referer: session.referer,
    connections: settings.connections || 8,
  };
  const response = await HydraNative.send(message);
  const status = response?.type === 'done' ? (response.path ? 'local' : 'sent') : 'failed';
  await updateTransfer(transfer.id, status);
  if (status === 'failed') console.error('failed to reach hydra-host:', response?.message || 'no response');
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
  await sendToHydra({ url, filename, referrer: item.referrer, source: 'auto' });
});

// --- Контекстное меню. ---
async function setupContextMenu(enabled) {
  try {
    await api.contextMenus.removeAll();
    if (enabled) api.contextMenus.create({
      id: CONTEXT_MENU_ID,
      title: 'Download with Hydra',
      contexts: ['link', 'image', 'video', 'audio'],
    });
  } catch {}
}

api.contextMenus.onClicked.addListener(async (info) => {
  if (info.menuItemId !== CONTEXT_MENU_ID) return;
  const url = info.linkUrl || info.srcUrl;
  if (!url) return;
  const settings = await HydraRules.loadSettings();
  if (!settings.privacyConsent) {
    try { await api.runtime.openOptionsPage(); } catch {}
    return;
  }
  await sendToHydra({ url, referrer: info.pageUrl, source: 'menu' });
});

// Инициализация + реакция на смену настроек.
async function init() {
  const settings = await HydraRules.loadSettings();
  await setupContextMenu(settings.contextMenuEnabled);
  if (!settings.enabled) updateActionIcon(false);
}
// Меню создаём только на onInstalled/onStartup — оно персистится, пересоздавать
// при каждом пробуждении service worker не нужно (и это вызывало гонку→duplicate).
api.runtime.onInstalled.addListener(init);
api.runtime.onStartup?.addListener(init);
api.storage.onChanged.addListener((changes, area) => {
  if (area === 'local' && changes.settings) {
    const settings = changes.settings.newValue || {};
    void setupContextMenu(settings.contextMenuEnabled ?? true);
    updateActionIcon(settings.enabled ?? true);
  }
});
