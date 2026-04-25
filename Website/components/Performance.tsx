const points = [
  {
    title: "On-GPU, on-device",
    body:
      "The detection model runs on your Mac's Metal-accelerated GPU — the same silicon that drives Final Cut, Logic, and your games.",
    icon: "🖥️",
  },
  {
    title: "No server round-trips",
    body:
      "Nothing leaves your Mac. No API calls, no network latency, no cold starts. Frames are analyzed before they finish rendering.",
    icon: "⚡",
  },
  {
    title: "Battery-friendly",
    body:
      "Apple Silicon eats AI inference for breakfast. Blur stays cool, the fan stays quiet, the battery stays full.",
    icon: "🔋",
  },
];

export function Performance() {
  return (
    <section id="performance" className="border-t border-border/50">
      <div className="mx-auto max-w-6xl px-6 py-24">
        <div className="mb-16 max-w-2xl">
          <div className="mb-4 text-xs font-semibold uppercase tracking-widest text-accent">
            Performance
          </div>
          <h2 className="text-3xl font-semibold tracking-tight text-foreground sm:text-4xl">
            Faster than you'd expect.
          </h2>
          <p className="mt-4 text-lg leading-relaxed text-foreground/70">
            "AI" usually means a server round-trip, a spinner, and a pause.
            Blur skips all of that. The detection model runs on your Mac's
            GPU — locally, in milliseconds — so the browser stays as fast as
            the WebKit it's built on.
          </p>
        </div>

        <div className="grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
          {points.map((p) => (
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
