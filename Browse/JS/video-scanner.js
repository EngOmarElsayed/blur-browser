// video-scanner.js — Video frame capture + classification pipeline
// Injected at documentEnd in ALL frames (including YouTube/Vimeo iframes)

(function() {
    if (window.__vidScanner) return;
    window.__vidScanner = true;

    var isIframe = (window !== window.top);
    var frameLabel = isIframe ? '[iframe] ' : '';

    function log(msg) {
        try { window.webkit.messageHandlers.videoLog.postMessage(frameLabel + msg); } catch(e) {}
    }

    function ensureId(el) {
        if (!el.dataset.vidId) {
            el.dataset.vidId = 'vid_' + Math.random().toString(36).substr(2, 9);
        }
        return el.dataset.vidId;
    }

    var blurState = {};

    async function captureAndClassify(video) {
        if (video.readyState < 2) return;
        if (video.videoWidth < 80 || video.videoHeight < 80) return;
        if (video.__vidClassifying) return;
        video.__vidClassifying = true;

        try {
            var vw = video.videoWidth, vh = video.videoHeight;
            var maxDim = 224;
            var w = vw, h = vh;
            if (w > maxDim || h > maxDim) {
                var r = Math.min(maxDim / w, maxDim / h);
                w = Math.round(w * r); h = Math.round(h * r);
            }

            var c = document.createElement('canvas');
            c.width = w; c.height = h;
            var ctx = c.getContext('2d');
            ctx.drawImage(video, 0, 0, w, h);

            try {
                var px = ctx.getImageData(Math.floor(w / 2), Math.floor(h / 2), 1, 1).data;
                if (px[0] === 0 && px[1] === 0 && px[2] === 0 && px[3] === 0) return;
            } catch(e) {
                log('canvas tainted: ' + (video.src || video.currentSrc || '').substring(0, 60));
                return;
            }

            var data = c.toDataURL('image/jpeg', 0.7);
            var id = ensureId(video);

            var result = await window.webkit.messageHandlers.videoFrame.postMessage({
                frameData: data,
                elementId: id,
                src: (video.src || video.currentSrc || '').substring(0, 200),
                currentTime: video.currentTime,
                isIframe: isIframe,
                host: location.hostname
            });

            if (!result) return;

            var shouldBlur = result.blur;
            var wasBlurred = blurState[id] || false;

            if (shouldBlur && !wasBlurred) {
                // See blurImageJS in WebViewCoordinator.swift for rationale —
                // scale pushes the faded edge halo outside the parent's
                // overflow clip so the full frame is actually covered.
                video.style.setProperty('filter', 'blur(30px)', 'important');
                video.style.setProperty('clip-path', 'inset(0)', 'important');
                video.style.setProperty('transform', 'scale(1.25)', 'important');
                video.style.setProperty('transform-origin', '50% 50%', 'important');
                blurState[id] = true;
                log('BLUR applied: ' + id);
            } else if (!shouldBlur && wasBlurred) {
                video.style.removeProperty('filter');
                video.style.removeProperty('clip-path');
                video.style.removeProperty('transform');
                video.style.removeProperty('transform-origin');
                blurState[id] = false;
                log('BLUR removed: ' + id);
            }
        } catch(e) {
            log('captureAndClassify error: ' + e.message);
        } finally {
            video.__vidClassifying = false;
        }
    }

    function hookVideo(video) {
        if (video.__vidHooked) return;
        video.__vidHooked = true;
        ensureId(video);

        var interval = null;
        var SAMPLE_MS = 1500;

        function startSampling() {
            if (interval) return;
            captureAndClassify(video);
            interval = setInterval(function() {
                if (video.paused || video.ended) { stopSampling(); return; }
                captureAndClassify(video);
            }, SAMPLE_MS);
        }

        function stopSampling() {
            if (interval) { clearInterval(interval); interval = null; }
        }

        video.addEventListener('play', startSampling);
        video.addEventListener('playing', startSampling);
        video.addEventListener('seeked', function() { captureAndClassify(video); });
        video.addEventListener('pause', stopSampling);
        video.addEventListener('ended', stopSampling);
        video.addEventListener('loadeddata', function() { captureAndClassify(video); });

        if (!video.paused && video.readyState >= 2) {
            startSampling();
        } else if (video.readyState >= 2) {
            captureAndClassify(video);
        }
    }

    window.__vidScan = function() {
        document.querySelectorAll('video').forEach(hookVideo);
    };
    window.__vidHookVideo = hookVideo;

    // MutationObserver for dynamically added <video> elements
    new MutationObserver(function(muts) {
        for (var i = 0; i < muts.length; i++) {
            var added = muts[i].addedNodes;
            for (var j = 0; j < added.length; j++) {
                var n = added[j];
                if (n.nodeType !== 1) continue;
                if (n.nodeName === 'VIDEO' && window.__vidHookVideo) window.__vidHookVideo(n);
                if (n.querySelectorAll) {
                    n.querySelectorAll('video').forEach(function(v) {
                        if (window.__vidHookVideo) window.__vidHookVideo(v);
                    });
                }
            }
        }
    }).observe(document.body || document.documentElement, { childList: true, subtree: true });

    // Periodic fallback for YouTube-style players
    setInterval(function() { if (window.__vidScan) window.__vidScan(); }, 2000);

    window.__vidScan();
    log('Video scanner ready. host=' + location.hostname + (isIframe ? ' (iframe)' : ' (main)'));
})();
