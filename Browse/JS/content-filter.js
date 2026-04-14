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
    style.textContent = 'img:not([data-sca-done]) { opacity: 0 !important; transition: opacity 0.15s ease !important; }';
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
        }
        el.__scaTimer = setTimeout(function() {
            if (!el.__scaDone) {
                el.setAttribute('data-sca-done', '1');
                el.style.opacity = '1';
                el.__scaDone = true;
            }
        }, 3000);
    }

    function rehideEl(el) {
        el.removeAttribute('data-sca-done');
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
})();
