// Runs in every game page. Games are played by tapping, sometimes fast, so pages act like an app here rather
// than a web page: quick taps don't zoom in, and taps don't flash, select text or pop up a menu. Text fields
// work as usual.
(() => {
  if (window.__dailyGamesTouch) return;
  window.__dailyGamesTouch = true;

  // :where() has no specificity, so anything a game sets for itself still wins.
  try {
    const sheet = new CSSStyleSheet();
    sheet.replaceSync(`
      :where(html) { touch-action: manipulation; -webkit-tap-highlight-color: transparent; }
      :where(body) { -webkit-user-select: none; user-select: none; -webkit-touch-callout: none; }
      :where(input, textarea, select, [contenteditable]:not([contenteditable="false"])) {
        -webkit-user-select: text; user-select: text; -webkit-touch-callout: default;
      }
    `);
    document.adoptedStyleSheets = [...document.adoptedStyleSheets, sheet];
  } catch (e) {}

  // A page made for phones doesn't zoom at all, so tapping twice, or into a small text field, can't zoom it.
  // Pages that say how far they zoom keep their own setting.
  const fixViewport = () => {
    for (const meta of document.querySelectorAll('meta[name="viewport" i]')) {
      const content = meta.getAttribute("content") || "";
      if (!/width\s*=\s*device-width/i.test(content) || /maximum-scale|user-scalable/i.test(content)) continue;
      meta.setAttribute("content", `${content}, maximum-scale=1, user-scalable=no`);
    }
  };
  const watch = () => {
    fixViewport();
    if (!document.head) return;
    new MutationObserver(fixViewport).observe(document.head, {
      childList: true, subtree: true, attributes: true, attributeFilter: ["content", "name"],
    });
  };
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", watch, { once: true });
  } else {
    watch();
  }
})();
