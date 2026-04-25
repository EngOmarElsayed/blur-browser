import type { Metadata } from "next";
import { About } from "@/components/About";

const ABOUT_DESCRIPTION =
  "Why I built Blur Browser. A note from Omar Elsayed about Google Safe Search, an autoplaying thumbnail, and the calmer macOS browser I wished I'd had.";

export const metadata: Metadata = {
  title: "About",
  description: ABOUT_DESCRIPTION,
  alternates: { canonical: "/about" },
  openGraph: {
    title: "About · Blur Browser",
    description: ABOUT_DESCRIPTION,
    url: "https://blurbrowser.app/about",
    type: "article",
    authors: ["Omar Elsayed"],
  },
  twitter: {
    card: "summary_large_image",
    title: "About · Blur Browser",
    description: ABOUT_DESCRIPTION,
  },
};

export default function AboutPage() {
  return <About />;
}
