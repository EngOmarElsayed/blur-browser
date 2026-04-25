"use client";

import { useEffect, useRef, useState } from "react";

interface HeroVideoProps {
  src: string;
  poster: string;
}

export function HeroVideo({ src, poster }: HeroVideoProps) {
  const videoRef = useRef<HTMLVideoElement>(null);
  // Start muted so when the user does press play, the browser doesn't block
  // playback. They can flip the mute toggle whenever they want.
  const [muted, setMuted] = useState(true);
  // Video does not autoplay — the centered play button is the entry point.
  const [playing, setPlaying] = useState(false);

  // Keep the playing flag in sync with the real video state. The browser may
  // pause autoplay (e.g. data saver, low-power mode), and we want the icon
  // to reflect reality.
  useEffect(() => {
    const video = videoRef.current;
    if (!video) return;

    const onPlay = () => setPlaying(true);
    const onPause = () => setPlaying(false);

    video.addEventListener("play", onPlay);
    video.addEventListener("pause", onPause);
    return () => {
      video.removeEventListener("play", onPlay);
      video.removeEventListener("pause", onPause);
    };
  }, []);

  const toggleMuted = () => {
    const video = videoRef.current;
    if (!video) return;
    const next = !video.muted;
    video.muted = next;
    setMuted(next);

    // If we just unmuted but autoplay had paused us, kick playback back on.
    if (!next && video.paused) {
      video.play().catch(() => {
        // Autoplay with sound denied — fall back to muted state.
        video.muted = true;
        setMuted(true);
      });
    }
  };

  const togglePlaying = () => {
    const video = videoRef.current;
    if (!video) return;

    if (video.paused) {
      video.play().catch(() => {
        // Play denied — leave UI in paused state.
        setPlaying(false);
      });
    } else {
      video.pause();
    }
  };

  return (
    <div className="relative aspect-[1554/1080] w-full overflow-hidden rounded-2xl border border-border/60 bg-chrome/50 shadow-2xl">
      <video
        ref={videoRef}
        src={src}
        poster={poster}
        muted
        loop
        playsInline
        preload="metadata"
        aria-label="Blur Browser product demo"
        className="absolute inset-0 h-full w-full object-cover"
      />

      {/* Centered play/pause button. Always rendered, but fades out while
          playing so it doesn't cover the video — reappears on hover/focus
          and stays visible while paused. */}
      <button
        type="button"
        onClick={togglePlaying}
        aria-label={playing ? "Pause video" : "Play video"}
        aria-pressed={!playing}
        className={`group/play absolute left-1/2 top-1/2 z-10 flex h-16 w-16 -translate-x-1/2 -translate-y-1/2 items-center justify-center rounded-full border border-white/20 bg-black/55 text-white shadow-lg backdrop-blur-md transition-all duration-300 hover:scale-105 hover:bg-black/70 focus:outline-none focus-visible:ring-2 focus-visible:ring-white/80 sm:h-20 sm:w-20 ${
          playing
            ? "opacity-0 hover:opacity-100 focus-visible:opacity-100"
            : "opacity-100"
        }`}
      >
        <span className="sr-only">{playing ? "Pause" : "Play"}</span>
        {playing ? <PauseIcon size={28} /> : <PlayIcon size={28} />}
      </button>

      {/* Mute toggle stays pinned top-right. */}
      <div className="absolute right-3 top-3 z-10 flex items-center gap-2 sm:right-4 sm:top-4">
        <ControlButton
          onClick={toggleMuted}
          ariaLabel={muted ? "Unmute video" : "Mute video"}
          ariaPressed={!muted}
        >
          {muted ? <MutedIcon /> : <UnmutedIcon />}
        </ControlButton>
      </div>
    </div>
  );
}

function ControlButton({
  onClick,
  ariaLabel,
  ariaPressed,
  children,
}: {
  onClick: () => void;
  ariaLabel: string;
  ariaPressed: boolean;
  children: React.ReactNode;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-label={ariaLabel}
      aria-pressed={ariaPressed}
      className="inline-flex h-9 w-9 items-center justify-center rounded-full border border-white/20 bg-black/45 text-white shadow-md backdrop-blur-md transition hover:bg-black/65 focus:outline-none focus-visible:ring-2 focus-visible:ring-white/70"
    >
      {children}
    </button>
  );
}

function PlayIcon({ size = 16 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
      <path d="M8 5.14v13.72a1 1 0 0 0 1.54.84l10.74-6.86a1 1 0 0 0 0-1.68L9.54 4.3A1 1 0 0 0 8 5.14z" />
    </svg>
  );
}

function PauseIcon({ size = 16 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
      <rect x="6" y="5" width="4" height="14" rx="1" />
      <rect x="14" y="5" width="4" height="14" rx="1" />
    </svg>
  );
}

function MutedIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" aria-hidden="true">
      <path
        d="M11 5L6 9H3a1 1 0 0 0-1 1v4a1 1 0 0 0 1 1h3l5 4V5z"
        fill="currentColor"
      />
      <path
        d="M16 9l6 6m0-6l-6 6"
        stroke="currentColor"
        strokeWidth="2"
        strokeLinecap="round"
      />
    </svg>
  );
}

function UnmutedIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" aria-hidden="true">
      <path
        d="M11 5L6 9H3a1 1 0 0 0-1 1v4a1 1 0 0 0 1 1h3l5 4V5z"
        fill="currentColor"
      />
      <path
        d="M16 8c1.5 1 2.5 2.5 2.5 4s-1 3-2.5 4M19 5c2.5 1.5 4 4 4 7s-1.5 5.5-4 7"
        stroke="currentColor"
        strokeWidth="2"
        strokeLinecap="round"
        fill="none"
      />
    </svg>
  );
}
