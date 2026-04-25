import { getLatestRelease } from "@/lib/github";

const SITE_URL = "https://blurbrowser.app";
const REPO_URL = "https://github.com/EngOmarElsayed/blur-browser";

/**
 * Emits JSON-LD structured data for the Blur Browser site.
 *
 * Three linked nodes:
 *  - SoftwareApplication: describes the macOS browser itself, so Google can
 *    render a rich app card (rating, price, OS, version). softwareVersion
 *    is pulled live from the latest GitHub release so we never ship stale
 *    metadata.
 *  - Organization: describes the maker, wiring up GitHub + Sponsors as
 *    sameAs links so Google consolidates the entity.
 *  - WebSite: makes the site eligible for the SERP sitelinks search box.
 */
export async function JsonLd() {
  const release = await getLatestRelease();

  const graph = {
    "@context": "https://schema.org",
    "@graph": [
      {
        "@type": "SoftwareApplication",
        "@id": `${SITE_URL}/#software`,
        name: "Blur Browser",
        applicationCategory: "BrowserApplication",
        applicationSubCategory: "WebBrowser",
        operatingSystem: "macOS 14 and later",
        description:
          "A native macOS browser. On-device AI softens adult images and videos in real time, on your GPU. Built on WebKit. Free and open source.",
        url: SITE_URL,
        downloadUrl: `${REPO_URL}/releases/latest`,
        softwareVersion: release.version,
        releaseNotes: release.notesUrl,
        offers: {
          "@type": "Offer",
          price: "0",
          priceCurrency: "USD",
        },
        featureList: [
          "On-device AI that softens adult images and videos in real time",
          "GPU-accelerated detection — no server round-trips",
          "Vertical sidebar tab list",
          "Seven hand-crafted themes",
          "Keyboard shortcuts with ⌘+/ overview",
          "Quick Search (⌘K) across tabs, history, and the web",
          "Zen mode for distraction-free browsing",
          "Built on WebKit — fast, battery-friendly, web-standards-honest",
          "Open source under MIT — no trackers, no telemetry",
        ],
        author: { "@id": `${SITE_URL}/#author` },
        image: `${SITE_URL}/poster.jpg`,
      },
      {
        "@type": "Organization",
        "@id": `${SITE_URL}/#author`,
        name: "Omar Elsayed",
        url: "https://github.com/EngOmarElsayed",
        logo: `${SITE_URL}/logo.png`,
        sameAs: [
          "https://github.com/EngOmarElsayed",
          "https://github.com/sponsors/EngOmarElsayed",
          REPO_URL,
        ],
      },
      {
        "@type": "WebSite",
        "@id": `${SITE_URL}/#website`,
        url: SITE_URL,
        name: "Blur Browser",
        description:
          "A calmer, safer macOS browser. On-device AI by default. Free and open source.",
        publisher: { "@id": `${SITE_URL}/#author` },
        inLanguage: "en",
      },
    ],
  };

  return (
    <script
      type="application/ld+json"
      // Safe: we control the JSON shape above.
      dangerouslySetInnerHTML={{ __html: JSON.stringify(graph) }}
    />
  );
}
