// Правила перехвата загрузок. Хранятся в chrome.storage.sync.
// Классический скрипт: вешает API на self.HydraRules, чтобы работать и в
// service worker (Chrome), и в background scripts (Firefox), и на страницах.
(function (global) {
  const DEFAULT_SETTINGS = {
    enabled: true, // глобальный тумблер авто-перехвата
    contextMenuEnabled: true, // пункт «Download with Hydra»
    connections: 8,
    minSizeMB: 10, // не перехватывать файлы мельче (0 = любые)
    domainMode: 'all', // 'all' | 'whitelist' | 'blacklist'
    domainList: [], // ['example.com', 'cdn.site.org']
    extensionMode: 'all', // 'all' | 'only' | 'except'
    extensionList: ['zip', 'dmg', 'iso', 'mp4', 'mkv', 'pdf', 'exe', 'tar', 'gz'],
  };

  const HOST = 'com.hydra.host';
  const api = typeof browser !== 'undefined' ? browser : chrome;
  let _cache = null, _cacheAt = 0;

  // Тянет настройки перехвата из приложения через native host.
  function fetchHostSettings() {
    return new Promise((resolve) => {
      try {
        const ret = api.runtime.sendNativeMessage(HOST, { type: 'getSettings' }, (resp) => {
          resolve(api.runtime.lastError || !resp || resp.type !== 'settings' ? null : resp);
        });
        if (ret && typeof ret.then === 'function') {
          ret.then((r) => resolve(r && r.type === 'settings' ? r : null)).catch(() => resolve(null));
        }
      } catch { resolve(null); }
    });
  }

  function mapHost(h) {
    const types = Array.isArray(h.fileTypes) ? h.fileTypes : [];
    return {
      enabled: !!h.autoIntercept,
      contextMenuEnabled: h.contextMenu !== false,
      connections: h.threadsPerFile || 8,
      minSizeMB: Math.round((h.minSizeBytes || 0) / (1024 * 1024)),
      domainMode: 'all',
      domainList: [],
      extensionMode: types.length ? 'only' : 'all',
      extensionList: types.length ? types : DEFAULT_SETTINGS.extensionList,
    };
  }

  // app — источник правды; кэш 30с ограничивает спавн host. Нет app → chrome.storage.
  async function loadSettings() {
    const now = Date.now();
    if (_cache && now - _cacheAt < 30000) return _cache;
    const host = await fetchHostSettings();
    let s;
    if (host) {
      s = mapHost(host);
      try { await api.storage.sync.set({ settings: s }); } catch {}   // офлайн-кэш
    } else {
      const stored = await api.storage.sync.get('settings');
      s = Object.assign({}, DEFAULT_SETTINGS, stored.settings || {});
    }
    _cache = s; _cacheAt = now;
    return s;
  }

  async function saveSettings(settings) {
    await chrome.storage.sync.set({ settings });
  }

  function hostOf(url) {
    try { return new URL(url).hostname.toLowerCase(); } catch { return ''; }
  }

  function extOf(url) {
    try {
      const path = new URL(url).pathname;
      const dot = path.lastIndexOf('.');
      return dot < 0 ? '' : path.slice(dot + 1).toLowerCase();
    } catch { return ''; }
  }

  function domainMatches(host, list) {
    return list.some((d) => {
      d = String(d).trim().toLowerCase();
      return d && (host === d || host.endsWith('.' + d));
    });
  }

  // fileSizeBytes может быть -1 (неизвестно).
  function shouldIntercept(settings, { url, fileSizeBytes }) {
    if (!settings.enabled) return false;

    const host = hostOf(url);
    if (settings.domainMode === 'whitelist' && !domainMatches(host, settings.domainList)) return false;
    if (settings.domainMode === 'blacklist' && domainMatches(host, settings.domainList)) return false;

    const ext = extOf(url);
    if (settings.extensionMode === 'only' && !settings.extensionList.includes(ext)) return false;
    if (settings.extensionMode === 'except' && settings.extensionList.includes(ext)) return false;

    const minBytes = (settings.minSizeMB || 0) * 1024 * 1024;
    if (minBytes > 0 && fileSizeBytes >= 0 && fileSizeBytes < minBytes) return false;

    return true;
  }

  global.HydraRules = { DEFAULT_SETTINGS, loadSettings, saveSettings, shouldIntercept };
})(typeof self !== 'undefined' ? self : this);
