(function () {
  'use strict';

  const post = (msg) => {
    try { window.webkit.messageHandlers.passwordManager.postMessage(msg); }
    catch (e) { /* channel not available */ }
  };

  const FIELD_ID_ATTR = 'data-bm-field-id';
  const UNIT_ID_ATTR  = 'data-bm-unit-id';

  const uuid = () => {
    if (crypto && crypto.randomUUID) return crypto.randomUUID();
    return 'u-' + Math.random().toString(36).slice(2) + Date.now().toString(36);
  };

  const idFor = (el, attr) => {
    let id = el.getAttribute(attr);
    if (!id) { id = uuid(); el.setAttribute(attr, id); }
    return id;
  };

  // --- Patch history.pushState / replaceState so SPA navigations fire a synthetic event ---

  (function patchHistory() {
    const fire = () => window.dispatchEvent(new CustomEvent('__bm_locationChanged'));
    const orig = { push: history.pushState, replace: history.replaceState };
    history.pushState = function (...args) { const r = orig.push.apply(this, args); fire(); return r; };
    history.replaceState = function (...args) { const r = orig.replace.apply(this, args); fire(); return r; };
    window.addEventListener('popstate', fire);
  })();

  // --- Form unit & field discovery ---

  const isVisible = (el) => {
    const cs = getComputedStyle(el);
    if (cs.display === 'none' || cs.visibility === 'hidden') return false;
    return el.getClientRects().length > 0;
  };

  const findUnit = (passwordEl) => {
    const form = passwordEl.closest('form');
    if (form) return form;
    let node = passwordEl.parentElement;
    while (node && node !== document.body) {
      if (node.querySelectorAll('input').length >= 2) return node;
      node = node.parentElement;
    }
    return passwordEl.parentElement || document.body;
  };

  const findUsernameField = (unit, passwordEl) => {
    const tagged = unit.querySelector('input[autocomplete~="username"], input[autocomplete~="email"]');
    if (tagged) return tagged;

    const candidates = unit.querySelectorAll('input[type="text"], input[type="email"], input[type="tel"], input:not([type])');
    let best = null;
    for (const c of candidates) {
      if (c === passwordEl) break;
      if (c.compareDocumentPosition(passwordEl) & Node.DOCUMENT_POSITION_FOLLOWING) {
        best = c;
      }
    }
    return best;
  };

  const SIGNUP_RE = /sign\s*up|register|create.*account|join/i;
  const CHANGE_RE = /change|update.*password|new.*password|reset.*password/i;

  const classify = (unit) => {
    const pwInputs = unit.querySelectorAll('input[type="password"]');
    const hasNew     = !![...pwInputs].find((p) => /new-password/.test(p.getAttribute('autocomplete') || ''));
    const hasCurrent = !![...pwInputs].find((p) => /current-password/.test(p.getAttribute('autocomplete') || ''));
    if (hasNew && hasCurrent) return 'change_password';
    if (hasNew) return 'signup';
    if (pwInputs.length >= 2) return 'signup';

    const text = (unit.textContent || '').slice(0, 1000);
    const idClass = (unit.id || '') + ' ' + (unit.className || '');
    if (CHANGE_RE.test(text) || CHANGE_RE.test(idClass)) return 'change_password';
    if (SIGNUP_RE.test(text) || SIGNUP_RE.test(idClass)) return 'signup';
    return 'login';
  };

  // Iframe-aware rect: walks up parent windows accumulating offsets so the
  // returned rect is in the TOP document's coordinate space.
  const rectInTopDoc = (el) => {
    const r = el.getBoundingClientRect();
    let x = r.left, y = r.top;
    let win = window;
    while (win !== window.top) {
      try {
        const fe = win.frameElement;
        if (!fe) break;
        const fr = fe.getBoundingClientRect();
        x += fr.left;
        y += fr.top;
        win = win.parent;
      } catch (e) { break; }
    }
    return { x, y, w: r.width, h: r.height };
  };

  const detected = new Map(); // unitId -> { unit, classification, usernameField, passwordField }

  const scan = () => {
    detected.clear();
    const passwords = document.querySelectorAll('input[type="password"]');
    const forms = [];

    for (const pw of passwords) {
      if (!isVisible(pw)) continue;
      const unit = findUnit(pw);
      const unitId = idFor(unit, UNIT_ID_ATTR);
      const username = findUsernameField(unit, pw);
      const classification = classify(unit);
      const fieldId = idFor(pw, FIELD_ID_ATTR);
      const usernameId = username ? idFor(username, FIELD_ID_ATTR) : null;

      detected.set(unitId, { unit, classification, usernameField: username, passwordField: pw });

      forms.push({
        unitId, classification,
        usernameFieldId: usernameId,
        passwordFieldId: fieldId,
        usernameRect: username ? rectInTopDoc(username) : null,
        passwordRect: rectInTopDoc(pw),
      });
    }

    // Standalone username/email detection for multi-step login flows
    // (Google's identifier step, Apple's "Email" step, Microsoft's account step)
    // where the password field lives on a separate document. Without this, the
    // autofill popover never appears on step 1 because no form was detected.
    const alreadyTagged = new Set();
    for (const rec of detected.values()) {
      if (rec.usernameField) alreadyTagged.add(rec.usernameField);
    }
    const standalones = document.querySelectorAll(
      'input[autocomplete~="username"], input[autocomplete~="email"], input[type="email"]'
    );
    for (const un of standalones) {
      if (alreadyTagged.has(un)) continue;
      if (!isVisible(un)) continue;
      const unit = un.closest('form') || un.parentElement || document.body;
      const unitId = idFor(unit, UNIT_ID_ATTR);
      if (detected.has(unitId)) continue; // already a real form unit here
      const fieldId = idFor(un, FIELD_ID_ATTR);
      detected.set(unitId, { unit, classification: 'login', usernameField: un, passwordField: null });
      forms.push({
        unitId, classification: 'login',
        usernameFieldId: fieldId,
        passwordFieldId: null,
        usernameRect: rectInTopDoc(un),
        passwordRect: null,
      });
    }

    post({ kind: 'formsDetected', site: location.hostname, forms });

    // If a freshly-tagged field is already focused (browser auto-focus from
    // page load fired before scan tagged the field, so fieldInfo returned null
    // at that time), announce it now so native can show the autofill popover.
    // Dedupe via lastAnnouncedFocusFieldId so re-scans triggered by DOM
    // mutations after autofill don't re-announce the same focus and re-show
    // the popover we just dismissed.
    const active = document.activeElement;
    if (active instanceof HTMLInputElement) {
      const info = fieldInfo(active);
      if (info && info.fieldId !== lastAnnouncedFocusFieldId) {
        lastAnnouncedFocusFieldId = info.fieldId;
        post({
          kind: 'fieldFocused',
          unitId: info.unitId,
          fieldId: info.fieldId,
          role: info.role,
          rect: rectInTopDoc(active),
        });
      }
    }
  };

  // Tracks the most recently announced focused fieldId so we don't redundantly
  // announce focus on every MutationObserver-triggered scan.
  let lastAnnouncedFocusFieldId = null;

  let scanTimer = null;
  const scheduleScan = () => {
    if (scanTimer) clearTimeout(scanTimer);
    scanTimer = setTimeout(scan, 150);
  };

  const mo = new MutationObserver(scheduleScan);
  mo.observe(document.documentElement, {
    subtree: true, childList: true,
    attributes: true, attributeFilter: ['type', 'autocomplete'],
  });

  // --- Focus / blur / viewport tracking ---

  const fieldInfo = (el) => {
    const fieldId = el.getAttribute(FIELD_ID_ATTR);
    if (!fieldId) return null;
    for (const [unitId, rec] of detected) {
      if (rec.passwordField === el) return { unitId, fieldId, role: 'password' };
      if (rec.usernameField === el) return { unitId, fieldId, role: 'username' };
    }
    return null;
  };

  document.addEventListener('focusin', (ev) => {
    const target = ev.target;
    if (!(target instanceof HTMLInputElement)) return;
    const info = fieldInfo(target);
    if (!info) return;
    lastAnnouncedFocusFieldId = info.fieldId;
    post({
      kind: 'fieldFocused',
      unitId: info.unitId,
      fieldId: info.fieldId,
      role: info.role,
      rect: rectInTopDoc(target),
    });
  }, true);

  document.addEventListener('focusout', (ev) => {
    const target = ev.target;
    if (!(target instanceof HTMLInputElement)) return;
    const info = fieldInfo(target);
    if (!info) return;
    if (lastAnnouncedFocusFieldId === info.fieldId) {
      lastAnnouncedFocusFieldId = null;
    }
    post({ kind: 'fieldBlurred', fieldId: info.fieldId });
  }, true);

  let viewportTimer = null;
  const onViewportChange = () => {
    if (viewportTimer) return;
    viewportTimer = setTimeout(() => {
      viewportTimer = null;
      post({ kind: 'viewportChanged' });
    }, 50);
  };
  window.addEventListener('scroll', onViewportChange, true);
  window.addEventListener('resize', onViewportChange);

  // --- Submission tracking + success watcher ---

  const SUBMIT_BUTTON_RE = /log\s*in|sign\s*in|continue|next|submit|sign\s*up|register|create.*account|update.*password|change.*password|verify|^ok$/i;

  const isSubmitLikeButton = (button) => {
    if (!button) return false;
    if (button.tagName === 'BUTTON' && (button.type === 'submit' || !button.type)) return true;
    if (button.tagName === 'INPUT' && button.type === 'submit') return true;
    const label = (button.textContent || '') + ' ' + (button.getAttribute('aria-label') || '');
    return SUBMIT_BUTTON_RE.test(label);
  };

  const isSubmitButton = (el, unit) => {
    if (!el) return false;
    // Clicks often hit inner spans/svgs/icons. Walk up to the nearest button-like
    // ancestor before classifying.
    const button = (el.closest && el.closest('button, [role="button"], input[type="submit"]')) || null;
    if (!button) return false;
    if (!isSubmitLikeButton(button)) return false;
    // Strict association: button is inside the unit's DOM tree OR linked via the
    // HTML5 form="..." attribute (HTMLButtonElement.form / HTMLInputElement.form).
    if (unit.contains(button) || (button.form && button.form === unit)) return true;
    // Permissive fallback: Apple's idmsa places the Sign In button outside the
    // <form> in the DOM and doesn't use the form="..." attribute. Trust the
    // click as a submission of this unit if (a) the unit has a password field
    // and (b) that field has a non-empty value at click time.
    const pwField = unit.querySelector('input[type="password"]');
    return !!(pwField && pwField.value);
  };

  // Multi-step login flows (Google, Apple, Microsoft) ask for the username on
  // one page, then the password on a separate document where the username
  // is no longer an input. Persist the most recent username typed on this
  // origin via sessionStorage so we can recover it at password-submit time.
  const USERNAME_STORAGE_KEY = '__bm_recentUsername';
  const rememberUsername = (value) => {
    if (!value) return;
    try { sessionStorage.setItem(USERNAME_STORAGE_KEY, value); } catch (e) {}
  };
  const recallUsername = () => {
    try { return sessionStorage.getItem(USERNAME_STORAGE_KEY) || ''; } catch (e) { return ''; }
  };

  // Watch any username/email-like input — even on pages with no password field
  // (e.g. Google's identifier step) — and stash its value as the user types.
  document.addEventListener('input', (ev) => {
    const t = ev.target;
    if (!(t instanceof HTMLInputElement)) return;
    const auto = (t.getAttribute('autocomplete') || '').toLowerCase();
    if (t.type === 'email' ||
        auto.includes('username') ||
        auto.includes('email')) {
      rememberUsername(t.value);
    }
  }, true);

  const captureSubmission = (rec) => {
    let username = rec.usernameField ? rec.usernameField.value : '';
    const password = rec.passwordField ? rec.passwordField.value : '';
    if (!password) return;
    if (!username) username = recallUsername();
    post({
      kind: 'formSubmitted',
      unitId: rec.unit.getAttribute(UNIT_ID_ATTR),
      classification: rec.classification,
      username, password,
    });
    watchForSuccess(rec);
  };

  document.addEventListener('submit', (ev) => {
    for (const rec of detected.values()) {
      if (rec.unit === ev.target || rec.unit.contains(ev.target)) {
        captureSubmission(rec);
        return;
      }
    }
  }, true);

  document.addEventListener('click', (ev) => {
    for (const rec of detected.values()) {
      if (isSubmitButton(ev.target, rec.unit)) {
        // Defer slightly so the form's own click handlers see current values first.
        setTimeout(() => captureSubmission(rec), 0);
        return;
      }
    }
  }, true);

  const watchForSuccess = (rec) => {
    const unitId = rec.unit.getAttribute(UNIT_ID_ATTR);
    const passwordEl = rec.passwordField;
    let resolved = false;

    const resolve = (kind) => {
      if (resolved) return;
      resolved = true;
      cleanup();
      post({ kind, unitId });
    };

    const onLocChange = () => resolve('loginLikelySucceeded');
    const onUnload   = () => resolve('loginLikelySucceeded');

    const checkPasswordGone = () => {
      if (!passwordEl.isConnected) return resolve('loginLikelySucceeded');
      const cs = getComputedStyle(passwordEl);
      if (cs.display === 'none' || cs.visibility === 'hidden') return resolve('loginLikelySucceeded');
      if (passwordEl.value === '' && document.activeElement !== passwordEl) {
        return resolve('loginLikelySucceeded');
      }
    };

    const tickInterval = setInterval(checkPasswordGone, 200);
    window.addEventListener('__bm_locationChanged', onLocChange);
    window.addEventListener('beforeunload', onUnload);

    const timeout = setTimeout(() => resolve('loginInconclusive'), 3000);

    function cleanup() {
      clearInterval(tickInterval);
      clearTimeout(timeout);
      window.removeEventListener('__bm_locationChanged', onLocChange);
      window.removeEventListener('beforeunload', onUnload);
    }
  };

  // --- Public API for native ---

  const findFieldById = (id) => document.querySelector('[' + FIELD_ID_ATTR + '="' + id + '"]');

  const fillElement = (el, value) => {
    if (!el) return;
    // Use the native value setter so React/Vue see the change.
    const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
    setter.call(el, value);
    el.dispatchEvent(new Event('input',  { bubbles: true }));
    el.dispatchEvent(new Event('change', { bubbles: true }));
    el.dispatchEvent(new KeyboardEvent('keydown', { bubbles: true }));
    el.dispatchEvent(new KeyboardEvent('keyup',   { bubbles: true }));
  };

  // Recursively walk same-origin iframes to find a frame whose
  // __BrowsePasswordManager has the requested field. Returns the inner namespace
  // object (or null). Cross-origin iframes throw on contentWindow access; we skip.
  const findInnerNamespaceFor = (fieldIds) => {
    const iframes = document.querySelectorAll('iframe');
    for (const frame of iframes) {
      try {
        const inner = frame.contentWindow && frame.contentWindow.__BrowsePasswordManager;
        if (!inner) continue;
        // The inner frame's __findFieldById is internal; we instead just call the
        // inner frame's fillField/fillCredential which runs its own search and
        // recurses if needed. Returning the inner namespace lets the caller invoke.
        for (const id of fieldIds) {
          if (id && frame.contentDocument && frame.contentDocument.querySelector('[' + FIELD_ID_ATTR + '="' + id + '"]')) {
            return inner;
          }
        }
      } catch (e) { /* cross-origin: skip */ }
    }
    return null;
  };

  const namespace = {
    fillField: function ({ fieldId, value }) {
      const local = findFieldById(fieldId);
      if (local) { fillElement(local, value); return; }
      const inner = findInnerNamespaceFor([fieldId]);
      if (inner && typeof inner.fillField === 'function') {
        inner.fillField({ fieldId, value });
      }
    },
    fillCredential: function ({ usernameFieldId, username, passwordFieldId, password }) {
      const u = findFieldById(usernameFieldId);
      const p = findFieldById(passwordFieldId);
      if (u || p) {
        fillElement(u, username);
        fillElement(p, password);
        return;
      }
      // Delegate to a same-origin iframe whose namespace owns these field ids
      // (Apple's idmsa form lives in an iframe; the main frame's evaluateJavaScript
      // call has to recurse to find the right realm).
      const inner = findInnerNamespaceFor([usernameFieldId, passwordFieldId]);
      if (inner && typeof inner.fillCredential === 'function') {
        inner.fillCredential({ usernameFieldId, username, passwordFieldId, password });
      }
    },
    rescan: scan,
  };
  Object.defineProperty(window, '__BrowsePasswordManager', {
    value: namespace, writable: false, configurable: false,
  });

  // --- Boot ---

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', scan, { once: true });
  } else {
    scan();
  }
  post({ kind: 'scriptReady', site: location.hostname });
})();
