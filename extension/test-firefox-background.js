const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

let onInstalled;
let menu;
let icon;
const browser = {
  action: { setIcon: ({ path }) => { icon = path; return Promise.resolve(); } },
  contextMenus: {
    removeAll: (...args) => {
      assert.equal(args.length, 0, 'Firefox removeAll() is Promise-only');
      menu = null;
      return Promise.resolve();
    },
    create: (item) => { menu = item; return item.id; },
    onClicked: { addListener: () => {} },
  },
  cookies: { getAll: async () => [] },
  downloads: { onCreated: { addListener: () => {} } },
  permissions: { getAll: async () => ({ data_collection: [] }) },
  runtime: {
    onInstalled: { addListener: (listener) => { onInstalled = listener; } },
    onStartup: { addListener: () => {} },
  },
  storage: {
    local: { get: async () => ({}), set: async () => {} },
    onChanged: { addListener: () => {} },
  },
};
const context = {
  browser, console, navigator: { userAgent: 'Firefox test' }, URL,
  HydraNative: { send: async () => ({ type: 'status', connected: true }) },
  HydraRules: {
    loadSettings: async () => ({ enabled: false, contextMenuEnabled: true }),
    shouldIntercept: () => true,
  },
};
vm.createContext(context);
vm.runInContext(fs.readFileSync('extension/src/background.js', 'utf8'), context);

(async () => {
  await onInstalled();
  assert.equal(menu.id, 'hydra-download');
  assert.equal(icon[16], 'icons/icon16-disabled.png');
  console.log('Firefox background API compatibility OK');
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
