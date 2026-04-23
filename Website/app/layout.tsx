import type { Metadata, Viewport } from "next";
import { Analytics } from "@vercel/analytics/next";
import { ThemeProvider } from "@/components/ThemeProvider";
import { Header } from "@/components/Header";
import { Footer } from "@/components/Footer";
import { JsonLd } from "@/components/JsonLd";
import "./globals.css";

const SITE_URL = "https://blurbrowser.app";
const DESCRIPTION =
  "Blur Browser is a free, open-source macOS browser that automatically blurs adult images and videos as you browse. Built on WebKit. Private by default — no trackers, no telemetry.";

export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  title: {
    default: "Blur Browser — A calmer, safer macOS browser",
    template: "%s · Blur Browser",
  },
  description: DESCRIPTION,
  applicationName: "Blur Browser",
  generator: "Next.js",
  keywords: [
    "Blur Browser",
    "macOS browser",
    "WebKit browser",
    "adult content blur",
    "safe browser",
    "content filtering browser",
    "private browser",
    "open source browser",
    "mac browser",
    "Safari alternative",
    "distraction-free browser",
    "Zen mode browser",
  ],
  authors: [{ name: "Omar Elsayed", url: "https://github.com/EngOmarElsayed" }],
  creator: "Omar Elsayed",
  publisher: "Omar Elsayed",
  category: "technology",
  alternates: {
    canonical: "/",
  },
  manifest: "/site.webmanifest",
  icons: {
    icon: [
      { url: "/favicons/favicon-16x16.png", sizes: "16x16", type: "image/png" },
      { url: "/favicons/favicon-32x32.png", sizes: "32x32", type: "image/png" },
      { url: "/favicons/favicon-48x48.png", sizes: "48x48", type: "image/png" },
    ],
    apple: [{ url: "/favicons/apple-touch-icon.png", sizes: "180x180" }],
  },
  openGraph: {
    type: "website",
    url: SITE_URL,
    siteName: "Blur Browser",
    title: "Blur Browser — A calmer, safer macOS browser",
    description: DESCRIPTION,
    locale: "en_US",
    images: [
      {
        url: "/main.png",
        width: 2730,
        height: 1632,
        alt: "Blur Browser on macOS — automatically blurs adult content",
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
    title: "Blur Browser — A calmer, safer macOS browser",
    description:
      "A native macOS browser that blurs adult images and videos automatically. Built on WebKit. Free and open source.",
    images: ["/main.png"],
  },
  robots: {
    index: true,
    follow: true,
    googleBot: {
      index: true,
      follow: true,
      "max-image-preview": "large",
      "max-snippet": -1,
      "max-video-preview": -1,
    },
  },
  // Paste the verification token Google Search Console gives you (Settings →
  // Ownership verification → HTML tag). Pulled from env so you can set it in
  // Vercel without another code change.
  verification: {
    google: process.env.NEXT_PUBLIC_GOOGLE_SITE_VERIFICATION,
  },
};

export const viewport: Viewport = {
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#F4F7FE" },
    { media: "(prefers-color-scheme: dark)", color: "#13141C" },
  ],
  width: "device-width",
  initialScale: 1,
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body className="min-h-screen flex flex-col">
        <JsonLd />
        <ThemeProvider>
          <Header />
          <main className="flex-1">{children}</main>
          <Footer />
        </ThemeProvider>
        <Analytics />
      </body>
    </html>
  );
}
