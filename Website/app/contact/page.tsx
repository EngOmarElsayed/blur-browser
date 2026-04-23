import { ContactForm } from "@/components/ContactForm";

import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Contact",
  description:
    "Get in touch with the Blur Browser team. Report a bug, suggest a feature, or just say hi — we read every message.",
  alternates: { canonical: "/contact" },
  openGraph: {
    title: "Contact · Blur Browser",
    description:
      "Get in touch with the Blur Browser team. Report a bug, suggest a feature, or just say hi.",
    url: "https://blurbrowser.app/contact",
    type: "website",
  },
};

export default function ContactPage() {
  return (
    <section className="mx-auto max-w-3xl px-6 py-20">
      <div className="mb-10 text-center">
        <div className="mb-4 text-xs font-semibold uppercase tracking-widest text-accent">
          Contact
        </div>
        <h1 className="text-4xl font-semibold tracking-tight text-foreground sm:text-5xl">
          Get in touch.
        </h1>
        <p className="mt-4 text-lg text-foreground/70">
          Bug reports, feature requests, partnerships, or just to say hi — we read every message.
        </p>
      </div>

      <div className="rounded-2xl border border-border/60 bg-chrome/30 p-6 sm:p-10 shadow-sm">
        <ContactForm />
      </div>

      <p className="mt-6 text-center text-xs text-foreground/50">
        Powered by{" "}
        <a
          href="https://web3forms.com"
          target="_blank"
          rel="noreferrer"
          className="underline underline-offset-2 hover:text-foreground"
        >
          Web3Forms
        </a>
        . Set <code className="rounded bg-chrome/60 px-1">NEXT_PUBLIC_WEB3FORMS_KEY</code> in{" "}
        <code className="rounded bg-chrome/60 px-1">.env.local</code>.
      </p>
    </section>
  );
}
