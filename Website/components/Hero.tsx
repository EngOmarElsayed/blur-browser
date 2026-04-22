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
              href="#"
              className="rounded-full bg-accent px-6 py-3 text-sm font-semibold text-white shadow-sm hover:opacity-90 transition"
            >
              Download for macOS
            </a>
            <Link
              href="/#features"
              className="rounded-full border border-border/70 bg-chrome/70 px-6 py-3 text-sm font-semibold text-foreground hover:bg-chrome transition"
            >
              See features
            </Link>
          </div>

          <div className="mt-16 w-full max-w-4xl">
            <div className="aspect-[16/10] w-full rounded-2xl border border-border/60 bg-chrome/50 shadow-2xl overflow-hidden">
              {/* Placeholder: drop a real screenshot at /public/screenshots/hero.png and swap this. */}
              <div className="h-full w-full flex items-center justify-center text-foreground/40 text-sm">
                App screenshot
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
