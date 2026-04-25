import Image from "next/image";

const features = [
  {
    title: "Vertical sidebar",
    description:
      "Tabs live on the left, stacked vertically like a calm reading list. More room for page titles, less eye-darting along a cramped top bar.",
    badge: "Built-in",
    screenshot: "/sidebar.png",
  },
  {
    title: "Keyboard shortcuts",
    description:
      "Blur is made for the keyboard. Press ⌘ + / anywhere in the browser to pull up the full list of shortcuts — no hunting through menus.",
    badge: "Built-in",
    screenshot: "/shortcut.png",
  },
  {
    title: "Seven themes, your mood",
    description:
      "From airy Periwinkle to inky Midnight. Pick a palette for your window and the whole browser shifts with you.",
    badge: "Built-in",
    screenshot: "/seven-theme.png",
  },
  {
    title: "Quick search",
    description:
      "Press ⌘K to search tabs, history, and the web from one calm overlay. No context switching.",
    badge: "Built-in",
    screenshot: "/quick-search.png",
  },
  {
    title: "Zen mode",
    description:
      "Hide the chrome, dim the noise, keep only the page. One shortcut away when you need to read, write, or think without the browser getting in your way.",
    badge: "Built-in",
    screenshot: "/zen-mode.png",
  },
  {
    title: "Funny error messages",
    description:
      "When things go sideways, Blur doesn't lecture you with a stack trace. You get a witty, human error page that makes you smile instead of sigh.",
    badge: "Built-in",
    screenshot: "/funny-error.png",
  },
  {
    title: "Built on WebKit",
    description:
      "The same engine that powers Safari. Fast to load, gentle on your battery, honest to web standards.",
    badge: "Engine",
    screenshot: null,
  },
  {
    title: "Private & secure",
    description:
      "No tracking, no telemetry, no ad networks watching your every move. Your browsing history stays on your Mac, where it belongs.",
    badge: "Core",
    screenshot: null,
  },
];

export function Features() {
  return (
    <section id="features" className="border-t border-border/50">
      <div className="mx-auto max-w-6xl px-6 py-24">
        <div className="mb-16 max-w-2xl">
          <div className="mb-4 text-xs font-semibold uppercase tracking-widest text-accent">
            Beyond the blur
          </div>
          <h2 className="text-3xl font-semibold tracking-tight text-foreground sm:text-4xl">
            And it's a delight to use, too.
          </h2>
          <p className="mt-4 text-lg leading-relaxed text-foreground/70">
            The safety is the headline. Everything else is what makes Blur
            worth opening every day — seven hand-crafted themes, ⌘K
            everywhere, Zen mode for deep work, and a few small jokes hiding
            in the error pages.
          </p>
        </div>

        <div className="gap-6 columns-1 sm:columns-2 lg:columns-3 [column-fill:_balance]">
          {features.map((f) => (
            <article
              key={f.title}
              className="group relative mb-6 flex break-inside-avoid flex-col overflow-hidden rounded-2xl border border-border/60 bg-surface shadow-sm transition hover:shadow-md"
            >
              {f.screenshot && !f.screenshot.startsWith("/screenshots/") && (
                <div className="relative aspect-[16/10] w-full overflow-hidden border-b border-border/60 bg-chrome/50">
                  <Image
                    src={f.screenshot}
                    alt={f.title}
                    fill
                    sizes="(min-width: 1024px) 400px, (min-width: 640px) 50vw, 100vw"
                    className="object-cover"
                  />
                </div>
              )}
              <div className="flex flex-1 flex-col p-6">
                <div className="mb-3 inline-flex self-start rounded-full border border-border/60 bg-chrome/60 px-2.5 py-0.5 text-[11px] font-medium text-foreground/80">
                  {f.badge}
                </div>
                <h3 className="text-lg font-semibold text-foreground">{f.title}</h3>
                <p className="mt-2 text-sm leading-relaxed text-foreground/70">
                  {f.description}
                </p>
              </div>
            </article>
          ))}
        </div>
      </div>
    </section>
  );
}
