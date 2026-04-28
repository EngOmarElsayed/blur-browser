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

  const SUBMIT_BUTTON_RE = /log\s*in|sign\s*in|continue|submit|sign\s*up|register|create.*account|update.*password|change.*password/i;

  const isSubmitButton = (el, unit) => {
    if (!el) return false;
    if (el.tagName === 'BUTTON' && (el.type === 'submit' || !el.type)) return unit.contains(el);
    if (el.tagName === 'INPUT' && el.type === 'submit') return unit.contains(el);
    if (unit.contains(el) && (el.tagName === 'BUTTON' || el.getAttribute('role') === 'button')) {
      return SUBMIT_BUTTON_RE.test(el.textContent || '');
    }
    return false;
  };

  const captureSubmission = (rec) => {
    const username = rec.usernameField ? rec.usernameField.value : '';
    const password = rec.passwordField ? rec.passwordField.value : '';
    if (!password) return;
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

  const namespace = {
    fillField: function ({ fieldId, value }) {
      fillElement(findFieldById(fieldId), value);
    },
    fillCredential: function ({ usernameFieldId, username, passwordFieldId, password }) {
      fillElement(findFieldById(usernameFieldId), username);
      fillElement(findFieldById(passwordFieldId), password);
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
