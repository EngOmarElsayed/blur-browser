"use client";

import Link from "next/link";
import { useEffect, useState } from "react";

const links = [
  { href: "/#features", label: "Features" },
  { href: "/#about", label: "About" },
  { href: "/contact", label: "Contact" },
];

export function MobileMenu() {
  const [open, setOpen] = useState(false);

  useEffect(() => {
    document.body.style.overflow = open ? "hidden" : "";
    return () => {
      document.body.style.overflow = "";
    };
  }, [open]);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") setOpen(false);
    };
    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
  }, []);

  return (
    <>
      <button
        type="button"
        onClick={() => setOpen((o) => !o)}
        aria-label={open ? "Close menu" : "Open menu"}
        aria-expanded={open}
        className="flex h-9 w-9 items-center justify-center rounded-full border border-border/60 bg-chrome/70 text-foreground backdrop-blur hover:bg-chrome transition sm:hidden"
      >
        <svg width="18" height="18" viewBox="0 0 18 18" fill="none" aria-hidden="true">
          {open ? (
            <>
              <path d="M4 4l10 10" stroke="currentColor" strokeWidth="1.75" strokeLinecap="round" />
              <path d="M14 4L4 14" stroke="currentColor" strokeWidth="1.75" strokeLinecap="round" />
            </>
          ) : (
            <>
              <path d="M3 5h12" stroke="currentColor" strokeWidth="1.75" strokeLinecap="round" />
              <path d="M3 9h12" stroke="currentColor" strokeWidth="1.75" strokeLinecap="round" />
              <path d="M3 13h12" stroke="currentColor" strokeWidth="1.75" strokeLinecap="round" />
            </>
          )}
        </svg>
      </button>

      {open && (
        <div
          className="fixed inset-0 top-[65px] z-30 sm:hidden"
          onClick={() => setOpen(false)}
        >
          <div
            className="border-t border-border/50 bg-surface/95 backdrop-blur shadow-lg"
            onClick={(e) => e.stopPropagation()}
          >
            <nav className="mx-auto flex max-w-6xl flex-col px-6 py-4">
              {links.map((l) => (
                <Link
                  key={l.href}
                  href={l.href}
                  onClick={() => setOpen(false)}
                  className="border-b border-border/40 py-4 text-base font-medium text-foreground last:border-b-0 hover:text-accent transition"
                >
                  {l.label}
                </Link>
              ))}
            </nav>
          </div>
          <div className="h-full w-full bg-foreground/10" />
        </div>
      )}
    </>
  );
}
