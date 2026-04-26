import Image from "next/image";
import { ThemesPicker } from "./ThemesPicker";

interface FeatureCard {
  title: string;
  body: string;
  /** Path under /public — omit for text-only cards. */
  screenshot?: string;
  /** Bento variant. "wide" spans 2 columns on lg+. Default is 1 column. */
  variant?: "wide";
  icon?: string;
}

const features: FeatureCard[] = [
  {
    title: "Vertical sidebar",
    body:
      "Tabs live on the left, stacked vertically like a calm reading list. More room for page titles, less eye-darting along a cramped top bar.",
    screenshot: "/sidebar.png",
  },
  {
    title: "Seven themes for your mood",
    body:
      "From airy Periwinkle to inky Midnight. Pick a palette for your window and the whole browser shifts with you.",
    variant: "wide",
  },
  {
    title: "Quick search",
    body: "Press ⌘K to search tabs, history, and the web from one calm overlay. No context switching.",
    screenshot: "/quick-search.png",
  },
  {
    title: "Zen mode",
    body: "Hide the chrome, dim the noise, keep only the page. One shortcut away when you need to read, write, or think.",
    screenshot: "/zen-mode.png",
  },
  {
    title: "Keyboard shortcuts",
    body: "Made for the keyboard. ⌘ + / pulls up the full list anywhere — no hunting through menus.",
    screenshot: "/shortcut.png",
  },
  {
    title: "Funny error messages",
    body: "When things go sideways, Blur doesn't lecture you with a stack trace. You get a witty, human error page that makes you smile.",
    screenshot: "/funny-error.png",
  },
  {
    title: "Built on WebKit",
    body: "The same engine that powers Safari. Fast to load, gentle on your battery, honest to web standards.",
    icon: "⚡",
  },
  {
    title: "Private & secure",
    body: "No tracking, no telemetry, no ad networks watching your every move. Your browsing history stays on your Mac, where it belongs.",
    icon: "🔒",
  },
];

export function Features() {
  return (
    <section id="features" className="border-t border-border/50">
      <div className="mx-auto max-w-6xl px-6 py-24">
        <div className="mb-16 max-w-2xl">
          <div className="mb-4 text-xs font-semibold uppercase tracking-widest text-accent">
            Calm by design
          </div>
          <h2 className="text-3xl font-semibold tracking-tight text-foreground sm:text-4xl">
            Made to be lived in.
          </h2>
          <p className="mt-4 text-lg leading-relaxed text-foreground/70">
            Vertical tabs that breathe. Seven themes for your mood. ⌘K to find
            anything. Zen mode when you need to focus. The browser you
            actually want to open every morning.
          </p>
        </div>

        {/* Bento grid: 3-column base, with the Themes card spanning 2 cols
            on lg+ to make room for the live palette showcase. */}
        <div className="grid auto-rows-[1fr] grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-3">
          {features.map((f) =>
            f.title === "Seven themes for your mood" ? (
              <ThemesShowcaseCard key={f.title} feature={f} />
            ) : (
              <FeatureTile key={f.title} feature={f} />
            ),
          )}
        </div>
      </div>
    </section>
  );
}

function FeatureTile({ feature }: { feature: FeatureCard }) {
  const wide = feature.variant === "wide";
  return (
    <article
      className={`group flex flex-col overflow-hidden rounded-2xl border border-border/60 bg-surface shadow-sm transition hover:shadow-md ${
        wide ? "lg:col-span-2" : ""
      }`}
    >
      {feature.screenshot ? (
        <div className="relative aspect-[16/10] w-full overflow-hidden border-b border-border/60 bg-chrome/40">
          <Image
            src={feature.screenshot}
            alt={feature.title}
            fill
            sizes="(min-width: 1024px) 400px, (min-width: 640px) 50vw, 100vw"
            className="object-cover transition duration-500 group-hover:scale-[1.02]"
          />
        </div>
      ) : null}

      <div className="flex flex-1 flex-col p-6">
        {feature.icon && !feature.screenshot ? (
          <div
            aria-hidden="true"
            className="mb-4 inline-flex h-10 w-10 items-center justify-center rounded-xl bg-accent/10 text-xl"
          >
            {feature.icon}
          </div>
        ) : null}
        <h3 className="text-lg font-semibold tracking-tight text-foreground">
          {feature.title}
        </h3>
        <p className="mt-2 text-sm leading-relaxed text-foreground/70">
          {feature.body}
        </p>
      </div>
    </article>
  );
}

/**
 * Special card for the Themes feature — uses the live theme palette from
 * lib/themes.ts to render an actual showcase of all seven themes instead of
 * a static screenshot. Spans 2 columns on lg+.
 */
function ThemesShowcaseCard({ feature }: { feature: FeatureCard }) {
  return (
    <article className="group relative flex flex-col overflow-hidden rounded-2xl border border-border/60 bg-surface shadow-sm transition hover:shadow-md lg:col-span-2">
      <div className="relative flex-1 overflow-hidden border-b border-border/60 bg-chrome/40 p-6">
        <ThemesPicker />
      </div>

      <div className="flex flex-col p-6">
        <h3 className="text-lg font-semibold tracking-tight text-foreground">
          {feature.title}
        </h3>
        <p className="mt-2 text-sm leading-relaxed text-foreground/70">
          Click a palette to feel it live — the whole site shifts with you.
        </p>
      </div>
    </article>
  );
}
