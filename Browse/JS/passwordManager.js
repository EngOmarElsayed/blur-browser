(function () {
  'use strict';

  const post = (msg) => {
    try {
      window.webkit.messageHandlers.passwordManager.postMessage(msg);
    } catch (e) {
      // Channel not available (e.g., about:blank during early load); ignore.
    }
  };

  const namespace = {
    fillField: function (_payload) { /* implemented in Round 3 */ },
    fillCredential: function (_payload) { /* implemented in Round 3 */ },
    rescan: function () { /* implemented in Round 3 */ },
  };
  Object.defineProperty(window, '__BrowsePasswordManager', {
    value: namespace, writable: false, configurable: false,
  });

  post({ kind: 'scriptReady', site: location.hostname });
})();
