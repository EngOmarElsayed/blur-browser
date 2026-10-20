(async () => {
  const [tab] = await browser.tabs.query({ active: true, currentWindow: true });
  document.getElementById("title").textContent = tab?.title ?? "(no tab)";
  document.getElementById("url").textContent = tab?.url ?? "";
  const { pages = 0 } = await browser.storage.local.get("pages");
  const all = await browser.tabs.query({});
  document.getElementById("stats").textContent = `${all.length} tabs open · content script ran on ${pages} pages`;

  document.getElementById("highlight").addEventListener("click", async () => {
    try {
      const reply = await browser.tabs.sendMessage(tab.id, { type: "highlight" });
      document.getElementById("result").textContent = `Outlined “${reply.title}” (${reply.links} links)`;
    } catch (e) {
      document.getElementById("result").textContent = `No content script on this page: ${e.message}`;
    }
  });
})();
