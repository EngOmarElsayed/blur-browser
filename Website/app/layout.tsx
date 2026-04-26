import type { Metadata, Viewport } from "next";
import { Analytics } from "@vercel/analytics/next";
import { ThemeProvider } from "@/components/ThemeProvider";
import { Header } from "@/components/Header";
import { Footer } from "@/components/Footer";
import { JsonLd } from "@/components/JsonLd";
import "./globals.css";

const SITE_URL = "https://blurbrowser.app";

// Kept under 160 characters so Google doesn't truncate it in SERPs.
// Voice mirrors the home-page hero: leads with the calm/experience pitch,
// safety as a quiet "and also" — the new umbrella positioning.
const DESCRIPTION =
  "A calm, safer macOS browser. Vertical tabs, seven themes, ⌘K, Zen mode — with on-device AI that softens adult content automatically. Built on WebKit.";

// Slightly longer Twitter/OG description — these surfaces don't truncate as
// aggressively, so we have room for the full umbrella pitch.
const SOCIAL_DESCRIPTION =
  "Calm by design. Safe by default. A native macOS browser with vertical tabs, seven themes, ⌘K, and Zen mode — plus on-device AI that softens adult content automatically. Free and open source.";

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
    "on-device AI browser",
    "adult content blur",
    "AI content filter",
    "content filtering browser",
    "private browser",
    "open source browser",
    "mac browser",
    "Safari alternative",
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
    description: SOCIAL_DESCRIPTION,
    locale: "en_US",
    images: [
      {
        url: "/poster.jpg",
        width: 1554,
        height: 1080,
        alt: "Blur Browser on macOS — on-device AI softens adult images and videos in real time",
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
    title: "Blur Browser — A calmer, safer macOS browser",
    description: SOCIAL_DESCRIPTION,
    images: ["/poster.jpg"],
    creator: "@EngOmarElsayed",
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
