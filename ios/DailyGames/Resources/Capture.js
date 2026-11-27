// Runs in every game page before the game's own scripts. When a game shares or copies its result, the text goes
// to the app (GameBrowser), which adds it to today's list. Copying still copies as usual.
(() => {
  if (window.__dailyGames) return;
  window.__dailyGames = true;

  const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.dailyGames;
  if (!handler) return;

  const send = (kind, text) => {
    if (typeof text !== "string" || !text.trim()) return false;
    try {
      handler.postMessage({ kind, text });
      return true;
    } catch (e) {
      return false;
    }
  };
  const define = (target, name, value) => {
    try {
      Object.defineProperty(target, name, { value, configurable: true, writable: true });
    } catch (e) {}
  };

  // What a share would have put on the clipboard: the text, then the link if the text doesn't already have it.
  const shareText = (data) => {
    if (!data || typeof data !== "object") return "";
    const text = typeof data.text === "string" ? data.text.trim() : "";
    const url = typeof data.url === "string" ? data.url.trim() : String(data.url || "").trim();
    const joined = [text, url && !text.includes(url) ? url : ""].filter(Boolean).join("\n");
    return joined || (typeof data.title === "string" ? data.title.trim() : "");
  };

  // Share: the result comes straight to the app instead of opening a share sheet. Games check for this to
  // decide whether to share or copy, so it's always there.
  const share = navigator.share ? navigator.share.bind(navigator) : null;
  const canShare = navigator.canShare ? navigator.canShare.bind(navigator) : null;
  define(navigator, "share", function (data) {
    if (send("share", shareText(data))) return Promise.resolve();
    if (share) return share(data);
    return Promise.reject(new DOMException("Sharing isn't available.", "NotAllowedError"));
  });
  define(navigator, "canShare", function (data) {
    if (shareText(data)) return true;
    return canShare ? canShare(data) : false;
  });

  // Copy, the modern way.
  const clipboard = navigator.clipboard;
  if (clipboard) {
    const writeText = clipboard.writeText ? clipboard.writeText.bind(clipboard) : null;
    define(clipboard, "writeText", function (text) {
      send("copy", String(text));
      return writeText ? writeText(text).catch(() => {}) : Promise.resolve();
    });
    const write = clipboard.write ? clipboard.write.bind(clipboard) : null;
    define(clipboard, "write", function (items) {
      try {
        const item = Array.from(items || []).find((i) => i && i.types && i.types.includes("text/plain"));
        if (item) item.getType("text/plain").then((blob) => blob.text()).then((t) => send("copy", t)).catch(() => {});
      } catch (e) {}
      return write ? write(items).catch(() => {}) : Promise.resolve();
    });
  }

  // Copy, the old way: select some text, or set it in a copy event, then execCommand("copy").
  const execCommand = document.execCommand.bind(document);
  define(document, "execCommand", function (command, ...rest) {
    if (String(command).toLowerCase() !== "copy") return execCommand(command, ...rest);
    let set = null;
    const setData = DataTransfer.prototype.setData;
    DataTransfer.prototype.setData = function (type, data) {
      if (/^text(\/plain)?$/i.test(type)) set = String(data);
      return setData.call(this, type, data);
    };
    let selected = "";
    try {
      const el = document.activeElement;
      selected = el && typeof el.value === "string" && typeof el.selectionStart === "number"
        ? el.value.slice(el.selectionStart, el.selectionEnd)
        : String(window.getSelection() || "");
    } catch (e) {}
    try {
      return execCommand(command, ...rest);
    } finally {
      DataTransfer.prototype.setData = setData;
      send("copy", set !== null ? set : selected);
    }
  });
})();
