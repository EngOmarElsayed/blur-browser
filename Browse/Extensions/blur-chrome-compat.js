// Blur-Browser: stand-ins for Chrome extension APIs WebKit doesn't implement,
// so Chrome extensions that touch them at startup keep running.
(() => {
  const event = () => {
    const listeners = new Set();
    return {
      addListener: (fn) => listeners.add(fn),
      removeListener: (fn) => listeners.delete(fn),
      hasListener: (fn) => listeners.has(fn),
      hasListeners: () => listeners.size > 0,
      _dispatch: (...args) => listeners.forEach((fn) => { try { fn(...args); } catch (e) { console.error(e); } }),
    };
  };
  const settled = (value) => (...args) => {
    const callback = typeof args[args.length - 1] === "function" ? args.pop() : null;
    const result = typeof value === "function" ? value(...args) : value;
    if (callback) { queueMicrotask(() => callback(result)); return undefined; }
    return Promise.resolve(result);
  };
  const setting = () => ({
    get: settled({ value: false, levelOfControl: "not_controllable" }),
    set: settled(undefined),
    clear: settled(undefined),
    onChange: event(),
  });

  const shims = {
    notifications: () => ({
      create: settled((id) => (typeof id === "string" ? id : String(Date.now()))),
      update: settled(false), clear: settled(true), getAll: settled({}), getPermissionLevel: settled("granted"),
      onClicked: event(), onClosed: event(), onButtonClicked: event(), onShowSettings: event(), onPermissionLevelChanged: event(),
    }),
    downloads: () => ({
      download: settled(() => { throw new Error("downloads API is not supported in this browser"); }),
      search: settled([]), cancel: settled(undefined), erase: settled([]), open: settled(undefined), show: settled(undefined),
      onCreated: event(), onChanged: event(), onErased: event(), onDeterminingFilename: event(),
    }),
    idle: () => ({
      queryState: settled("active"), setDetectionInterval: () => {}, getAutoLockDelay: settled(0),
      onStateChanged: event(),
    }),
    management: () => {
      const self = () => {
        const manifest = chrome.runtime.getManifest();
        return { id: chrome.runtime.id, name: manifest.name, shortName: manifest.short_name, version: manifest.version,
          enabled: true, installType: "normal", type: "extension", mayDisable: true, offlineEnabled: false,
          permissions: manifest.permissions || [], hostPermissions: manifest.host_permissions || [] };
      };
      return { getSelf: settled(self), getAll: settled(() => [self()]), get: settled(self),
        onInstalled: event(), onUninstalled: event(), onEnabled: event(), onDisabled: event() };
    },
    privacy: () => ({
      services: { passwordSavingEnabled: setting(), autofillEnabled: setting(), autofillAddressEnabled: setting(), autofillCreditCardEnabled: setting() },
      network: { webRTCIPHandlingPolicy: setting(), networkPredictionEnabled: setting() },
      websites: { thirdPartyCookiesAllowed: setting(), hyperlinkAuditingEnabled: setting() },
    }),
  };

  // WebKit's API namespace objects are wrappers that can be garbage-collected
  // and recreated, dropping anything added to them. Keeping a reference to
  // every object we extend keeps our additions alive.
  const keepAlive = (globalThis.__blurChromeCompatKeepAlive ||= []);

  for (const ns of [globalThis.chrome, globalThis.browser]) {
    if (!ns) continue;
    keepAlive.push(ns);
    for (const [name, make] of Object.entries(shims)) {
      if (ns[name] !== undefined) continue;
      try { Object.defineProperty(ns, name, { value: make(), configurable: true, enumerable: true }); }
      catch (e) { console.warn("blur-chrome-compat: could not add", name, e); }
    }
    // chrome.storage.managed (enterprise policy storage) — always empty here.
    if (ns.storage) keepAlive.push(ns.storage);
    if (ns.storage && !ns.storage.managed) {
      try {
        Object.defineProperty(ns.storage, "managed", { configurable: true, enumerable: true, value: {
          get: settled({}), getBytesInUse: settled(0), onChanged: event(),
        } });
      } catch (e) { console.warn("blur-chrome-compat: could not add storage.managed", e); }
    }

    // Events Chrome has on namespaces WebKit does implement.
    const missingEvents = {
      webNavigation: ["onCreatedNavigationTarget", "onReferenceFragmentUpdated", "onHistoryStateUpdated", "onTabReplaced"],
      webRequest: ["onAuthRequired", "onBeforeRedirect", "onResponseStarted", "onErrorOccurred", "onSendHeaders", "onHeadersReceived", "onBeforeSendHeaders", "onCompleted", "onBeforeRequest"],
      runtime: ["onSuspend", "onSuspendCanceled", "onUpdateAvailable", "onRestartRequired", "onConnectExternal", "onMessageExternal", "onUserScriptMessage"],
      tabs: ["onReplaced", "onHighlighted", "onZoomChange", "onAttached", "onDetached", "onMoved"],
      windows: ["onBoundsChanged"],
      contextMenus: ["onClicked"],
      commands: ["onCommand"],
    };
    for (const [api, names] of Object.entries(missingEvents)) {
      const target = ns[api];
      if (!target) continue;
      keepAlive.push(target);
      for (const name of names) {
        if (target[name] !== undefined) continue;
        try { Object.defineProperty(target, name, { value: event(), configurable: true, enumerable: true }); }
        catch (e) { console.warn("blur-chrome-compat: could not add", api + "." + name, e); }
      }
    }
  }
})();
