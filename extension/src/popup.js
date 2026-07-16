const api = typeof browser !== 'undefined' ? browser : chrome;

function domainSummary(settings) {
  if (settings.domainMode === 'whitelist') return `Только выбранные · ${settings.domainList.length}`;
  if (settings.domainMode === 'blacklist') return `Кроме выбранных · ${settings.domainList.length}`;
  return 'Все сайты';
}

function typeSummary(settings) {
  if (settings.extensionMode === 'only') return `Только выбранные · ${settings.extensionList.length}`;
  if (settings.extensionMode === 'except') return `Кроме выбранных · ${settings.extensionList.length}`;
  return 'Все типы';
}

function displayURL(value) {
  try {
    const url = new URL(value);
    return url.hostname + (url.pathname === '/' ? '' : url.pathname);
  } catch { return value; }
}

function displayName(item) {
  if (item.filename) return item.filename;
  try {
    const url = new URL(item.url);
    return decodeURIComponent(url.pathname.split('/').filter(Boolean).pop() || url.hostname);
  } catch { return item.url; }
}

function renderLog(items) {
  const list = document.getElementById('logList');
  const visible = (items || []).slice(0, 2);
  document.getElementById('logCount').textContent = items?.length
    ? (items.length > 2 ? `2 из ${items.length}` : String(items.length))
    : '';

  if (!visible.length) return;
  const labels = {
    sending: ['Передаётся', ''],
    sent: ['В Hydra', 'sent'],
    local: ['Без приложения', 'local'],
    failed: ['Ошибка', 'failed'],
  };
  const source = { auto: 'Автоперехват', menu: 'Контекстное меню' };
  const time = new Intl.DateTimeFormat('ru', { hour: '2-digit', minute: '2-digit' });

  list.replaceChildren(...visible.map((item) => {
    const row = document.createElement('div');
    row.className = 'log-item';

    const copy = document.createElement('div');
    copy.className = 'log-copy';
    const title = document.createElement('div');
    title.className = 'log-title';
    title.textContent = displayName(item);
    const url = document.createElement('div');
    url.className = 'log-url';
    url.textContent = displayURL(item.url);
    const meta = document.createElement('div');
    meta.className = 'log-meta';
    meta.textContent = `${source[item.source] || 'Передача'} · ${time.format(new Date(item.createdAt))}`;
    copy.append(title, url, meta);

    const [statusText, statusClass] = labels[item.status] || labels.failed;
    const status = document.createElement('span');
    status.className = `log-status ${statusClass}`;
    status.textContent = statusText;
    row.append(copy, status);
    return row;
  }));
}

async function render() {
  const [connection, settings, stored] = await Promise.all([
    HydraNative.send({ type: 'ping' }),
    HydraRules.loadSettings(),
    api.storage.local.get('transferLog'),
  ]);
  const connected = connection?.type === 'status' && connection.connected;
  const badge = document.getElementById('connection');
  badge.classList.add(connected ? 'connected' : 'disconnected');
  document.getElementById('connectionText').textContent = connected ? 'Подключена' : 'Не запущена';

  const auto = document.getElementById('autoValue');
  auto.textContent = settings.privacyConsent ? (settings.enabled ? 'Включён' : 'Выключен') : 'Нужно разрешение';
  auto.className = `setting-value ${settings.enabled ? 'on' : 'off'}`;
  document.getElementById('sizeValue').textContent = settings.minSizeMB ? `От ${settings.minSizeMB} МБ` : 'Любой размер';
  const domains = document.getElementById('domainsValue');
  domains.textContent = domainSummary(settings);
  if (settings.domainMode === 'whitelist' && !settings.domainList.length) domains.classList.add('off');
  const types = document.getElementById('typesValue');
  types.textContent = typeSummary(settings);
  if (settings.extensionMode === 'only' && !settings.extensionList.length) types.classList.add('off');
  renderLog(stored.transferLog || []);
}

document.getElementById('openApp').addEventListener('click', async (event) => {
  const button = event.currentTarget;
  const label = button.querySelector('span');
  button.disabled = true;
  label.textContent = 'Открываем…';
  const response = await HydraNative.send({ type: 'openApp' });
  if (response?.type === 'done') window.close();
  else {
    button.disabled = false;
    label.textContent = 'Не удалось открыть Hydra';
  }
});

document.getElementById('openSettings').addEventListener('click', async () => {
  try {
    await api.runtime.openOptionsPage();
    window.close();
  } catch {}
});

render().catch(() => {
  document.getElementById('connection').classList.add('disconnected');
  document.getElementById('connectionText').textContent = 'Нет связи';
});
