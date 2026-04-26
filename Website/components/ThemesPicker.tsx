"use client";

import { useTheme } from "./ThemeProvider";

/**
 * Live, interactive showcase of all seven themes. Clicking a swatch flips
 * the whole site's theme — wires straight into the existing ThemeProvider
 * context so the global CSS variables update instantly.
 *
 * Used inside the "Calm by design" Features section so visitors can feel
 * the theming system as a feature, not just read about it.
 */
export function ThemesPicker() {
  const { themeID, setThemeID, themes } = useTheme();

  return (
    <div
      className="grid grid-cols-2 gap-3 sm:grid-cols-4 lg:grid-cols-7"
      role="radiogroup"
      aria-label="Choose a theme"
    >
      {themes.map((theme) => {
        const active = theme.id === themeID;
        return (
          <button
            key={theme.id}
            type="button"
            role="radio"
            aria-checked={active}
            aria-label={`Switch to ${theme.name} theme`}
            onClick={() => setThemeID(theme.id)}
            className="group/swatch flex flex-col overflow-hidden rounded-xl border shadow-sm transition hover:-translate-y-0.5 hover:shadow-md focus:outline-none focus-visible:ring-2 focus-visible:ring-offset-2"
            style={{
              borderColor: active ? theme.accent : theme.border,
              borderWidth: active ? 2 : 1,
              background: theme.surface,
              boxShadow: active
                ? `0 0 0 3px ${hexWithAlpha(theme.accent, 0.18)}`
                : undefined,
            }}
          >
            <div
              className="h-12 w-full"
              style={{ background: theme.chrome }}
            />
            <div className="flex items-center justify-between gap-2 px-3 py-2">
              <span
                className="text-[11px] font-semibold tracking-tight"
                style={{ color: theme.foreground }}
              >
                {theme.name}
              </span>
              <span
                className={`flex h-2.5 w-2.5 items-center justify-center rounded-full transition-transform ${
                  active ? "scale-125" : "group-hover/swatch:scale-110"
                }`}
                style={{ background: theme.accent }}
                aria-hidden="true"
              />
            </div>
          </button>
        );
      })}
    </div>
  );
}

/**
 * Returns the given #RRGGBB hex color with the requested alpha as an
 * `rgba(r, g, b, a)` string. Used to tint the active swatch's outer glow.
 */
function hexWithAlpha(hex: string, alpha: number): string {
  const h = hex.replace("#", "");
  const n = parseInt(h, 16);
  const r = (n >> 16) & 255;
  const g = (n >> 8) & 255;
  const b = n & 255;
  return `rgba(${r}, ${g}, ${b}, ${alpha})`;
}
