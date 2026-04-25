import Link from "next/link";

interface RoadmapItem {
  title: string;
  status: "Coming soon" | "In flight" | "Exploring" | "Open";
  body: string;
}

const items: RoadmapItem[] = [
  {
    title: "Website blocking",
    status: "Coming soon",
    body: "Block entire domains at the browser level. No extensions, no workarounds — they just don't load.",
  },
  {
    title: "Smarter detection",
    status: "In flight",
    body: "Better accuracy, faster inference, and fewer false positives. Always on-device.",
  },
  {
    title: "Blur for iPhone & iPad",
    status: "Exploring",
    body: "Same calm browsing, on the go. Bringing Blur to iOS and iPadOS is next on the list.",
  },
  {
    title: "Your idea here",
    status: "Open",
    body: "The best features come from the people actually using Blur. Tell us what's missing.",
  },
];

const statusStyles: Record<RoadmapItem["status"], string> = {
  "Coming soon": "border-accent/40 bg-accent/10 text-accent",
  "In flight": "border-border/60 bg-chrome/60 text-foreground/80",
  "Exploring": "border-border/60 bg-chrome/60 text-foreground/80",
  "Open": "border-border/60 bg-chrome/60 text-foreground/80",
};

export function Roadmap() {
  return (
    <section id="roadmap" className="border-t border-border/50 bg-chrome/30">
      <div className="mx-auto max-w-6xl px-6 py-24">
        <div className="grid gap-16 md:grid-cols-2 md:gap-24">
          <div>
            <div className="mb-4 text-xs font-semibold uppercase tracking-widest text-accent">
              What's next
            </div>
            <h2 className="text-3xl font-semibold tracking-tight text-foreground sm:text-4xl">
              This is just the start.
            </h2>
            <p className="mt-4 text-lg leading-relaxed text-foreground/70">
              Blur is in beta — what you see today is the first chapter, not
              the last. There's a longer list of features in motion than this
              section can hold, and the best ones are usually the ones you
              ask for.
            </p>

            <div className="mt-8 flex flex-wrap items-center gap-3">
              <Link
                href="/contact"
                className="inline-flex items-center gap-2 rounded-full bg-accent px-5 py-2.5 text-sm font-semibold text-white shadow-sm transition hover:opacity-90"
              >
                Tell us what to build next
                <span aria-hidden="true">→</span>
              </Link>
              <a
                href="https://github.com/EngOmarElsayed/blur-browser"
                target="_blank"
                rel="noreferrer"
                className="rounded-full border border-border/70 bg-surface px-5 py-2.5 text-sm font-semibold text-foreground transition hover:bg-chrome"
              >
                ⭐ Star on GitHub
              </a>
            </div>
          </div>

          <ul className="space-y-3">
            {items.map((item) => (
              <li
                key={item.title}
                className="rounded-2xl border border-border/60 bg-surface p-5 shadow-sm"
              >
                <div className="flex items-center justify-between gap-4">
                  <h3 className="text-base font-semibold text-foreground">
                    {item.title}
                  </h3>
                  <span
                    className={`shrink-0 rounded-full border px-2.5 py-0.5 text-[11px] font-semibold uppercase tracking-wider ${statusStyles[item.status]}`}
                  >
                    {item.status}
                  </span>
                </div>
                <p className="mt-2 text-sm leading-relaxed text-foreground/70">
                  {item.body}
                </p>
              </li>
            ))}
          </ul>
        </div>
      </div>
    </section>
  );
}
