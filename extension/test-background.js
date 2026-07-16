const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

let onCreated;
let onInstalled;
let onStorageChanged;
let actionIcon = { 16: 'icons/icon16.png', 32: 'icons/icon32.png' };
const local = {};
const chrome = {
  action: { setIcon: ({ path }) => { actionIcon = path; return Promise.resolve(); } },
  cookies: { getAll: async () => [] },
  downloads: {
    cancel: async () => {}, erase: async () => {},
    onCreated: { addListener: (listener) => { onCreated = listener; } },
  },
  contextMenus: {
    removeAll: async () => {}, create: () => {},
    onClicked: { addListener: () => {} },
  },
  runtime: {
    lastError: null,
    sendNativeMessage: (_host, _message, callback) => callback({ type: 'done', message: 'delegated to Hydra.app' }),
    onInstalled: { addListener: (listener) => { onInstalled = listener; } },
    onStartup: { addListener: () => {} },
  },
  storage: {
    local: {
      get: async (key) => ({ [key]: local[key] }),
      set: async (value) => Object.assign(local, value),
    },
    onChanged: { addListener: (listener) => { onStorageChanged = listener; } },
  },
};

const context = {
  chrome, console, navigator: { userAgent: 'Hydra test' }, URL,
  HydraRules: {
    loadSettings: async () => ({ connections: 8, contextMenuEnabled: true, enabled: true }),
    shouldIntercept: () => true,
  },
  HydraNative: {
    send: async () => ({ type: 'done', message: 'delegated to Hydra.app' }),
  },
};
vm.createContext(context);
vm.runInContext(fs.readFileSync('extension/src/background.js', 'utf8'), context);

(async () => {
  await onInstalled();
  assert.equal(actionIcon[16], 'icons/icon16.png');
  onStorageChanged({ settings: { newValue: { enabled: false, contextMenuEnabled: true } } }, 'sync');
  assert.equal(actionIcon[16], 'icons/icon16-disabled.png');

  await onCreated({
    id: 1,
    url: 'https://example.com/releases/Hydra.dmg?token=secret',
    filename: '/Users/test/Downloads/Hydra.dmg',
    fileSize: 42_000_000,
    referrer: 'https://example.com/',
  });
  assert.equal(local.transferLog.length, 1);
  assert.equal(local.transferLog[0].filename, 'Hydra.dmg');
  assert.equal(local.transferLog[0].status, 'sent');
  assert.equal(local.transferLog[0].source, 'auto');
  console.log('background transfer log OK');
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
