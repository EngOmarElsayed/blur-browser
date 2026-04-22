"use client";

import { createContext, useContext, useEffect, useMemo, useState } from "react";
import {
  type Theme,
  type ThemeID,
  defaultThemeID,
  themeById,
  themeCssVars,
  themes,
} from "@/lib/themes";

interface ThemeContextValue {
  themeID: ThemeID;
  theme: Theme;
  setThemeID: (id: ThemeID) => void;
  themes: Theme[];
}

const ThemeContext = createContext<ThemeContextValue | null>(null);

const STORAGE_KEY = "blur-theme";

export function ThemeProvider({ children }: { children: React.ReactNode }) {
  const [themeID, setThemeIDState] = useState<ThemeID>(defaultThemeID);

  useEffect(() => {
    const saved = localStorage.getItem(STORAGE_KEY) as ThemeID | null;
    if (saved && themes.some((t) => t.id === saved)) {
      setThemeIDState(saved);
    }
  }, []);

  const theme = useMemo(() => themeById(themeID), [themeID]);

  useEffect(() => {
    const root = document.documentElement;
    const vars = themeCssVars(theme);
    for (const [k, v] of Object.entries(vars)) {
      root.style.setProperty(k, v);
    }
    root.style.colorScheme = theme.isDark ? "dark" : "light";
  }, [theme]);

  const setThemeID = (id: ThemeID) => {
    setThemeIDState(id);
    localStorage.setItem(STORAGE_KEY, id);
  };

  return (
    <ThemeContext.Provider value={{ themeID, theme, setThemeID, themes }}>
      {children}
    </ThemeContext.Provider>
  );
}

export const useTheme = () => {
  const ctx = useContext(ThemeContext);
  if (!ctx) throw new Error("useTheme must be used inside ThemeProvider");
  return ctx;
};
