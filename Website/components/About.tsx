import Image from "next/image";
import Link from "next/link";

export function About() {
  return (
    <section id="about" className="border-t border-border/50 bg-chrome/30">
      <div className="mx-auto max-w-6xl px-6 py-24">
        <div className="grid gap-16 md:grid-cols-[1fr_1.5fr] md:gap-24">
          <div className="flex flex-col items-start">
            <div className="mb-4 text-xs font-semibold uppercase tracking-widest text-accent">
              A note from the maker
            </div>
            <h2 className="text-3xl font-semibold tracking-tight text-foreground sm:text-4xl">
              Hi, I'm Omar.
            </h2>
            <p className="mt-4 text-base leading-relaxed text-foreground/70">
              Blur is the side project I couldn't stop thinking about.
            </p>

            <div
              className="relative mt-10"
              style={{
                filter: "drop-shadow(0 20px 40px rgb(var(--accent) / 0.25))",
              }}
            >
              <Image
                src="/logo.png"
                alt="Blur Browser icon"
                width={140}
                height={140}
                className="rounded-[32px]"
              />
            </div>
          </div>

          <div className="space-y-6 text-lg leading-relaxed text-foreground/80">
            <p>
              It started with a Google search. Something completely
              ordinary — Safe Search turned on, the way it's supposed to be —
              and the image results still had things in them I didn't want to
              see. The setting that's supposed to be the seatbelt of the
              internet, and it just… didn't work. I remember thinking:{" "}
              <em>
                if Google can't get this right, with all their data and
                engineers, what's actually keeping any of us safe?
              </em>
            </p>

            <p>
              I went looking for a real fix. Browser extensions exist, but
              they're brittle and you're trusting whoever maintains them —
              same problem as Safe Search, smaller team. Parental control
              software is clunky and assumes you're protecting someone else,
              not yourself. Nothing felt like the calm, deliberate thing I'd
              actually want to use every day.
            </p>

            <p>
              So I started building. I'm an iOS and macOS engineer by trade —
              Swift, AppKit, SwiftUI, the whole Apple stack — and Blur is
              everything I love about my craft poured into a single app.
              Native macOS. WebKit under the hood. On-device AI running on
              your GPU. Design that doesn't shout. No third-party
              dependencies. No tracking. No upsells, ever.
            </p>

            <p>
              It will always be{" "}
              <strong className="text-foreground">free</strong>. It will
              always be{" "}
              <strong className="text-foreground">open source</strong>. It
              will always be the browser I wish I'd had a year ago.
            </p>

            <p>
              If Blur makes your browsing a little calmer, that's the whole
              point. If it doesn't, tell me why — I read every message.
            </p>

            <p className="pt-2 font-medium text-foreground">— Omar Elsayed</p>

            <div className="flex flex-wrap items-center gap-3 pt-6">
              <a
                href="https://github.com/EngOmarElsayed/blur-browser"
                target="_blank"
                rel="noreferrer"
                className="rounded-full border border-border/70 bg-surface px-5 py-2.5 text-sm font-semibold text-foreground transition hover:bg-chrome"
              >
                ⭐ Star on GitHub
              </a>
              <a
                href="https://github.com/sponsors/EngOmarElsayed"
                target="_blank"
                rel="noreferrer"
                className="rounded-full bg-accent px-5 py-2.5 text-sm font-semibold text-white shadow-sm transition hover:opacity-90"
              >
                💖 Sponsor the project
              </a>
              <Link
                href="/contact"
                className="rounded-full border border-border/70 bg-surface px-5 py-2.5 text-sm font-semibold text-foreground transition hover:bg-chrome"
              >
                Send me a note
              </Link>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
