// Настройки браузерного перехвата: спокойная форма без зависимостей.
const $ = (id) => document.getElementById(id);
const api = typeof browser !== 'undefined' ? browser : chrome;
const form = $('settings');
let ready = false;

function textToList(text) {
  return String(text || '').split(/[\s,]+/).map((value) => value.trim()).filter(Boolean);
}

function modeValue(name) {
  return form.elements[name].value;
}

function setMode(name, value) {
  const input = form.querySelector(`input[name="${name}"][value="${value}"]`);
  (input || form.querySelector(`input[name="${name}"]`)).checked = true;
}

function normalizeDomain(value) {
  const raw = value.trim().toLowerCase().replace(/^\*\./, '');
  if (!raw) return '';
  try {
    return new URL(raw.includes('://') ? raw : `https://${raw}`).hostname.replace(/\.$/, '');
  } catch {
    return raw.replace(/^https?:\/\//, '').split('/')[0].replace(/\.$/, '');
  }
}

function normalizeExtension(value) {
  return value.trim().toLowerCase().replace(/^\.+/, '');
}

function createTokenEditor({ fieldId, tokensId, entryId, hiddenId, normalize }) {
  const field = $(fieldId);
  const tokens = $(tokensId);
  const entry = $(entryId);
  const hidden = $(hiddenId);
  let values = [];

  function sync() {
    hidden.value = values.join('\n');
    if (ready) hidden.dispatchEvent(new Event('input', { bubbles: true }));
  }

  function render() {
    tokens.replaceChildren(...values.map((value) => {
      const token = document.createElement('span');
      token.className = 'token';

      const text = document.createElement('span');
      text.textContent = value;

      const remove = document.createElement('button');
      remove.type = 'button';
      remove.setAttribute('aria-label', `Удалить ${value}`);
      remove.innerHTML = '<svg viewBox="0 0 12 12" aria-hidden="true"><path d="m3 3 6 6M9 3 3 9" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/></svg>';
      remove.addEventListener('click', () => {
        values = values.filter((item) => item !== value);
        render();
        sync();
        entry.focus();
      });

      token.append(text, remove);
      return token;
    }));
  }

  function add(raw) {
    const next = textToList(raw).map(normalize).filter(Boolean);
    entry.value = '';
    const merged = [...new Set([...values, ...next])];
    if (merged.length === values.length) return;
    values = merged;
    render();
    sync();
  }

  entry.addEventListener('keydown', (event) => {
    if (event.key === 'Enter' || event.key === ',') {
      event.preventDefault();
      add(entry.value);
    } else if (event.key === 'Backspace' && !entry.value && values.length) {
      values.pop();
      render();
      sync();
    }
  });
  entry.addEventListener('blur', () => add(entry.value));
  field.addEventListener('click', (event) => {
    if (event.target === field || event.target === tokens) entry.focus();
  });

  return {
    set(next) {
      values = [...new Set((next || []).map(normalize).filter(Boolean))];
      render();
      sync();
    },
    get() {
      if (entry.value) add(entry.value);
      return [...values];
    },
  };
}

const domains = createTokenEditor({
  fieldId: 'domainField', tokensId: 'domainTokens', entryId: 'domainEntry', hiddenId: 'domainList', normalize: normalizeDomain,
});
const extensions = createTokenEditor({
  fieldId: 'extensionField', tokensId: 'extensionTokens', entryId: 'extensionEntry', hiddenId: 'extensionList', normalize: normalizeExtension,
});

function syncRuleDetails() {
  $('domainDetails').hidden = modeValue('domainMode') === 'all';
  $('extensionDetails').hidden = modeValue('extensionMode') === 'all';
}

function syncConsent() {
  const accepted = $('privacyConsent').checked;
  $('enabled').disabled = !accepted;
  if (!accepted) $('enabled').checked = false;
}

function markDirty() {
  if (!ready) return;
  $('save').disabled = false;
  $('status').className = '';
  $('status').textContent = 'Есть несохранённые изменения';
}

async function restore() {
  const settings = await HydraRules.loadSettings();
  $('privacyConsent').checked = settings.privacyConsent;
  $('enabled').checked = settings.privacyConsent && settings.enabled;
  $('contextMenuEnabled').checked = settings.contextMenuEnabled;
  $('connections').value = settings.connections;
  $('minSizeMB').value = settings.minSizeMB;
  setMode('domainMode', settings.domainMode);
  domains.set(settings.domainList);
  setMode('extensionMode', settings.extensionMode);
  extensions.set(settings.extensionList);
  syncConsent();
  syncRuleDetails();
  ready = true;
}

async function save(event) {
  event.preventDefault();
  $('save').disabled = true;
  $('status').className = '';
  $('status').textContent = 'Сохраняем…';

  const settings = {
    privacyConsent: $('privacyConsent').checked,
    enabled: $('privacyConsent').checked && $('enabled').checked,
    contextMenuEnabled: $('contextMenuEnabled').checked,
    connections: Math.max(1, Math.min(32, parseInt($('connections').value, 10) || 8)),
    minSizeMB: Math.max(0, parseInt($('minSizeMB').value, 10) || 0),
    domainMode: modeValue('domainMode'),
    domainList: domains.get(),
    extensionMode: modeValue('extensionMode'),
    extensionList: extensions.get(),
  };

  try {
    await HydraRules.saveSettings(settings);
    $('connections').value = settings.connections;
    $('minSizeMB').value = settings.minSizeMB;
    $('status').className = 'saved';
    $('status').textContent = 'Сохранено';
  } catch {
    $('save').disabled = false;
    $('status').className = 'error';
    $('status').textContent = 'Не удалось сохранить настройки';
  }
}

async function checkConnection() {
  const response = await HydraNative.send({ type: 'ping' });

  const connected = response?.type === 'status' && response.connected;
  $('connection').classList.add(connected ? 'connected' : 'disconnected');
  $('connectionText').textContent = connected ? 'Hydra подключена' : 'Приложение не запущено';
}

form.addEventListener('input', markDirty);
form.addEventListener('change', (event) => {
  if (event.target.id === 'privacyConsent') syncConsent();
  if (event.target.matches('input[type="radio"]')) syncRuleDetails();
  markDirty();
});
form.addEventListener('submit', save);

document.addEventListener('DOMContentLoaded', () => {
  restore().catch(() => {
    $('status').className = 'error';
    $('status').textContent = 'Не удалось загрузить настройки';
  });
  checkConnection();
});
