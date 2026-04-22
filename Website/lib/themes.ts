export type ThemeID =
  | "periwinkle"
  | "midnight"
  | "sandstone"
  | "nordic"
  | "rosewood"
  | "verdant"
  | "graphite";

export interface Theme {
  id: ThemeID;
  name: string;
  mood: string;
  chrome: string;
  foreground: string;
  accent: string;
  border: string;
  surface: string;
  isDark: boolean;
}

const hexToRgb = (hex: string) => {
  const h = hex.replace("#", "");
  const n = parseInt(h, 16);
  return `${(n >> 16) & 255} ${(n >> 8) & 255} ${n & 255}`;
};

export const themes: Theme[] = [
  {
    id: "periwinkle",
    name: "Periwinkle",
    mood: "Airy sky blue through frosted glass",
    chrome: "#92B4F4",
    foreground: "#1A1A1A",
    accent: "#6366F1",
    border: "#C5CAE0",
    surface: "#F4F7FE",
    isDark: false,
  },
  {
    id: "midnight",
    name: "Midnight",
    mood: "Ink-blue darkness with a soft indigo glow",
    chrome: "#1C1E2A",
    foreground: "#E2E4EA",
    accent: "#818CF8",
    border: "#3A3D50",
    surface: "#13141C",
    isDark: true,
  },
  {
    id: "sandstone",
    name: "Sandstone",
    mood: "Sun-baked clay and natural linen",
    chrome: "#D4C4A8",
    foreground: "#2C2416",
    accent: "#C2703E",
    border: "#BFB093",
    surface: "#F5EEDF",
    isDark: false,
  },
  {
    id: "nordic",
    name: "Nordic",
    mood: "Scandinavian winter clarity, fjord-blue accents",
    chrome: "#C9D0DC",
    foreground: "#1E2A33",
    accent: "#5B8FA8",
    border: "#BCC4D1",
    surface: "#EEF1F6",
    isDark: false,
  },
  {
    id: "rosewood",
    name: "Rosewood",
    mood: "Dusty rose with warm plum undertones",
    chrome: "#DCCDD2",
    foreground: "#2D1F23",
    accent: "#A3586C",
    border: "#C4B2B8",
    surface: "#F5EBEE",
    isDark: false,
  },
  {
    id: "verdant",
    name: "Verdant",
    mood: "Botanical green, sunlit greenhouse",
    chrome: "#B4C4B0",
    foreground: "#1A261A",
    accent: "#527C52",
    border: "#A8B8A4",
    surface: "#EAF0E8",
    isDark: false,
  },
  {
    id: "graphite",
    name: "Graphite",
    mood: "Neutral warm grays — invisible chrome",
    chrome: "#C8C8C8",
    foreground: "#222222",
    accent: "#5A5A5A",
    border: "#B5B5B5",
    surface: "#EEEEEE",
    isDark: false,
  },
];

export const defaultThemeID: ThemeID = "periwinkle";

export const themeById = (id: ThemeID): Theme =>
  themes.find((t) => t.id === id) ?? themes[0];

export const themeCssVars = (theme: Theme): Record<string, string> => ({
  "--chrome": hexToRgb(theme.chrome),
  "--foreground": hexToRgb(theme.foreground),
  "--accent": hexToRgb(theme.accent),
  "--border": hexToRgb(theme.border),
  "--surface": hexToRgb(theme.surface),
});
