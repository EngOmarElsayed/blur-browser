const SITE_URL = "https://blurbrowser.app";
const REPO_URL = "https://github.com/EngOmarElsayed/blur-browser";

/**
 * Emits JSON-LD structured data for the Blur Browser site.
 *
 * Uses two linked graph nodes:
 *  - SoftwareApplication: describes the macOS browser itself (helps Google
 *    render a rich result with rating/price/OS requirements).
 *  - Organization: describes the project/author, wiring up the GitHub /
 *    sponsors profile as sameAs links for entity consolidation.
 *  - WebSite: enables the sitelinks search box in SERPs.
 */
export function JsonLd() {
  const graph = {
    "@context": "https://schema.org",
    "@graph": [
      {
        "@type": "SoftwareApplication",
        "@id": `${SITE_URL}/#software`,
        name: "Blur Browser",
        applicationCategory: "BrowserApplication",
        operatingSystem: "macOS 14 and later",
        description:
          "A native macOS browser that blurs adult images and videos automatically. Built on WebKit. Free and open source.",
        url: SITE_URL,
        downloadUrl: `${REPO_URL}/releases/latest`,
        softwareVersion: "0.8.0",
        offers: {
          "@type": "Offer",
          price: "0",
          priceCurrency: "USD",
        },
        featureList: [
          "Automatic blur for adult images and videos",
          "Vertical sidebar tab list",
          "7 built-in themes",
          "Keyboard shortcuts with ⌘+/ overview",
          "Quick Search (⌘K) across tabs, history, and the web",
          "Zen mode",
          "Website blocking (coming soon)",
          "Built on WebKit",
        ],
        author: { "@id": `${SITE_URL}/#author` },
        image: `${SITE_URL}/main.png`,
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
          "A calmer, safer macOS browser. Free and open source.",
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
