// Попап расширения — статус связи + снимок загрузок (дизайн из прототипа, экран 10).
const api = typeof browser !== 'undefined' ? browser : chrome;
const HOST = 'com.hydra.host';

function send(msg) {
  return new Promise((res) => {
    try {
      const r = api.runtime.sendNativeMessage(HOST, msg, (resp) => res(api.runtime.lastError ? null : resp));
      if (r && typeof r.then === 'function') r.then(res).catch(() => res(null));
    } catch { res(null); }
  });
}

function fmt(b) {
  const u = ['Б', 'КБ', 'МБ', 'ГБ', 'ТБ'];
  let v = b, i = 0;
  while (v >= 1024 && i < u.length - 1) { v /= 1024; i++; }
  return (i === 0 ? Math.round(v) : v.toFixed(1)) + ' ' + u[i];
}
function ext(name) {
  const d = name.lastIndexOf('.');
  return d < 0 ? 'FILE' : name.slice(d + 1).toUpperCase().slice(0, 4);
}
function esc(s) { const e = document.createElement('div'); e.textContent = s; return e.innerHTML; }

async function render() {
  const logo = document.getElementById('logo');
  const pill = document.getElementById('pill');
  const body = document.getElementById('body');
  const ai = document.getElementById('ai');

  const status = await send({ type: 'ping' });
  const connected = !!(status && status.connected);

  pill.className = 'pill ' + (connected ? 'on' : 'off');
  pill.innerHTML = '<span class="dot"></span>' + (connected ? 'связано' : 'не связано');

  if (!connected) {
    logo.style.background = 'var(--label2)';
    body.innerHTML =
      '<div class="warn"><div class="t">Приложение не запущено</div>' +
      '<div class="b">Качаю в резервном режиме браузера: без многопоточности и полного проброса сессии. Запусти Hydra.</div></div>';
    ai.textContent = '';
    return;
  }

  const [dl, st] = await Promise.all([send({ type: 'getDownloads' }), send({ type: 'getSettings' })]);
  const items = (dl && dl.items) || [];

  if (items.length === 0) {
    body.innerHTML = '<div class="empty">Нет активных загрузок</div>';
  } else {
    body.innerHTML = items.map((it) => {
      const pct = it.total > 0 ? Math.round((it.done / it.total) * 100) : 0;
      const sub = it.running
        ? `${pct}% · ${fmt(it.done)} из ${fmt(it.total)}`
        : `Пауза · ${pct}%`;
      return `<div class="item"><span class="badge">${esc(ext(it.name))}</span>` +
        `<div style="min-width:0;flex:1"><div class="it-name">${esc(it.name)}</div>` +
        `<div class="it-sub"><span class="d"></span>${sub}</div></div></div>`;
    }).join('');
  }

  const ver = api.runtime.getManifest().version;
  const auto = st ? 'Авто-перехват: ' + (st.autoIntercept ? 'вкл' : 'выкл') : '';
  ai.textContent = [auto, 'v' + ver].filter(Boolean).join(' · ');
}

document.getElementById('opts').addEventListener('click', () => api.runtime.openOptionsPage());
render();
