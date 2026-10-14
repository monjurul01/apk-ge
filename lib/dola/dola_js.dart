/// The in-page driver script.
///
/// Runs inside the real dola.com document via `callAsyncJavaScript`, so every
/// request it triggers is made by Dola's own page code: the page keeps its
/// own cookies, its own headers and its own request signing. We only move
/// the cursor, so to speak - type the prompt, press send, read the result.
///
/// Returns `{ok: true, url, width, height, model}` or `{ok: false, code,
/// detail}` where `code` maps onto [GenerationErrorKind].
library;

/// Arguments supplied by Dart: `prompt` (String), `cfg` (selector map),
/// `timeoutMs` (int).
const dolaDriverJs = r'''
const pick = (sels) => {
  for (const s of (sels || [])) {
    try {
      const el = document.querySelector(s);
      if (el) return el;
    } catch (e) { /* invalid selector from user override - skip */ }
  }
  return null;
};

const pickAll = (sels) => {
  const out = [];
  for (const s of (sels || [])) {
    try {
      document.querySelectorAll(s).forEach((e) => out.push(e));
    } catch (e) { /* skip */ }
  }
  return out;
};

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const looksLikeResult = (src) => {
  if (!src) return false;
  if (src.startsWith('data:') || src.startsWith('blob:')) return false;
  return (cfg.imageHostHints || []).some((h) => src.indexOf(h) >= 0);
};

// A generated wallpaper is never a 32px avatar. Dola's transcript is full of
// bot icons served from the same CDN, so size is the only reliable filter.
const bigEnough = (img) => (img.naturalWidth || 0) >= 256 && (img.naturalHeight || 0) >= 256;

const srcOf = (img) => img.currentSrc || img.src || '';

// --- 0. Refuse early if the page is not usable -------------------------
if (location.pathname.indexOf('region-restricted') >= 0) {
  return { ok: false, code: 'region_blocked', detail: location.href };
}
if (pick(cfg.loginWall)) {
  return { ok: false, code: 'signed_out', detail: 'login wall present' };
}

// --- 1. Find the composer ----------------------------------------------
const composer = pick(cfg.composer);
if (!composer) {
  return {
    ok: false,
    code: 'page_changed',
    detail: 'composer not found; tried: ' + (cfg.composer || []).join(' | '),
  };
}

// --- 2. Baseline the transcript so we only accept NEW images ------------
const before = new Set();
pickAll(cfg.resultImage).forEach((i) => before.add(srcOf(i)));
Array.from(document.images).forEach((i) => before.add(srcOf(i)));

// --- 3. Type the prompt -------------------------------------------------
// React controls these inputs, so assigning .value directly is swallowed on
// the next render. The native setter + input event is what React's
// onChange actually listens for; contenteditable needs execCommand so the
// editor's beforeinput handler runs.
const typeInto = (el, text) => {
  const tag = el.tagName;
  if (tag === 'TEXTAREA' || tag === 'INPUT') {
    const proto = tag === 'TEXTAREA'
      ? window.HTMLTextAreaElement.prototype
      : window.HTMLInputElement.prototype;
    const setter = Object.getOwnPropertyDescriptor(proto, 'value').set;
    el.focus();
    setter.call(el, text);
    el.dispatchEvent(new Event('input', { bubbles: true }));
    el.dispatchEvent(new Event('change', { bubbles: true }));
  } else {
    el.focus();
    const range = document.createRange();
    range.selectNodeContents(el);
    const sel = window.getSelection();
    if (sel) {
      sel.removeAllRanges();
      sel.addRange(range);
    }
    document.execCommand('selectAll', false, null);
    document.execCommand('insertText', false, text);
    el.dispatchEvent(new Event('input', { bubbles: true }));
  }
};

try {
  typeInto(composer, prompt);
} catch (e) {
  return { ok: false, code: 'page_changed', detail: 'could not type: ' + e };
}

// Let React commit the change so the send button leaves its disabled state.
await sleep(250);

// --- 4. Send -------------------------------------------------------------
let sent = false;
const btn = pick(cfg.sendButton);
if (btn && !btn.disabled && btn.getAttribute('aria-disabled') !== 'true') {
  btn.click();
  sent = true;
}
if (!sent) {
  // Enter is the documented shortcut in Dola's own composer hint.
  const opts = { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true };
  composer.dispatchEvent(new KeyboardEvent('keydown', opts));
  composer.dispatchEvent(new KeyboardEvent('keyup', opts));
  sent = true;
}

// --- 5. Wait for a new, large image to settle ----------------------------
const deadline = Date.now() + timeoutMs;
let lastUrl = '';
let stableFor = 0;

while (Date.now() < deadline) {
  if (location.pathname.indexOf('region-restricted') >= 0) {
    return { ok: false, code: 'region_blocked', detail: location.href };
  }
  if (pick(cfg.loginWall)) {
    return { ok: false, code: 'signed_out', detail: 'logged out mid-request' };
  }
  const refused = pick(cfg.refusal);
  if (refused) {
    return {
      ok: false,
      code: 'rejected',
      detail: (refused.innerText || '').slice(0, 300),
    };
  }

  const candidates = pickAll(cfg.resultImage)
    .concat(Array.from(document.images))
    .filter((i) => !before.has(srcOf(i)))
    .filter((i) => looksLikeResult(srcOf(i)))
    .filter(bigEnough);

  if (candidates.length) {
    // Take the last one: Dola appends to the transcript.
    const img = candidates[candidates.length - 1];
    const url = srcOf(img);
    // The CDN swaps in a higher-resolution source once decoding finishes,
    // so only accept a URL that has stopped changing.
    if (url === lastUrl) {
      stableFor += 1;
      if (stableFor >= 3) {
        return {
          ok: true,
          url: url,
          width: img.naturalWidth || 0,
          height: img.naturalHeight || 0,
        };
      }
    } else {
      lastUrl = url;
      stableFor = 0;
    }
  }
  await sleep(500);
}

return {
  ok: false,
  code: 'timeout',
  detail: lastUrl ? 'image never stabilised: ' + lastUrl : 'no image appeared',
};
''';

/// Probe used before sending a prompt: reports whether the composer is
/// present, and whether the page is a login / region wall instead.
const dolaProbeJs = r'''
const pick = (sels) => {
  for (const s of (sels || [])) {
    try {
      const el = document.querySelector(s);
      if (el) return el;
    } catch (e) { /* skip */ }
  }
  return null;
};
if (location.pathname.indexOf('region-restricted') >= 0) {
  return { state: 'region_blocked', url: location.href };
}
if (pick(cfg.loginWall)) return { state: 'signed_out', url: location.href };
if (pick(cfg.composer)) return { state: 'ready', url: location.href };
return { state: 'not_ready', url: location.href, title: document.title };
''';

/// Fetches [url] from inside the page so the CDN sees Dola's own origin,
/// referer and cookies. Returns base64 - only used when a plain Dart
/// request is rejected, because the bridge hop is expensive.
const dolaFetchJs = r'''
try {
  const res = await fetch(url, { credentials: 'include', referrerPolicy: 'strict-origin-when-cross-origin' });
  if (!res.ok) return { ok: false, detail: 'HTTP ' + res.status };
  const buf = await res.arrayBuffer();
  const bytes = new Uint8Array(buf);
  let binary = '';
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    binary += String.fromCharCode.apply(null, bytes.subarray(i, i + chunk));
  }
  return { ok: true, b64: btoa(binary), type: res.headers.get('content-type') || '' };
} catch (e) {
  return { ok: false, detail: String(e) };
}
''';
