const platforms = [
  {
    title: "Social platforms",
    body:
      "Instagram, TikTok, X, Reddit, Facebook. Your scroll stays calm — even when the algorithm doesn't.",
    icon: "🌐",
  },
  {
    title: "Streaming services",
    body:
      "Yes, Netflix too. And YouTube, Prime Video, Disney+. Family movie nights without the sweaty-palms preview.",
    icon: "🎬",
  },
  {
    title: "Anywhere on the web",
    body:
      "Random article, Wikipedia rabbit hole, iframe from who-knows-where. If pixels reach the screen, Blur is already on them.",
    icon: "🪟",
  },
];

export function HowItWorks() {
  return (
    <section
      id="how-it-works"
      className="border-t border-border/50 bg-chrome/30"
    >
      <div className="mx-auto max-w-6xl px-6 py-24">
        <div className="mb-16 max-w-2xl">
          <div className="mb-4 text-xs font-semibold uppercase tracking-widest text-accent">
            How it works
          </div>
          <h2 className="text-3xl font-semibold tracking-tight text-foreground sm:text-4xl">
            AI that actually watches the screen.
          </h2>
          <p className="mt-4 text-lg leading-relaxed text-foreground/70">
            Blur reads every image and video frame in real time and softens
            what doesn't belong. No keyword lists. No URL blocklists. No "nope,
            that site isn't on the registry yet." If your browser can show it,
            Blur can see it.
          </p>
        </div>

        <div className="grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
          {platforms.map((p) => (
            <article
              key={p.title}
              className="rounded-2xl border border-border/60 bg-surface p-6 shadow-sm"
            >
              <div
                aria-hidden="true"
                className="mb-4 inline-flex h-10 w-10 items-center justify-center rounded-xl bg-accent/10 text-xl"
              >
                {p.icon}
              </div>
              <h3 className="text-lg font-semibold text-foreground">
                {p.title}
              </h3>
              <p className="mt-2 text-sm leading-relaxed text-foreground/70">
                {p.body}
              </p>
            </article>
          ))}
        </div>
      </div>
    </section>
  );
}
