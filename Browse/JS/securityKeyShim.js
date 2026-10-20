// WebAuthn for USB security keys, without Apple's passkey entitlement.
//
// Injected at documentStart into every frame (page world) only when the app
// lacks com.apple.developer.web-browser.public-key-credential, so WebKit's own
// WebAuthn is off. navigator.credentials.create()/get() with `publicKey` go
// to the native blurSecurityKey handler, which talks CTAP2 to the key. The
// native side takes the origin from WebKit, never from this script.
(function () {
  'use strict';

  if (!window.isSecureContext) return;
  const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.blurSecurityKey;
  if (!handler) return;
  const postMessage = handler.postMessage.bind(handler);

  // --- Helpers -------------------------------------------------------------

  const bytesOf = (source, name) => {
    if (source instanceof ArrayBuffer) return new Uint8Array(source);
    if (ArrayBuffer.isView(source)) return new Uint8Array(source.buffer, source.byteOffset, source.byteLength);
    throw new TypeError(`${name} must be a BufferSource.`);
  };

  const toB64 = (source, name) => {
    const bytes = bytesOf(source, name);
    let binary = '';
    for (let i = 0; i < bytes.length; i += 0x8000) {
      binary += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
    }
    return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  };

  const fromB64 = (string) => {
    let s = String(string).replace(/-/g, '+').replace(/_/g, '/');
    while (s.length % 4) s += '=';
    const binary = atob(s);
    const out = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) out[i] = binary.charCodeAt(i);
    return out.buffer;
  };

  const newID = () => (crypto.randomUUID ? crypto.randomUUID() : String(Math.random()).slice(2) + Date.now());

  const domError = (name, message) => (name === 'TypeError' ? new TypeError(message) : new DOMException(message, name));
  const abortReason = (signal) => (signal.reason !== undefined ? signal.reason : new DOMException('The operation was aborted.', 'AbortError'));

  // Transient user activation. navigator.userActivation where WebKit has
  // it, plus our own record of recent input (sites often fetch a challenge
  // from the server between the click and the call).
  const activationGetter = (() => {
    try {
      const desc = typeof UserActivation !== 'undefined' && Object.getOwnPropertyDescriptor(UserActivation.prototype, 'isActive');
      const ua = navigator.userActivation;
      return desc && ua ? () => desc.get.call(ua) : () => false;
    } catch (e) { return () => false; }
  })();
  let lastInput = 0;
  for (const type of ['pointerup', 'mouseup', 'keydown', 'touchend', 'click']) {
    window.addEventListener(type, (e) => { if (e.isTrusted) lastInput = Date.now(); }, { capture: true, passive: true });
  }
  const hasActivation = () => {
    try { if (activationGetter()) return true; } catch (e) {}
    return Date.now() - lastInput < 10000;
  };

  const descriptors = (list, name) => (list || []).map((d) => ({
    type: d.type, id: toB64(d.id, `${name}.id`), transports: Array.isArray(d.transports) ? d.transports.slice() : undefined,
  }));

  const extensionInputs = (ext) => {
    if (!ext) return undefined;
    const out = {};
    for (const key of ['credProps', 'credentialProtectionPolicy', 'enforceCredentialProtectionPolicy', 'appid']) {
      if (ext[key] !== undefined) out[key] = ext[key];
    }
    return out;
  };

  const serializeCreation = (o) => {
    if (!o || typeof o !== 'object') throw new TypeError('publicKey options are required.');
    if (!o.rp) throw new TypeError('rp is required.');
    if (!o.user) throw new TypeError('user is required.');
    if (o.challenge === undefined) throw new TypeError('challenge is required.');
    const sel = o.authenticatorSelection;
    return {
      rp: { id: o.rp.id, name: o.rp.name },
      user: { id: toB64(o.user.id, 'user.id'), name: o.user.name, displayName: o.user.displayName },
      challenge: toB64(o.challenge, 'challenge'),
      pubKeyCredParams: (o.pubKeyCredParams || []).map((p) => ({ type: p.type, alg: p.alg })),
      timeout: o.timeout,
      excludeCredentials: descriptors(o.excludeCredentials, 'excludeCredentials'),
      authenticatorSelection: sel ? {
        authenticatorAttachment: sel.authenticatorAttachment,
        residentKey: sel.residentKey,
        requireResidentKey: sel.requireResidentKey,
        userVerification: sel.userVerification,
      } : undefined,
      attestation: o.attestation,
      extensions: extensionInputs(o.extensions),
    };
  };

  const serializeRequest = (o) => {
    if (!o || typeof o !== 'object') throw new TypeError('publicKey options are required.');
    if (o.challenge === undefined) throw new TypeError('challenge is required.');
    return {
      rpId: o.rpId,
      challenge: toB64(o.challenge, 'challenge'),
      timeout: o.timeout,
      allowCredentials: descriptors(o.allowCredentials, 'allowCredentials'),
      userVerification: o.userVerification,
      extensions: extensionInputs(o.extensions),
    };
  };

  // --- Interfaces ----------------------------------------------------------

  const slots = new WeakMap();
  const slot = (self) => {
    const s = slots.get(self);
    if (!s) throw new TypeError('Illegal invocation');
    return s;
  };
  const illegal = function () { throw new TypeError('Illegal constructor'); };

  const isNative = (fn) => {
    try { return typeof fn === 'function' && /\[native code\]\s*\}\s*$/.test(Function.prototype.toString.call(fn)); }
    catch (e) { return false; }
  };

  const findDescriptor = (proto, key) => {
    for (let p = proto; p; p = Object.getPrototypeOf(p)) {
      const d = Object.getOwnPropertyDescriptor(p, key);
      if (d) return d;
    }
    return undefined;
  };

  // Defines a WebAuthn interface, or, when WebKit already has it (WebAuthn
  // left on for extensions such as 1Password), wraps its members so our
  // objects work and WebKit's (or an extension's) objects keep theirs.
  // `instanceof PublicKeyCredential` then holds for both.
  const defineInterface = (name, parent, members) => {
    const existing = typeof window[name] === 'function' ? window[name] : null;
    if (existing) {
      for (const [key, value] of Object.entries(members)) {
        const original = findDescriptor(existing.prototype, key);
        if (typeof value === 'function') {
          const nativeFn = original && original.value;
          Object.defineProperty(existing.prototype, key, {
            value: function (...args) {
              if (slots.has(this)) return value.apply(this, args);
              if (typeof nativeFn === 'function') return nativeFn.apply(this, args);
              throw new TypeError('Illegal invocation');
            },
            writable: true, configurable: true,
          });
        } else {
          const nativeGet = original && original.get;
          Object.defineProperty(existing.prototype, key, {
            get: function () {
              if (slots.has(this)) return value.get.call(this);
              if (nativeGet) return nativeGet.call(this);
              throw new TypeError('Illegal invocation');
            },
            enumerable: true, configurable: true,
          });
        }
      }
      return existing;
    }
    const ctor = { [name]: function () { illegal(); } }[name];
    ctor.prototype = Object.create(parent ? parent.prototype : Object.prototype);
    Object.defineProperty(ctor.prototype, 'constructor', { value: ctor, writable: true, configurable: true });
    Object.defineProperty(ctor.prototype, Symbol.toStringTag, { value: name, configurable: true });
    if (parent) Object.setPrototypeOf(ctor, parent);
    for (const [key, value] of Object.entries(members)) {
      if (typeof value === 'function') {
        Object.defineProperty(ctor.prototype, key, { value, writable: true, configurable: true });
      } else {
        Object.defineProperty(ctor.prototype, key, { get: value.get, enumerable: true, configurable: true });
      }
    }
    Object.defineProperty(window, name, { value: ctor, writable: true, configurable: true });
    return ctor;
  };

  const get = (fn) => ({ get() { return fn(slot(this)); } });

  const BaseCredential = typeof window.Credential === 'function' ? window.Credential
    : defineInterface('Credential', null, { id: get((s) => s.id), type: get(() => 'public-key') });

  const AuthenticatorResponse = defineInterface('AuthenticatorResponse', null, {
    clientDataJSON: get((s) => s.clientDataJSON),
  });

  const AuthenticatorAttestationResponse = defineInterface('AuthenticatorAttestationResponse', AuthenticatorResponse, {
    attestationObject: get((s) => s.attestationObject),
    getTransports() { return slot(this).transports.slice(); },
    getAuthenticatorData() { return slot(this).authenticatorData.slice(0); },
    getPublicKey() { const k = slot(this).publicKey; return k ? k.slice(0) : null; },
    getPublicKeyAlgorithm() { return slot(this).publicKeyAlgorithm; },
  });

  const AuthenticatorAssertionResponse = defineInterface('AuthenticatorAssertionResponse', AuthenticatorResponse, {
    authenticatorData: get((s) => s.authenticatorData),
    signature: get((s) => s.signature),
    userHandle: get((s) => s.userHandle),
  });

  const responseJSON = (s) => {
    const out = { clientDataJSON: s.json.clientDataJSON };
    for (const key of ['attestationObject', 'authenticatorData', 'transports', 'publicKey', 'publicKeyAlgorithm', 'signature', 'userHandle']) {
      if (s.json[key] !== undefined) out[key] = s.json[key];
    }
    return out;
  };

  const PublicKeyCredential = defineInterface('PublicKeyCredential', BaseCredential, {
    id: get((s) => s.id),
    type: get(() => 'public-key'),
    rawId: get((s) => s.rawId),
    response: get((s) => s.response),
    authenticatorAttachment: get((s) => s.authenticatorAttachment),
    getClientExtensionResults() { return JSON.parse(JSON.stringify(slot(this).extensions)); },
    toJSON() {
      const s = slot(this);
      return {
        id: s.id, rawId: s.id, type: 'public-key', authenticatorAttachment: s.authenticatorAttachment,
        clientExtensionResults: JSON.parse(JSON.stringify(s.extensions)),
        response: responseJSON(slots.get(s.response)),
      };
    },
  });

  const statics = {
    isUserVerifyingPlatformAuthenticatorAvailable: () => Promise.resolve(false),
    isConditionalMediationAvailable: () => Promise.resolve(false),
    getClientCapabilities: () => Promise.resolve({
      conditionalCreate: false, conditionalGet: false, hybridTransport: false,
      passkeyPlatformAuthenticator: false, userVerifyingPlatformAuthenticator: false,
      relatedOrigins: false, signalAllAcceptedCredentials: false, signalCurrentUserDetails: false,
      signalUnknownCredential: false, 'extension:appid': true, 'extension:credProps': true,
      'extension:credProtect': true,
    }),
    signalUnknownCredential: () => Promise.resolve(),
    signalAllAcceptedCredentials: () => Promise.resolve(),
    signalCurrentUserDetails: () => Promise.resolve(),
    parseCreationOptionsFromJSON(json) {
      const o = Object.assign({}, json);
      o.challenge = fromB64(json.challenge);
      o.user = Object.assign({}, json.user, { id: fromB64(json.user.id) });
      if (json.excludeCredentials) o.excludeCredentials = json.excludeCredentials.map((d) => Object.assign({}, d, { id: fromB64(d.id) }));
      return o;
    },
    parseRequestOptionsFromJSON(json) {
      const o = Object.assign({}, json);
      o.challenge = fromB64(json.challenge);
      if (json.allowCredentials) o.allowCredentials = json.allowCredentials.map((d) => Object.assign({}, d, { id: fromB64(d.id) }));
      return o;
    },
  };
  // WebKit's versions would describe the platform authenticator we can't
  // reach; an extension's replacement (non-native) is left alone.
  for (const [key, value] of Object.entries(statics)) {
    const current = PublicKeyCredential[key];
    if (current === undefined || isNative(current)) {
      Object.defineProperty(PublicKeyCredential, key, { value, writable: true, configurable: true });
    }
  }

  const makeCredential = (data, isCreate) => {
    const r = data.response;
    const response = Object.create((isCreate ? AuthenticatorAttestationResponse : AuthenticatorAssertionResponse).prototype);
    const responseSlot = { clientDataJSON: fromB64(r.clientDataJSON), json: r };
    if (isCreate) {
      Object.assign(responseSlot, {
        attestationObject: fromB64(r.attestationObject),
        authenticatorData: fromB64(r.authenticatorData),
        transports: r.transports || [],
        publicKey: r.publicKey ? fromB64(r.publicKey) : null,
        publicKeyAlgorithm: r.publicKeyAlgorithm,
      });
    } else {
      Object.assign(responseSlot, {
        authenticatorData: fromB64(r.authenticatorData),
        signature: fromB64(r.signature),
        userHandle: r.userHandle ? fromB64(r.userHandle) : null,
      });
    }
    slots.set(response, responseSlot);
    const credential = Object.create(PublicKeyCredential.prototype);
    slots.set(credential, {
      id: data.id, rawId: fromB64(data.rawId), response,
      authenticatorAttachment: data.authenticatorAttachment || null,
      extensions: data.clientExtensionResults || {},
    });
    return credential;
  };

  // --- navigator.credentials --------------------------------------------

  const call = (op, options, isCreate) => {
    const signal = options.signal;
    if (signal && signal.aborted) return Promise.reject(abortReason(signal));
    let serialized;
    try {
      serialized = isCreate ? serializeCreation(options.publicKey) : serializeRequest(options.publicKey);
    } catch (e) {
      return Promise.reject(e);
    }
    const id = newID();
    return new Promise((resolve, reject) => {
      let settled = false;
      const onAbort = () => {
        if (settled) return;
        settled = true;
        postMessage({ op: 'cancel', id }).catch(() => {});
        reject(abortReason(signal));
      };
      if (signal) signal.addEventListener('abort', onAbort, { once: true });
      const message = JSON.parse(JSON.stringify({ op, id, options: serialized, activation: hasActivation() }));
      postMessage(message).then((reply) => {
        if (settled) return;
        settled = true;
        if (signal) signal.removeEventListener('abort', onAbort);
        if (reply && reply.ok) {
          resolve(makeCredential(reply.ok, isCreate));
        } else {
          const e = (reply && reply.error) || {};
          reject(domError(e.name || 'NotAllowedError', e.message || 'The operation either timed out or was not allowed.'));
        }
      }, () => {
        if (settled) return;
        settled = true;
        reject(domError('NotAllowedError', 'The operation either timed out or was not allowed.'));
      });
    });
  };

  const native = navigator.credentials;
  const nativeCreate = native && native.create ? native.create.bind(native) : null;
  const nativeGet = native && native.get ? native.get.bind(native) : null;

  const methods = {
    create(options) {
      if (options && options.publicKey) return call('create', options, true);
      if (nativeCreate) return nativeCreate(options);
      return Promise.reject(new DOMException('Only publicKey credentials are supported.', 'NotSupportedError'));
    },
    get(options) {
      if (options && options.publicKey) {
        if (options.mediation === 'conditional') {
          // No autofill UI for security keys: stay pending until aborted.
          return new Promise((_, reject) => {
            const signal = options.signal;
            if (signal) {
              if (signal.aborted) reject(abortReason(signal));
              signal.addEventListener('abort', () => reject(abortReason(signal)), { once: true });
            }
          });
        }
        return call('get', options, false);
      }
      if (nativeGet) return nativeGet(options);
      return Promise.reject(new DOMException('Only publicKey credentials are supported.', 'NotSupportedError'));
    },
    store() { return Promise.reject(new DOMException('Not supported.', 'NotSupportedError')); },
    preventSilentAccess() { return Promise.resolve(); },
  };

  if (native) {
    // Wrap WebKit's methods on the prototype. Anything that wraps
    // navigator.credentials later (1Password) captures these and falls back
    // to them when it declines. If an extension already replaced them, leave
    // its wrapper alone.
    const proto = Object.getPrototypeOf(native);
    for (const key of ['create', 'get']) {
      if (!isNative(proto[key]) || Object.prototype.hasOwnProperty.call(native, key)) continue;
      Object.defineProperty(proto, key, { value: methods[key], writable: true, configurable: true, enumerable: true });
    }
  } else {
    const CredentialsContainer = typeof window.CredentialsContainer === 'function' ? window.CredentialsContainer
      : defineInterface('CredentialsContainer', null, {});
    const container = Object.create(CredentialsContainer.prototype);
    for (const [key, value] of Object.entries(methods)) {
      Object.defineProperty(CredentialsContainer.prototype, key, { value, writable: true, configurable: true, enumerable: true });
    }
    Object.defineProperty(Navigator.prototype, 'credentials', {
      get() { return container; }, enumerable: true, configurable: true,
    });
  }
})();
