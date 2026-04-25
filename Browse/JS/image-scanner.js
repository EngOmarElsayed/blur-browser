// image-scanner.js — Image detection + extraction pipeline
// Injected at documentEnd in ALL frames

(function() {
    if (window.__sca) return;
    window.__sca = true;

    function log(msg) {
        try { window.webkit.messageHandlers.scanLog.postMessage(msg); } catch(e) {}
    }

    function ensureId(el) {
        if (!el.dataset.sensitiveId) {
            el.dataset.sensitiveId = 'sca_' + Math.random().toString(36).substr(2, 9);
        }
        return el.dataset.sensitiveId;
    }

    window.__scaSentIds = window.__scaSentIds || new Set();
    var __scaSentIds = window.__scaSentIds;

    function markDone(el) {
        if (el.__scaDone) return;
        el.__scaDone = true;
        if (el.__scaTimer) { clearTimeout(el.__scaTimer); el.__scaTimer = null; }
    }

    function revealEl(el) {
        markDone(el);
        el.setAttribute('data-sca-done', '1');
        el.setAttribute('data-sca-safe', '1');
        // Clear the placeholder blur that content-filter's hideEl applies
        // inline on insertion. Without this, safe images stay blurred.
        el.style.removeProperty('filter');
        el.style.removeProperty('transform');
        el.style.removeProperty('transform-origin');
        el.style.removeProperty('clip-path');
        el.style.opacity = '1';
    }

    // Canvas extraction (instant, fails on tainted cross-origin)
    function canvasDraw(img, maxDim) {
        try {
            var w = img.naturalWidth || img.width;
            var h = img.naturalHeight || img.height;
            if (w < 80 || h < 80) return null;
            if (w > maxDim || h > maxDim) {
                var r = Math.min(maxDim / w, maxDim / h);
                w = Math.round(w * r); h = Math.round(h * r);
            }
            var c = document.createElement('canvas');
            c.width = w; c.height = h;
            var ctx = c.getContext('2d');
            ctx.drawImage(img, 0, 0, w, h);
            try {
                var spots = [
                    [Math.floor(w/4), Math.floor(h/4)],
                    [Math.floor(w/2), Math.floor(h/2)],
                    [Math.floor(3*w/4), Math.floor(3*h/4)]
                ];
                var allBlack = true;
                for (var s = 0; s < spots.length; s++) {
                    var px = ctx.getImageData(spots[s][0], spots[s][1], 1, 1).data;
                    if (px[0] > 0 || px[1] > 0 || px[2] > 0) { allBlack = false; break; }
                }
                if (allBlack) return null;
            } catch(secErr) { return null; }
            return c.toDataURL('image/jpeg', 0.6);
        } catch(e) { return null; }
    }

    // Fetch fallback (CORS)
    async function fetchDraw(src, maxDim) {
        try {
            var resp = await fetch(src, { mode: 'cors', credentials: 'omit' });
            if (!resp.ok) return null;
            var blob = await resp.blob();
            if (!blob.type.startsWith('image/')) return null;
            var bmp = await createImageBitmap(blob);
            var w = bmp.width, h = bmp.height;
            if (w < 80 || h < 80) { bmp.close(); return null; }
            if (w > maxDim || h > maxDim) {
                var r = Math.min(maxDim / w, maxDim / h);
                w = Math.round(w * r); h = Math.round(h * r);
            }
            var c = new OffscreenCanvas(w, h);
            c.getContext('2d').drawImage(bmp, 0, 0, w, h);
            bmp.close();
            var out = await c.convertToBlob({ type: 'image/jpeg', quality: 0.6 });
            return await new Promise(function(res, rej) {
                var rd = new FileReader();
                rd.onloadend = function() { res(rd.result); };
                rd.onerror = rej;
                rd.readAsDataURL(out);
            });
        } catch(e) { return null; }
    }

    function send(dataURL, elementId, src) {
        if (!dataURL) return false;
        try {
            window.webkit.messageHandlers.imageFound.postMessage({
                imageData: dataURL,
                elementId: elementId,
                src: (src || '').substring(0, 200)
            });
            return true;
        } catch(e) { return false; }
    }

    // Process a single <img> element
    async function processImg(img) {
        if (img.__scaSent) return;
        var src = img.src || img.currentSrc || img.getAttribute('data-src') || img.getAttribute('data-thumb');
        if (!src) { revealEl(img); return; }

        var isInline = src.startsWith('data:') || src.startsWith('blob:');

        var rect = img.getBoundingClientRect();
        if (rect.width < 40 && rect.height < 40) { revealEl(img); return; }

        if (isInline) {
            if (!img.complete || img.naturalWidth < 80 || img.naturalHeight < 80) return;
        }

        img.__scaSent = true;
        var id = ensureId(img);
        if (__scaSentIds.has(id)) { revealEl(img); return; }

        var data = canvasDraw(img, 300);
        if (!data && !isInline) data = await fetchDraw(src, 300);

        if (data) {
            __scaSentIds.add(id);
            send(data, id, src.substring(0, 200));
        } else if (!isInline) {
            __scaSentIds.add(id);
            try {
                window.webkit.messageHandlers.imageFound.postMessage({
                    imageData: '', elementId: id,
                    src: src.substring(0, 2000), needsNativeFetch: true
                });
            } catch(e) { revealEl(img); }
        } else {
            revealEl(img);
        }
    }

    // Process background-image element
    async function processBg(el) {
        if (el.__scaSent) return;
        var bg;
        try { bg = getComputedStyle(el).backgroundImage; } catch(e) { return; }
        if (!bg || bg === 'none') return;
        var m = bg.match(/url\(["']?([^"')]+)["']?\)/);
        if (!m) return;
        var url = m[1];
        if (!url || url.startsWith('data:')) { revealEl(el); return; }

        var rect = el.getBoundingClientRect();
        if (rect.width < 60 || rect.height < 60) { revealEl(el); return; }
        if (!/\.(jpg|jpeg|png|webp)/i.test(url) && !url.includes('ytimg') && !url.includes('ggpht')) {
            revealEl(el); return;
        }

        el.__scaSent = true;
        var id = ensureId(el);
        if (__scaSentIds.has(id)) { revealEl(el); return; }

        var data = await fetchDraw(url, 300);
        if (data) {
            __scaSentIds.add(id);
            send(data, id, url);
        } else {
            __scaSentIds.add(id);
            try {
                window.webkit.messageHandlers.imageFound.postMessage({
                    imageData: '', elementId: id,
                    src: url.substring(0, 2000), needsNativeFetch: true
                });
            } catch(e) { revealEl(el); }
        }
    }

    // Full scan
    window.__scaScan = function() {
        var imgs = document.querySelectorAll('img');
        for (var i = 0; i < imgs.length; i++) processImg(imgs[i]);

        var bgEls = document.querySelectorAll(
            'a[style*="background"], div[style*="background"], ' +
            'ytm-media-item *, [class*="thumbnail"] *, [class*="thumb"] *, ' +
            'ytd-thumbnail *, ytd-rich-grid-media *, yt-image *'
        );
        for (var j = 0; j < bgEls.length; j++) processBg(bgEls[j]);

        var divs = document.querySelectorAll('div, a, section');
        for (var k = 0; k < divs.length; k++) {
            var d = divs[k];
            var r = d.getBoundingClientRect();
            if (r.width >= 100 && r.height >= 80) processBg(d);
        }
    };

    // Hook img.onload
    function hookLoad(img) {
        if (img.__scaHook) return;
        img.__scaHook = true;
        if (img.complete && img.naturalWidth > 0) {
            processImg(img);
        } else {
            img.addEventListener('load', function() { processImg(img); }, { once: true });
        }
    }
    document.querySelectorAll('img').forEach(hookLoad);
    window.__scaHookLoad = hookLoad;

    // SPA navigation support
    function resetState() {
        document.querySelectorAll('[data-sensitive-id]').forEach(function(el) {
            var id = el.dataset.sensitiveId;
            if (__scaSentIds.has(id)) return;
            el.__scaSent = false; el.__scaH = false;
            el.__scaDone = false; el.__scaHook = false;
        });
    }
    var origPush = history.pushState;
    var origReplace = history.replaceState;
    history.pushState = function() {
        origPush.apply(this, arguments);
        setTimeout(function() { resetState(); window.__scaScan(); }, 300);
    };
    history.replaceState = function() {
        origReplace.apply(this, arguments);
        setTimeout(function() { resetState(); window.__scaScan(); }, 300);
    };
    window.addEventListener('popstate', function() {
        setTimeout(function() { resetState(); window.__scaScan(); }, 300);
    });

    // MutationObserver for new images
    var timer = null;
    new MutationObserver(function(muts) {
        for (var i = 0; i < muts.length; i++) {
            var added = muts[i].addedNodes;
            for (var j = 0; j < added.length; j++) {
                var n = added[j];
                if (n.nodeType !== 1) continue;
                if (n.nodeName === 'IMG' && window.__scaHookLoad) window.__scaHookLoad(n);
                if (n.querySelectorAll && window.__scaHookLoad) {
                    n.querySelectorAll('img').forEach(window.__scaHookLoad);
                }
            }
        }
        clearTimeout(timer);
        timer = setTimeout(function() { if (window.__scaScan) window.__scaScan(); }, 0);
    }).observe(document.body || document.documentElement, { childList: true, subtree: true });

    // Scroll-triggered rescan
    var scrollTimer = null;
    window.addEventListener('scroll', function() {
        clearTimeout(scrollTimer);
        scrollTimer = setTimeout(function() { if (window.__scaScan) window.__scaScan(); }, 10);
    }, { passive: true });

    window.__scaScan();
    log('Image scanner ready. host=' + location.hostname);
})();
