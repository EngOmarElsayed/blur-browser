// Tells the background a page ran the content script; the popup can ask us to
// outline the page so you can see injection worked.
browser.runtime.sendMessage({ type: "content-ready", url: location.href });
browser.runtime.onMessage.addListener((message) => {
  if (message?.type === "highlight") {
    document.documentElement.style.outline = "6px solid #4A9FD8";
    document.documentElement.style.outlineOffset = "-6px";
    return Promise.resolve({ title: document.title, links: document.links.length });
  }
});
