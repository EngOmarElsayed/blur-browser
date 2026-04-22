import type { Metadata } from "next";
import { Analytics } from "@vercel/analytics/next";
import { ThemeProvider } from "@/components/ThemeProvider";
import { Header } from "@/components/Header";
import { Footer } from "@/components/Footer";
import "./globals.css";

export const metadata: Metadata = {
  metadataBase: new URL("https://blurbrowser.app"),
  title: "Blur Browser — A calmer, safer web",
  description:
    "A native macOS browser that blurs adult content automatically. Built on WebKit. Free and open source.",
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
    url: "https://blurbrowser.app",
    siteName: "Blur Browser",
    title: "Blur Browser — A calmer, safer web",
    description:
      "A native macOS browser that blurs adult content automatically. Built on WebKit. Free and open source.",
    locale: "en_US",
    images: [
      {
        url: "/main.png",
        width: 2730,
        height: 1632,
        alt: "Blur Browser on macOS — a calmer, safer web",
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
    title: "Blur Browser — A calmer, safer web",
    description:
      "A native macOS browser that blurs adult content automatically. Built on WebKit.",
    images: ["/main.png"],
  },
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body className="min-h-screen flex flex-col">
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
