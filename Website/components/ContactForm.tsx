"use client";

import { useState } from "react";

const WEB3FORMS_ACCESS_KEY =
  process.env.NEXT_PUBLIC_WEB3FORMS_KEY ?? "9e18876f-70da-44ef-a8ba-a7038f6204af";

type Status = "idle" | "submitting" | "success" | "error";

export function ContactForm() {
  const [status, setStatus] = useState<Status>("idle");
  const [errorMessage, setErrorMessage] = useState("");

  async function onSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setStatus("submitting");
    setErrorMessage("");

    const formData = new FormData(e.currentTarget);
    formData.append("access_key", WEB3FORMS_ACCESS_KEY);
    formData.append("from_name", "Blur Browser Website");
    formData.append("subject", "New message from Blur Browser website");

    try {
      const res = await fetch("https://api.web3forms.com/submit", {
        method: "POST",
        body: formData,
      });
      const data = await res.json();
      if (data.success) {
        setStatus("success");
        (e.target as HTMLFormElement).reset();
      } else {
        setStatus("error");
        setErrorMessage(data.message || "Something went wrong. Please try again.");
      }
    } catch (err) {
      setStatus("error");
      setErrorMessage("Network error. Please try again.");
    }
  }

  return (
    <form onSubmit={onSubmit} className="space-y-5">
      {/* Honeypot */}
      <input type="checkbox" name="botcheck" className="hidden" tabIndex={-1} readOnly />

      <div className="grid gap-5 sm:grid-cols-2">
        <Field label="Your name" name="name" type="text" required />
        <Field label="Email address" name="email" type="email" required />
      </div>

      <Field label="Subject" name="user_subject" type="text" required />

      <div>
        <label className="mb-1.5 block text-sm font-medium text-foreground">Message</label>
        <textarea
          name="message"
          required
          rows={6}
          className="w-full resize-none rounded-xl border border-border/70 bg-surface px-4 py-3 text-sm text-foreground placeholder:text-foreground/40 focus:border-accent focus:outline-none focus:ring-2 focus:ring-accent/30 transition"
          placeholder="Tell us what's on your mind…"
        />
      </div>

      <div className="flex items-center justify-between gap-4">
        <button
          type="submit"
          disabled={status === "submitting"}
          className="rounded-full bg-accent px-6 py-3 text-sm font-semibold text-white shadow-sm hover:opacity-90 disabled:opacity-60 transition"
        >
          {status === "submitting" ? "Sending…" : "Send message"}
        </button>

        {status === "success" && (
          <p className="text-sm font-medium text-accent">
            Thanks — we'll get back to you soon.
          </p>
        )}
        {status === "error" && (
          <p className="text-sm font-medium text-red-500">{errorMessage}</p>
        )}
      </div>
    </form>
  );
}

function Field({
  label,
  name,
  type,
  required,
}: {
  label: string;
  name: string;
  type: string;
  required?: boolean;
}) {
  return (
    <div>
      <label className="mb-1.5 block text-sm font-medium text-foreground">{label}</label>
      <input
        type={type}
        name={name}
        required={required}
        className="w-full rounded-xl border border-border/70 bg-surface px-4 py-3 text-sm text-foreground placeholder:text-foreground/40 focus:border-accent focus:outline-none focus:ring-2 focus:ring-accent/30 transition"
      />
    </div>
  );
}
