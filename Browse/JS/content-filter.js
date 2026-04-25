// content-filter.js — NSFW image + video detection
// Injected at documentStart (early hide) and documentEnd (scanner + video)
// Works in main frame AND iframes

(function() {
    'use strict';
    if (window.__scaEarly) return;
    window.__scaEarly = true;

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // PHASE 1: Early Hide (runs immediately at documentStart)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    var style = document.createElement('style');
    style.id = '__sca-hide';
    // Pre-classification placeholder: heavy blur so the raw pixels never
    // flash — including inside lightboxes where a fresh <img> DOM node
    // is created on tap. We gate on `data-sca-safe` (set only after the
    // classifier says it's safe) rather than `data-sca-done` so cloned
    // DOM nodes don't accidentally inherit an "unhide" signal.
    style.textContent =
        'img:not([data-sca-safe]) {' +
        '  filter: blur(60px) !important;' +
        '  transform: scale(1.6) !important;' +
        '  transform-origin: 50% 50% !important;' +
        '  clip-path: inset(0) !important;' +
        '  transition: filter 0.15s ease, transform 0.15s ease !important;' +
        '  -webkit-user-drag: none !important;' +
        '  user-select: none !important;' +
        '  -webkit-user-select: none !important;' +
        '}';
    (document.head || document.documentElement).appendChild(style);

    function hideEl(el) {
        if (el.__scaH) return;
        el.__scaH = true;
        var w = parseInt(el.getAttribute('width')) || 0;
        var h = parseInt(el.getAttribute('height')) || 0;
        if ((w > 0 && w < 40) || (h > 0 && h < 40)) return;
        if (el.nodeName !== 'IMG') {
            el.style.opacity = '0';
            el.style.transition = 'opacity 0.15s ease';
        } else if (!el.hasAttribute('data-sca-safe')) {
            // Set inline !important blur immediately on insertion so the raw
            // pixels cannot paint even for one frame — the global stylesheet
            // rule can be outraced by Twitter's lightbox if it forces sync
            // layout between DOM insertion and our MutationObserver callback.
            el.style.setProperty('filter', 'blur(60px)', 'important');
            el.style.setProperty('transform', 'scale(1.6)', 'important');
            el.style.setProperty('transform-origin', '50% 50%', 'important');
            el.style.setProperty('clip-path', 'inset(0)', 'important');
            // Block dragging the original (unblurred) source out of the page.
            // CSS filter is purely cosmetic — without this, dragging the <img>
            // to the desktop would write the raw image file.
            el.setAttribute('draggable', 'false');
        }
        el.__scaTimer = setTimeout(function() {
            if (!el.__scaDone) {
                el.setAttribute('data-sca-done', '1');
                el.setAttribute('data-sca-safe', '1');
                el.style.removeProperty('filter');
                el.style.removeProperty('transform');
                el.style.removeProperty('transform-origin');
                el.style.removeProperty('clip-path');
                el.style.opacity = '1';
                el.__scaDone = true;
            }
        }, 3000);
    }

    function rehideEl(el) {
        el.removeAttribute('data-sca-done');
        el.removeAttribute('data-sca-safe');
        if (el.dataset && el.dataset.sensitiveId && window.__scaSentIds) {
            window.__scaSentIds.delete(el.dataset.sensitiveId);
        }
        delete el.dataset.sensitiveId;
        el.__scaH = false;
        el.__scaDone = false;
        el.__scaSent = false;
        el.__scaHook = false;
        hideEl(el);
    }

    new MutationObserver(function(muts) {
        for (var i = 0; i < muts.length; i++) {
            var mut = muts[i];
            if (mut.type === 'attributes' && mut.attributeName === 'src' && mut.target.nodeName === 'IMG') {
                var img = mut.target;
                var newSrc = img.src || '';
                if ((img.__scaDone || img.__scaSent) && !newSrc.startsWith('data:') && !newSrc.startsWith('blob:') && newSrc.length > 0) {
                    rehideEl(img);
                    if (window.__scaHookLoad) window.__scaHookLoad(img);
                }
                continue;
            }
            var added = mut.addedNodes;
            for (var j = 0; j < added.length; j++) {
                var n = added[j];
                if (n.nodeType !== 1) continue;
                if (n.nodeName === 'IMG') hideEl(n);
                if (n.style && n.style.backgroundImage && n.style.backgroundImage !== 'none') hideEl(n);
                if (n.querySelectorAll) {
                    n.querySelectorAll('img').forEach(hideEl);
                    n.querySelectorAll('[style*="background-image"]').forEach(hideEl);
                }
            }
        }
    }).observe(document.documentElement, { childList: true, subtree: true, attributes: true, attributeFilter: ['src'] });

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // PHASE 4: Block exfiltration of unblurred pixels
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // CSS blur is cosmetic — the underlying <img>/<video> still holds the raw
    // source. Dragging to the Finder, right-click → Save Image As, or copy
    // would all expose the original bytes. Capture-phase listeners run before
    // any site handlers and survive React re-renders (no DOM attribute needed).
    function shouldBlock(el) {
        if (!el || !el.nodeName) return false;
        var tag = el.nodeName;
        if (tag === 'IMG') {
            return !el.hasAttribute || !el.hasAttribute('data-sca-safe');
        }
        if (tag === 'VIDEO') {
            // Videos don't carry data-sca-safe — check inline filter instead.
            var f = (el.style && el.style.filter) || '';
            return f.indexOf('blur') !== -1;
        }
        return false;
    }
    function blockEvent(e) {
        if (shouldBlock(e.target)) {
            e.preventDefault();
            e.stopPropagation();
            return false;
        }
    }
    // dragstart  → drag-to-Finder, drag-to-other-app
    // contextmenu → right-click → Save Image As / Copy Image
    // copy/cut   → ⌘C on a selected/focused image
    var blockedEvents = ['dragstart', 'contextmenu', 'copy', 'cut'];
    for (var i = 0; i < blockedEvents.length; i++) {
        document.addEventListener(blockedEvents[i], blockEvent, true);
    }
})();
