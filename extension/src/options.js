// Загрузка/сохранение настроек на странице опций.
const $ = (id) => document.getElementById(id);

function listToText(arr) { return (arr || []).join('\n'); }
function textToList(text) {
  return text.split(/[\s,]+/).map((s) => s.trim()).filter(Boolean);
}

async function restore() {
  const s = await HydraRules.loadSettings();
  $('enabled').checked = s.enabled;
  $('contextMenuEnabled').checked = s.contextMenuEnabled;
  $('connections').value = s.connections;
  $('minSizeMB').value = s.minSizeMB;
  $('domainMode').value = s.domainMode;
  $('domainList').value = listToText(s.domainList);
  $('extensionMode').value = s.extensionMode;
  $('extensionList').value = listToText(s.extensionList);
}

async function save() {
  const settings = {
    enabled: $('enabled').checked,
    contextMenuEnabled: $('contextMenuEnabled').checked,
    connections: Math.max(1, Math.min(32, parseInt($('connections').value, 10) || 8)),
    minSizeMB: Math.max(0, parseInt($('minSizeMB').value, 10) || 0),
    domainMode: $('domainMode').value,
    domainList: textToList($('domainList').value),
    extensionMode: $('extensionMode').value,
    extensionList: textToList($('extensionList').value),
  };
  await HydraRules.saveSettings(settings);
  $('status').textContent = 'Сохранено ✓';
  setTimeout(() => ($('status').textContent = ''), 1500);
}

document.addEventListener('DOMContentLoaded', restore);
$('save').addEventListener('click', save);
