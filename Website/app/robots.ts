import type { MetadataRoute } from "next";

const SITE_URL = "https://blurbrowser.app";

export default function robots(): MetadataRoute.Robots {
  return {
    rules: [
      {
        userAgent: "*",
        allow: "/",
        // Nothing sensitive to disallow, but a small list of paths that
        // shouldn't waste crawl budget.
        disallow: ["/api/", "/_next/", "/_vercel/"],
      },
    ],
    sitemap: `${SITE_URL}/sitemap.xml`,
    host: SITE_URL,
  };
}
