const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const source = fs.readFileSync('extension/src/native.js', 'utf8');

async function testChrome() {
  const chrome = {
    runtime: {
      lastError: null,
      sendNativeMessage: (host, message, callback) => {
        assert.equal(host, 'com.hydra.host');
        callback({ type: message.type });
      },
    },
  };
  const context = { chrome, Promise };
  vm.createContext(context);
  vm.runInContext(source, context);
  assert.equal((await context.HydraNative.send({ type: 'ping' })).type, 'ping');
}

async function testFirefox() {
  const browser = {
    runtime: {
      sendNativeMessage: (...args) => {
        assert.equal(args.length, 2, 'Firefox browser.* must not receive a Chrome callback');
        return Promise.resolve({ type: args[1].type });
      },
    },
  };
  const context = { browser, Promise };
  vm.createContext(context);
  vm.runInContext(source, context);
  assert.equal((await context.HydraNative.send({ type: 'openApp' })).type, 'openApp');
  browser.runtime.sendNativeMessage = () => Promise.reject(new Error('host unavailable'));
  assert.equal(await context.HydraNative.send({ type: 'ping' }), null);
}

Promise.all([testChrome(), testFirefox()]).then(() => {
  console.log('Chrome and Firefox native messaging OK');
}).catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
