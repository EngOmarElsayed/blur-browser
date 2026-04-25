const useCases = [
  {
    title: "Family movie nights",
    body:
      "Pick a film together. Trust the browser to handle the scenes you'd rather skip past — without pausing, fast-forwarding, or that awkward \"oh, hold on\" moment.",
    icon: "🎥",
  },
  {
    title: "Calm everyday browsing",
    body:
      "Open a tab. Read an article. No ambush from a sidebar ad or a thumbnail you didn't ask to see. Just the web, the way it should have been.",
    icon: "☕",
  },
  {
    title: "Sharing your screen",
    body:
      "Demos, presentations, classroom projectors, screencasts. One less thing to worry about going sideways in front of an audience.",
    icon: "💻",
  },
];

export function WhoItsFor() {
  return (
    <section id="who-its-for" className="border-t border-border/50">
      <div className="mx-auto max-w-6xl px-6 py-24">
        <div className="mb-16 max-w-2xl">
          <div className="mb-4 text-xs font-semibold uppercase tracking-widest text-accent">
            Who Blur is for
          </div>
          <h2 className="text-3xl font-semibold tracking-tight text-foreground sm:text-4xl">
            For when you'd rather not be ambushed.
          </h2>
          <p className="mt-4 text-lg leading-relaxed text-foreground/70">
            Blur is for anyone who'd like a little more peace and a little
            less surprise from their browser.
          </p>
        </div>

        <div className="grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
          {useCases.map((u) => (
            <article
              key={u.title}
              className="rounded-2xl border border-border/60 bg-surface p-6 shadow-sm"
            >
              <div
                aria-hidden="true"
                className="mb-4 inline-flex h-10 w-10 items-center justify-center rounded-xl bg-accent/10 text-xl"
              >
                {u.icon}
              </div>
              <h3 className="text-lg font-semibold text-foreground">
                {u.title}
              </h3>
              <p className="mt-2 text-sm leading-relaxed text-foreground/70">
                {u.body}
              </p>
            </article>
          ))}
        </div>
      </div>
    </section>
  );
}
