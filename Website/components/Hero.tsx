import Image from "next/image";
import Link from "next/link";

export function Hero() {
  return (
    <section className="relative overflow-hidden">
      <div
        className="pointer-events-none absolute inset-0 -z-10"
        style={{
          background:
            "radial-gradient(circle at 20% 10%, rgb(var(--accent) / 0.18), transparent 40%), radial-gradient(circle at 85% 30%, rgb(var(--chrome) / 0.6), transparent 45%)",
        }}
      />

      <div className="mx-auto max-w-6xl px-6 pt-20 pb-24 sm:pt-28 sm:pb-32">
        <div className="flex flex-col items-center text-center">
          <Image
            src="/logo.png"
            alt="Blur Browser"
            width={96}
            height={96}
            className="mb-8 rounded-3xl shadow-xl"
            priority
          />
          <div className="mb-4 inline-flex items-center gap-2 rounded-full border border-border/60 bg-chrome/60 px-3 py-1 text-xs font-medium text-foreground/80">
            <span className="h-1.5 w-1.5 rounded-full bg-accent" />
            Free & open source, forever
          </div>
          <h1 className="max-w-3xl text-4xl font-semibold leading-[1.1] tracking-tight text-foreground sm:text-6xl">
            The browser that{" "}
            <span className="relative inline-block">
              <span className="relative z-10">blurs</span>
              <span
                className="absolute inset-0 -z-0 translate-y-1 rounded-lg"
                style={{ background: "rgb(var(--accent) / 0.25)", filter: "blur(8px)" }}
              />
            </span>{" "}
            what you don't want to see.
          </h1>
          <p className="mt-6 max-w-2xl text-lg text-foreground/70">
            Blur is a native macOS browser that protects you from adult content by blurring
            it automatically — with website blocking and more on the way. Built on WebKit.
            Designed for calm, focused browsing.
          </p>

          <div className="mt-10 flex flex-wrap items-center justify-center gap-3">
            <a
              href="https://github.com/EngOmarElsayed/blur-browser/releases/download/v0.7.0/Blur-Browser-v0.7.0.dmg"
              className="inline-flex items-center gap-2 rounded-full bg-accent px-6 py-3 text-sm font-semibold text-white shadow-sm hover:opacity-90 transition"
            >
              <svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor" aria-hidden="true">
                <path d="M11.182.008C11.148-.03 9.923.023 8.857 1.18c-1.066 1.156-.902 2.482-.878 2.516.024.034 1.52.087 2.475-1.258.955-1.345.762-2.391.728-2.43Zm3.314 11.733c-.048-.096-2.325-1.234-2.113-3.422.212-2.189 1.675-2.789 1.698-2.854.023-.065-.597-.79-1.254-1.157a3.692 3.692 0 0 0-1.563-.434c-.108-.003-.483-.095-1.254.116-.508.139-1.653.589-1.968.607-.316.018-1.256-.522-2.267-.665-.647-.125-1.333.131-1.824.328-.49.196-1.422.754-2.074 2.237-.652 1.482-.311 3.83-.067 4.56.244.729.625 1.924 1.273 2.796.576.984 1.34 1.667 1.659 1.899.319.232 1.219.386 1.843.067.502-.308 1.408-.485 1.766-.472.357.013 1.061.154 1.782.539.571.197 1.111.115 1.652-.105.541-.221 1.324-1.059 2.238-2.758.347-.79.505-1.217.473-1.282Z"/>
              </svg>
              Download for macOS
            </a>
            <Link
              href="/#features"
              className="rounded-full border border-border/70 bg-chrome/70 px-6 py-3 text-sm font-semibold text-foreground hover:bg-chrome transition"
            >
              See features
            </Link>
          </div>

          <a
            href="https://github.com/EngOmarElsayed/blur-browser/releases/tag/v0.7.0"
            target="_blank"
            rel="noreferrer"
            className="mt-4 text-xs text-foreground/60 hover:text-foreground transition"
          >
            v0.7.0 · Release notes ↗
          </a>

          <div className="mt-16 w-full max-w-5xl">
            <div className="relative aspect-[2778/1672] w-full overflow-hidden rounded-2xl border border-border/60 bg-chrome/50 shadow-2xl">
              <Image
                src="/main.png"
                alt="Blur Browser main window"
                fill
                sizes="(min-width: 1024px) 1024px, 100vw"
                className="object-cover"
                priority
              />
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
