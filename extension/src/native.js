// Единый Promise-интерфейс native messaging для browser.* (Firefox)
// и callback-интерфейса chrome.*.
(function (global) {
  const HOST = 'com.hydra.host';
  const api = typeof browser !== 'undefined' ? browser : chrome;

  function send(message) {
    if (typeof browser !== 'undefined') {
      return api.runtime.sendNativeMessage(HOST, message).catch(() => null);
    }
    return new Promise((resolve) => {
      try {
        api.runtime.sendNativeMessage(HOST, message, (response) => {
          resolve(api.runtime.lastError ? null : (response || null));
        });
      } catch { resolve(null); }
    });
  }

  global.HydraNative = { send };
})(typeof self !== 'undefined' ? self : this);
