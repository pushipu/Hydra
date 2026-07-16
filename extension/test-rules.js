const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

let stored;
let onChanged;
const browser = {
  storage: {
    local: {
      get: async () => ({ settings: stored }),
      set: async ({ settings }) => { stored = settings; },
    },
    onChanged: { addListener: (listener) => { onChanged = listener; } },
  },
};
const context = {
  browser, URL, Date,
  HydraNative: {
    send: async (message) => message.type === 'getSettings'
      ? { type: 'settings', autoIntercept: true, threadsPerFile: 8, minSizeBytes: 0, fileTypes: [] }
      : { type: 'done' },
  },
};
vm.createContext(context);
vm.runInContext(fs.readFileSync('extension/src/rules.js', 'utf8'), context);

(async () => {
  const firstRun = await context.HydraRules.loadSettings();
  assert.equal(firstRun.privacyConsent, false);
  assert.equal(firstRun.enabled, false, 'app settings must not bypass browser consent');
  assert.equal(context.HydraRules.shouldIntercept(firstRun, {
    url: 'https://example.com/file.dmg', fileSizeBytes: 42_000_000,
  }), false);

  await context.HydraRules.saveSettings({ ...firstRun, privacyConsent: true, enabled: true });
  onChanged({ settings: { newValue: stored } }, 'local');
  const accepted = await context.HydraRules.loadSettings();
  assert.equal(context.HydraRules.shouldIntercept(accepted, {
    url: 'https://example.com/file.dmg', fileSizeBytes: 42_000_000,
  }), true);
  console.log('explicit local-data consent OK');
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
