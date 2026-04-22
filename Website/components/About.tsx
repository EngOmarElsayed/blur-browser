import Image from "next/image";

export function About() {
  return (
    <section id="about" className="border-t border-border/50 bg-chrome/30">
      <div className="mx-auto max-w-6xl px-6 py-24">
        <div className="grid gap-16 md:grid-cols-2 md:gap-24">
          <div className="flex flex-col items-start">
            <div className="mb-4 text-xs font-semibold uppercase tracking-widest text-accent">
              About
            </div>
            <h2 className="text-3xl font-semibold tracking-tight text-foreground sm:text-4xl">
              A quieter, safer web.
            </h2>
            <div
              className="relative mt-10"
              style={{
                filter: "drop-shadow(0 20px 40px rgb(var(--accent) / 0.25))",
              }}
            >
              <Image
                src="/logo.png"
                alt="Blur Browser icon"
                width={160}
                height={160}
                className="rounded-[36px]"
              />
            </div>
          </div>

          <div className="space-y-6 text-lg text-foreground/80 leading-relaxed">
            <p>
              Blur began as a simple idea: the web shouldn't ambush you. Most browsers treat
              every pixel the same. Blur treats your attention like something worth
              protecting.
            </p>
            <p>
              Under the hood, it's WebKit — the same rendering engine that powers Safari —
              so sites load fast, look right, and respect your battery. On top, we've
              added calm UI, seven hand-crafted themes, and a growing set of tools to
              shield you from what you'd rather not see.
            </p>
            <p>
              Blur is <strong className="text-foreground">free</strong> and will always be{" "}
              <strong className="text-foreground">open source</strong>. No tracking, no
              upsells, no dark patterns. Just a browser that's on your side.
            </p>

            <div className="grid grid-cols-3 gap-4 pt-4">
              <Stat label="Engine" value="WebKit" />
              <Stat label="Price" value="Free" />
              <Stat label="Source" value="Open" />
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-xl border border-border/60 bg-surface px-4 py-3">
      <div className="text-[11px] font-medium uppercase tracking-wider text-foreground/60">
        {label}
      </div>
      <div className="mt-1 text-xl font-semibold text-foreground">{value}</div>
    </div>
  );
}
