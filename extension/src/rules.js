// Правила перехвата загрузок. Хранятся локально в профиле браузера.
// Классический скрипт: вешает API на self.HydraRules, чтобы работать и в
// service worker (Chrome), и в background scripts (Firefox), и на страницах.
(function (global) {
  const DEFAULT_SETTINGS = {
    privacyConsent: false, // явное согласие на локальную передачу данных в Hydra.app
    enabled: false, // глобальный тумблер авто-перехвата
    contextMenuEnabled: true, // пункт «Download with Hydra»
    connections: 8,
    minSizeMB: 10, // не перехватывать файлы мельче (0 = любые)
    domainMode: 'all', // 'all' | 'whitelist' | 'blacklist'
    domainList: [], // ['example.com', 'cdn.site.org']
    extensionMode: 'all', // 'all' | 'only' | 'except'
    extensionList: ['zip', 'dmg', 'iso', 'mp4', 'mkv', 'pdf', 'exe', 'tar', 'gz'],
  };

  const api = typeof browser !== 'undefined' ? browser : chrome;
  let _cache = null, _cacheAt = 0;

  // Тянет общие настройки перехвата из приложения через native host.
  async function fetchHostSettings() {
    const response = await HydraNative.send({ type: 'getSettings' });
    return response?.type === 'settings' ? response : null;
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

  // Общие параметры берём из app, правила конкретного браузера — из storage.sync.
  async function loadSettings() {
    const now = Date.now();
    if (_cache && now - _cacheAt < 30000) return _cache;
    const [stored, host] = await Promise.all([
      api.storage.local.get('settings'),
      fetchHostSettings(),
    ]);
    const app = host ? mapHost(host) : null;
    const saved = stored.settings || {};
    const next = Object.assign({}, DEFAULT_SETTINGS, Object.keys(saved).length ? saved : (app || {}));
    next.privacyConsent = saved.privacyConsent === true;
    if (app) {
      next.enabled = app.enabled;
      next.connections = app.connections;
      next.minSizeMB = app.minSizeMB;
    }
    if (!next.privacyConsent) next.enabled = false;
    try { await api.storage.local.set({ settings: next }); } catch {}
    _cache = next;
    _cacheAt = now;
    return next;
  }

  async function saveSettings(settings) {
    const next = Object.assign({}, DEFAULT_SETTINGS, settings);
    next.enabled = next.privacyConsent && next.enabled;
    await HydraNative.send({
      type: 'setSettings',
      autoIntercept: next.enabled,
      minSizeMB: next.minSizeMB,
      threadsPerFile: next.connections,
    });
    await api.storage.local.set({ settings: next });
    _cache = next;
    _cacheAt = Date.now();
  }

  api.storage.onChanged?.addListener((changes, area) => {
    if (area === 'local' && changes.settings) { _cache = null; _cacheAt = 0; }
  });

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
    if (!settings.privacyConsent || !settings.enabled) return false;

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
