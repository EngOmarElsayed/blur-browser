export interface LatestRelease {
  tag: string;
  version: string; // tag without leading "v"
  dmgUrl: string;
  notesUrl: string;
  publishedAt: string | null;
}

const REPO = "EngOmarElsayed/blur-browser";

// Used only if the GitHub API is unreachable at build/revalidate time.
// The .github/workflows/release-revalidate.yml workflow keeps this in sync
// automatically — it bumps the constant on every release publish so we
// never serve stale fallback data even if api.github.com is down for a while.
const FALLBACK: LatestRelease = {
  tag: "v0.8.2",
  version: "0.8.2",
  dmgUrl: `https://github.com/${REPO}/releases/download/v0.8.2/Blur-Browser-v0.8.2.dmg`,
  notesUrl: `https://github.com/${REPO}/releases/tag/v0.8.2`,
  publishedAt: null,
};

interface GithubAsset {
  name: string;
  browser_download_url: string;
}

interface GithubRelease {
  tag_name: string;
  html_url: string;
  published_at: string;
  assets: GithubAsset[];
  draft: boolean;
  prerelease: boolean;
}

/**
 * Fetches the latest GitHub release for the repo. Used by the Hero component
 * to always link to the current version's .dmg without a code change.
 *
 * Revalidated hourly (Next.js ISR), so within an hour of publishing a new
 * release the live site picks it up automatically.
 */
export async function getLatestRelease(): Promise<LatestRelease> {
  try {
    const res = await fetch(`https://api.github.com/repos/${REPO}/releases/latest`, {
      headers: {
        Accept: "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
      },
      next: { revalidate: 3600 },
    });
    if (!res.ok) throw new Error(`GitHub API ${res.status}`);

    const data = (await res.json()) as GithubRelease;
    const tag = data.tag_name;
    const version = tag.replace(/^v/, "");
    const dmg = data.assets.find((a) => a.name.toLowerCase().endsWith(".dmg"));

    if (!dmg) {
      // Release exists but has no .dmg yet (e.g. still uploading). Fall back
      // so the download button isn't broken.
      return FALLBACK;
    }

    return {
      tag,
      version,
      dmgUrl: dmg.browser_download_url,
      notesUrl: data.html_url,
      publishedAt: data.published_at,
    };
  } catch (err) {
    console.warn("[github] getLatestRelease failed, using fallback:", err);
    return FALLBACK;
  }
}
