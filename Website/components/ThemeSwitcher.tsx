"use client";

import { useEffect, useRef, useState } from "react";
import { useTheme } from "./ThemeProvider";

export function ThemeSwitcher() {
  const { themeID, setThemeID, themes } = useTheme();
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const onClick = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false);
    };
    document.addEventListener("mousedown", onClick);
    return () => document.removeEventListener("mousedown", onClick);
  }, []);

  return (
    <div className="relative" ref={ref}>
      <button
        onClick={() => setOpen((o) => !o)}
        className="flex items-center gap-2 rounded-full border border-border/60 bg-chrome/70 px-3 py-1.5 text-sm font-medium text-foreground backdrop-blur hover:bg-chrome transition"
        aria-label="Change theme"
      >
        <span
          className="h-4 w-4 rounded-full border border-border/60"
          style={{ background: `rgb(var(--accent))` }}
        />
        <span className="hidden sm:inline">Theme</span>
        <svg width="12" height="12" viewBox="0 0 12 12" className="opacity-60">
          <path d="M2 4l4 4 4-4" stroke="currentColor" strokeWidth="1.5" fill="none" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      </button>

      {open && (
        <div className="absolute right-0 mt-2 w-64 overflow-hidden rounded-xl border border-border/60 bg-surface shadow-lg z-50">
          <div className="p-2">
            {themes.map((t) => (
              <button
                key={t.id}
                onClick={() => {
                  setThemeID(t.id);
                  setOpen(false);
                }}
                className={`flex w-full items-center gap-3 rounded-lg px-2.5 py-2 text-left transition hover:bg-chrome/60 ${
                  t.id === themeID ? "bg-chrome/80" : ""
                }`}
              >
                <div className="flex gap-0.5">
                  <span className="h-5 w-2 rounded-sm" style={{ background: t.chrome }} />
                  <span className="h-5 w-2 rounded-sm" style={{ background: t.accent }} />
                  <span className="h-5 w-2 rounded-sm" style={{ background: t.foreground }} />
                </div>
                <div className="flex-1 min-w-0">
                  <div className="text-sm font-medium text-foreground">{t.name}</div>
                  <div className="text-[11px] text-foreground/60 truncate">{t.mood}</div>
                </div>
                {t.id === themeID && (
                  <svg width="14" height="14" viewBox="0 0 14 14" className="text-accent">
                    <path d="M3 7l3 3 5-6" stroke="currentColor" strokeWidth="2" fill="none" strokeLinecap="round" strokeLinejoin="round" />
                  </svg>
                )}
              </button>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
