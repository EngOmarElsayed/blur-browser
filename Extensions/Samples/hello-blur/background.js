// Badge = number of open tabs, refreshed as tabs open and close.
async function updateBadge() {
  const tabs = await browser.tabs.query({});
  await browser.action.setBadgeText({ text: String(tabs.length) });
}
browser.tabs.onCreated.addListener(updateBadge);
browser.tabs.onRemoved.addListener(updateBadge);
browser.runtime.onInstalled.addListener(updateBadge);
browser.runtime.onStartup.addListener(updateBadge);
updateBadge();

browser.runtime.onMessage.addListener((message) => {
  if (message?.type === "content-ready") {
    return browser.storage.local.get("pages").then(({ pages = 0 }) =>
      browser.storage.local.set({ pages: pages + 1 }));
  }
});
