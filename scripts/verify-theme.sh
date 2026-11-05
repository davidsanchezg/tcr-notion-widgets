#!/usr/bin/env bash
# verify-theme.sh — checks the OS-following dark/light contract on every Pages HTML file:
#   1. files exist and parse
#   2. the <head> theme resolver is identical on every page, runs before first <style>, has the matchMedia default-auto path
#   3. light/dark token palettes match the spec exactly; page-local surface tokens (declared pages only) match exactly
#   4. no light-only hardcoded neutrals or SVG track/text colors outside the token/resolver blocks
#   5. resolver fixtures (run in a vm sandbox): default auto, locks, live OS change, strict postMessage origins
#   6. index.html passes an explicit light/dark lock through to the preview iframes
#   7. multi-ring loop reload keeps location.hash (hash locks survive the pulse loop)
# Usage: scripts/verify-theme.sh      Exit 0 = all pass · 1 = a check failed · 2 = node missing
# Needs node only (no npm deps).
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v node >/dev/null 2>&1; then
  echo "verify-theme: node not found on PATH (required; no npm deps)" >&2
  exit 2
fi

export VERIFY_THEME_ROOT="$ROOT"
exec node - <<'JS'
'use strict';
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const ROOT = process.env.VERIFY_THEME_ROOT;
const FILES = [
  'index.html',
  'widgets/tcr-glance/index.html',
  'widgets/ring-test/index.html',
  'widgets/bars-test/index.html',
  'widgets/gauge-test/index.html',
  'widgets/multi-ring/index.html',
  'widgets/controls-test/index.html',
];
const TRUSTED_LITERAL = '^https:\\/\\/([a-z0-9-]+\\.)?(notion\\.so|notion\\.site)$';
const LIGHT = { '--bg': '#ffffff', '--card': '#f7f6f3', '--line': '#e9e9e7', '--track': '#ecebea', '--ink': '#37352f', '--muted': '#787774' };
const DARK = { '--bg': '#191919', '--card': '#202020', '--line': '#373737', '--track': '#2f2f2f', '--ink': '#e6e6e6', '--muted': '#9b9b9b' };
const SVG_ATTR_RE = /\b(?:stroke|fill)="#(?:ecebea|37352f|787774)"/gi;
const LEAK_RE = /#(?:ffffff|787774|37352f|ecebea|e9e9e7|f7f6f3|f1f1ef|e3e2e0|d3d1cb)(?![0-9a-f])/gi;
const RESOLVER_RE = /<!-- theme-resolver:start[^>]*-->([\s\S]*?)<!-- theme-resolver:end -->/g;
const TOKENS_RE = /\/\* theme-tokens:start \*\/([\s\S]*?)\/\* theme-tokens:end \*\//g;
const PAGE_TOKENS_RE = /\/\* page-tokens:start \*\/([\s\S]*?)\/\* page-tokens:end \*\//g;

const results = [];
function check(name, ok, detail) {
  results.push(Boolean(ok));
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}`);
  if (!ok && detail) console.log(`      ${detail}`);
}
const read = (rel) => { try { return fs.readFileSync(path.join(ROOT, rel), 'utf8'); } catch (e) { return ''; } };
const inlineScripts = (html) => [...html.matchAll(/<script(\s[^>]*)?>([\s\S]*?)<\/script>/gi)]
  .filter((m) => !/\ssrc\s*=/i.test(m[1] || ''))
  .map((m) => m[2]);
const blankBlocks = (html) => html
  .replace(RESOLVER_RE, (m) => '\n'.repeat(m.split('\n').length - 1))
  .replace(TOKENS_RE, (m) => '\n'.repeat(m.split('\n').length - 1))
  .replace(PAGE_TOKENS_RE, (m) => '\n'.repeat(m.split('\n').length - 1));
const lineHits = (text, re) => {
  const flags = re.flags.replace('g', '');
  const out = [];
  text.split('\n').forEach((ln, i) => { if (new RegExp(re.source, flags).test(ln)) out.push(`line ${i + 1}: ${ln.trim()}`); });
  return out;
};
const sameTokens = (got, want) => Object.keys(want).every((k) => got[k] === want[k]) && Object.keys(got).length === Object.keys(want).length;

// ---- 1. files exist and parse -------------------------------------------------
const html = {};
for (const rel of FILES) html[rel] = read(rel);
const widgetDirs = fs.readdirSync(path.join(ROOT, 'widgets'), { withFileTypes: true }).filter((d) => d.isDirectory()).map((d) => `widgets/${d.name}/index.html`);
check(`${FILES.length} HTML files exist, non-empty, contain <html> (and every widgets/*/index.html is covered)`,
  FILES.every((rel) => /<html[\s>]/i.test(html[rel])) && widgetDirs.every((rel) => FILES.includes(rel)),
  `missing or uncovered: ${FILES.filter((r) => !/<html[\s>]/i.test(html[r])).concat(widgetDirs.filter((r) => !FILES.includes(r))).join(', ')}`);
for (const rel of FILES) {
  const t = html[rel];
  let err = '';
  if (!/<body[\s>]/i.test(t) || !/<\/body>/i.test(t) || !/<\/html>/i.test(t)) err = 'missing <body>/</html>';
  for (const src of inlineScripts(t)) { try { new vm.Script(src, { filename: rel }); } catch (e) { err = err || e.message; } }
  check(`parses (markup + inline JS syntax): ${rel}`, !err, err);
}

// ---- 2. resolver present, identical, before paint -----------------------------
const blocks = {};
for (const rel of FILES) {
  const found = [...html[rel].matchAll(RESOLVER_RE)];
  if (found.length !== 1) { check(`resolver block present exactly once: ${rel}`, false, `found ${found.length}`); continue; }
  const block = found[0][1];
  blocks[rel] = block;
  const t = html[rel];
  check(`resolver sits in <head> before first <style>: ${rel}`,
    t.indexOf('theme-resolver:start') < t.indexOf('<style>') && t.indexOf('theme-resolver:end') < t.indexOf('</head>'));
  check(`resolver has matchMedia default-auto path + live change listener: ${rel}`,
    block.includes("window.matchMedia('(prefers-color-scheme: dark)')") && block.includes("mq.addEventListener('change',onMedia)"));
  check(`resolver origin regex present and strict: ${rel}`, block.includes(TRUSTED_LITERAL));
  check(`resolver sets dataset.theme, dataset.themeMode, style.colorScheme: ${rel}`,
    ['root.dataset.theme=', 'root.dataset.themeMode=', 'root.style.colorScheme='].every((s) => block.includes(s)));
}
const blockRels = Object.keys(blocks);
check(`resolver identical across all ${FILES.length} pages`,
  blockRels.length === FILES.length && blockRels.every((r) => blocks[r] === blocks[blockRels[0]]),
  'resolver blocks differ between pages');

// ---- 3. token palettes --------------------------------------------------------
for (const rel of FILES) {
  const found = [...html[rel].matchAll(TOKENS_RE)];
  if (found.length !== 1) { check(`token block present exactly once: ${rel}`, false, `found ${found.length}`); continue; }
  const css = found[0][1];
  const light = /:root,:root\[data-theme="light"\]\{([^}]*)\}/.exec(css);
  const dark = /:root\[data-theme="dark"\]\{([^}]*)\}/.exec(css);
  const parse = (s) => Object.fromEntries([...s.matchAll(/(--[a-z]+)\s*:\s*(#[0-9a-f]{6})/gi)].map((m) => [m[1].toLowerCase(), m[2].toLowerCase()]));
  check(`light + dark CSS tokens match spec (incl. color-scheme): ${rel}`,
    light && dark && sameTokens(parse(light[1]), LIGHT) && sameTokens(parse(dark[1]), DARK)
      && /color-scheme:light/.test(light[1]) && /color-scheme:dark/.test(dark[1]),
    'token values differ from spec');
}

// ---- 3b. page-local surface tokens: only declared pages, exact production values ----
const PAGE_TOKENS = {
  'widgets/controls-test/index.html': {
    light: { '--toggle-off': '#e3e2e0', '--pill-off': '#f1f1ef' },
    dark: { '--toggle-off': '#2f2f2f', '--pill-off': '#252525' },
  },
  'widgets/gauge-test/index.html': {
    light: { '--tick': '#d3d1cb' },
    dark: { '--tick': '#4a4a4a' },
  },
};
for (const rel of Object.keys(PAGE_TOKENS)) {
  const found = [...html[rel].matchAll(PAGE_TOKENS_RE)];
  if (found.length !== 1) { check(`page-local token block present exactly once: ${rel}`, false, `found ${found.length}`); continue; }
  const css = found[0][1];
  const light = /:root,:root\[data-theme="light"\]\{([^}]*)\}/.exec(css);
  const dark = /:root\[data-theme="dark"\]\{([^}]*)\}/.exec(css);
  const parse = (s) => Object.fromEntries([...s.matchAll(/(--[a-z-]+)\s*:\s*(#[0-9a-f]{6})/gi)].map((m) => [m[1].toLowerCase(), m[2].toLowerCase()]));
  check(`page-local tokens match production light + dark values: ${rel}`,
    light && dark && sameTokens(parse(light[1]), PAGE_TOKENS[rel].light) && sameTokens(parse(dark[1]), PAGE_TOKENS[rel].dark),
    'page-local token values differ from spec');
}
const undeclaredPageTokens = FILES.filter((rel) => !PAGE_TOKENS[rel] && [...html[rel].matchAll(PAGE_TOKENS_RE)].length > 0);
check('page-local token blocks only in declared pages', undeclaredPageTokens.length === 0,
  `undeclared page-local token block: ${undeclaredPageTokens.join(', ')}`);

// ---- 4. no light-only hardcoded neutrals / SVG track+text colors ---------------
for (const rel of FILES) {
  const scan = blankBlocks(html[rel]);
  const hits = [...lineHits(scan, SVG_ATTR_RE), ...lineHits(scan, LEAK_RE)];
  check(`no hardcoded light-only neutrals or SVG track/text colors: ${rel}`, hits.length === 0, hits.join('\n      '));
}

// ---- 5. resolver fixtures in a vm sandbox -------------------------------------
function runResolver(src, { search = '', hash = '', osDark = false }) {
  const documentElement = { dataset: {}, style: {} };
  const mq = {
    matches: osDark,
    query: null,
    changeListeners: [],
    addEventListener(type, fn) { if (type === 'change') this.changeListeners.push(fn); },
  };
  const messageListeners = [];
  const events = [];
  const sandbox = {
    window: {
      matchMedia(q) { mq.query = q; return mq; },
      addEventListener(type, fn) { if (type === 'message') messageListeners.push(fn); },
      dispatchEvent(ev) { events.push(ev); return true; },
    },
    document: { documentElement },
    location: { search, hash },
    URLSearchParams,
    CustomEvent: class { constructor(type, init) { this.type = type; this.detail = init && init.detail; } },
  };
  vm.createContext(sandbox);
  vm.runInContext(src, sandbox);
  return {
    get theme() { return documentElement.dataset.theme; },
    get mode() { return documentElement.dataset.themeMode; },
    get scheme() { return documentElement.style.colorScheme; },
    mq,
    events,
    setOs(dark) { mq.matches = dark; mq.changeListeners.forEach((fn) => fn({ matches: dark })); },
    post(origin, data) { messageListeners.forEach((fn) => fn({ origin, data })); },
  };
}

function fixtureFailures(src) {
  const fails = [];
  const expect = (name, cond) => { if (!cond) fails.push(name); };
  let r;

  // default: omitted param = auto = OS
  r = runResolver(src, { osDark: false });
  expect('no param + OS light → light, mode auto', r.theme === 'light' && r.mode === 'auto' && r.scheme === 'light');
  r = runResolver(src, { osDark: true });
  expect('no param + OS dark → dark, mode auto (NOT forced light)', r.theme === 'dark' && r.mode === 'auto' && r.scheme === 'dark');
  expect('matchMedia queried for (prefers-color-scheme: dark)', runResolver(src, {}).mq.query === '(prefers-color-scheme: dark)');
  r = runResolver(src, { osDark: false }); r.setOs(true);
  expect('auto: live OS change to dark recolors (event fired)', r.theme === 'dark' && r.events.length > 0 && r.events[r.events.length - 1].detail === 'dark');
  r.setOs(false);
  expect('auto: live OS change back to light recolors', r.theme === 'light');

  // explicit locks
  r = runResolver(src, { search: '?theme=dark', osDark: false });
  expect('?theme=dark → dark locked', r.theme === 'dark' && r.mode === 'dark');
  r.setOs(true); r.setOs(false);
  expect('?theme=dark stays dark through OS toggles', r.theme === 'dark');
  r = runResolver(src, { search: '?dark=1', osDark: false });
  expect('?dark=1 → dark locked', r.theme === 'dark' && r.mode === 'dark');
  r = runResolver(src, { search: '?dark=true', osDark: false });
  expect('?dark=true → dark locked', r.theme === 'dark');
  r = runResolver(src, { search: '?mode=dark', osDark: false });
  expect('?mode=dark → dark locked', r.theme === 'dark' && r.mode === 'dark');
  r = runResolver(src, { search: '?theme=light', osDark: true });
  expect('?theme=light → light locked (OS dark)', r.theme === 'light' && r.mode === 'light');
  r.setOs(false); r.setOs(true);
  expect('?theme=light stays light through OS toggles', r.theme === 'light');
  r = runResolver(src, { search: '?dark=0', osDark: true });
  expect('?dark=0 → light locked', r.theme === 'light' && r.mode === 'light');
  r = runResolver(src, { search: '?dark=false', osDark: true });
  expect('?dark=false → light locked', r.theme === 'light');
  r = runResolver(src, { search: '?mode=light', osDark: true });
  expect('?mode=light → light locked', r.theme === 'light');
  r = runResolver(src, { search: '?theme=light&dark=1', osDark: false });
  expect('theme= wins over dark= when both present', r.theme === 'light');
  r = runResolver(src, { search: '?theme=DARK', osDark: false });
  expect('?theme=DARK case-insensitive → dark', r.theme === 'dark');
  r = runResolver(src, { hash: '#theme=dark', osDark: false });
  expect('#theme=dark (hash) → dark locked', r.theme === 'dark' && r.mode === 'dark');
  r = runResolver(src, { hash: '#theme=light', osDark: true });
  expect('#theme=light (hash) → light locked', r.theme === 'light');

  // auto / system = follow media
  r = runResolver(src, { search: '?theme=auto', osDark: true });
  expect('?theme=auto + OS dark → dark, mode auto (not forced)', r.theme === 'dark' && r.mode === 'auto');
  r = runResolver(src, { search: '?theme=auto', osDark: false });
  expect('?theme=auto + OS light → light, mode auto (not forced)', r.theme === 'light' && r.mode === 'auto');
  r = runResolver(src, { search: '?theme=system', osDark: true });
  expect('?theme=system → follows OS (dark)', r.theme === 'dark' && r.mode === 'auto');
  r = runResolver(src, { search: '?mode=system', osDark: false });
  expect('?mode=system → follows OS (light)', r.theme === 'light' && r.mode === 'auto');
  r = runResolver(src, { search: '?theme=purple', osDark: true });
  expect('unknown theme value falls back to auto/OS', r.theme === 'dark' && r.mode === 'auto');

  // postMessage: trusted origins only, only when unlocked
  for (const o of ['https://notion.so', 'https://www.notion.so', 'https://www.notion.site', 'https://abc-1.notion.site']) {
    r = runResolver(src, { osDark: false }); r.post(o, { theme: 'dark' });
    expect(`trusted origin accepted: ${o}`, r.theme === 'dark');
  }
  for (const o of ['https://evil.example.com', 'http://www.notion.so', 'https://notion.so.evil.com', 'https://evilnotion.so', 'https://a.b.notion.so', 'https://www.notion.so.evil.com', 'null']) {
    r = runResolver(src, { osDark: false }); r.post(o, { theme: 'dark' });
    expect(`untrusted origin rejected: ${o}`, r.theme === 'light');
  }
  r = runResolver(src, { osDark: false });
  r.post('https://www.notion.so', { theme: 'dark' });
  expect('trusted {theme:"dark"} applied in auto', r.theme === 'dark');
  r.post('https://www.notion.so', { theme: 'purple' });
  expect('unknown theme payload ignored', r.theme === 'dark');
  r.post('https://www.notion.so', 'light');
  expect('string payload ignored', r.theme === 'dark');
  r.post('https://www.notion.so', null);
  expect('null payload ignored', r.theme === 'dark');
  r.post('https://www.notion.so', { darkMode: 'yes' });
  expect('non-boolean darkMode ignored', r.theme === 'dark');
  r.post('https://www.notion.site', { darkMode: false });
  expect('trusted {darkMode:false} applied', r.theme === 'light');
  r.post('https://evil.example.com', { theme: 'dark' });
  expect('untrusted message after trusted stays light', r.theme === 'light');
  r.post('https://www.notion.so', { theme: 'dark' });
  r.setOs(false);
  expect('OS change clears postMessage override and follows OS', r.theme === 'light');
  r = runResolver(src, { search: '?theme=light', osDark: true });
  r.post('https://www.notion.so', { theme: 'dark' });
  expect('locked light ignores trusted message', r.theme === 'light');
  r = runResolver(src, { search: '?dark=1', osDark: false });
  r.post('https://www.notion.so', { darkMode: false });
  expect('locked dark ignores trusted message', r.theme === 'dark');
  return fails;
}

for (const rel of FILES) {
  if (!blocks[rel]) continue;
  const script = inlineScripts(blocks[rel])[0] || '';
  const fails = fixtureFailures(script);
  check(`resolver fixtures pass (defaults, locks, live OS change, strict postMessage): ${rel}`, fails.length === 0, fails.join('\n      '));
}

// ---- 6. index.html passes explicit lock through to iframes --------------------
const idxScript = inlineScripts(html['index.html']).find((s) => s.includes('iframe[data-src]')) || '';
const DS = ['widgets/ring-test/?value=72&label=Open&color=%232383e2', 'widgets/controls-test/?toggles=1,0,1&active=2&meter=58'];
function passThrough(mode) {
  const frames = DS.map((ds) => ({ getAttribute: () => ds, src: undefined }));
  vm.runInNewContext(idxScript, { document: { documentElement: { dataset: { themeMode: mode } }, querySelectorAll: () => frames } });
  return frames.map((f) => f.src);
}
check('index.html iframes use data-src (no static src to bypass pass-through)', !/<iframe[^>]*\ssrc=/i.test(html['index.html']));
check('index pass-through: auto/omitted → iframes keep original URLs (OS-follow)',
  JSON.stringify(passThrough('auto')) === JSON.stringify(DS) && JSON.stringify(passThrough(undefined)) === JSON.stringify(DS));
check('index pass-through: ?theme=dark → iframes get theme=dark',
  JSON.stringify(passThrough('dark')) === JSON.stringify([`${DS[0]}&theme=dark`, `${DS[1]}&theme=dark`]));
check('index pass-through: ?theme=light → iframes get theme=light',
  JSON.stringify(passThrough('light')) === JSON.stringify([`${DS[0]}&theme=light`, `${DS[1]}&theme=light`]));
check('index pass-through: URL without ? gets ?theme=dark', (() => {
  const frames = [{ getAttribute: () => 'widgets/bars-test/', src: undefined }];
  vm.runInNewContext(idxScript, { document: { documentElement: { dataset: { themeMode: 'dark' } }, querySelectorAll: () => frames } });
  return frames[0].src === 'widgets/bars-test/?theme=dark';
})());

// ---- 7. multi-ring loop reload keeps location.hash (hash locks survive the loop) -
// Runs the page's own script in a vm sandbox, drives the animation frame past its duration,
// and captures the URL passed to location.replace() by the loop branch.
function loopReloadUrl(src, { search, hash }) {
  let frame = null;
  let replaced = null;
  const stub = () => ({ style: {}, textContent: '', className: '', innerHTML: '', append() {}, querySelector: () => stub() });
  const sandbox = {
    URLSearchParams,
    document: { getElementById: () => stub(), createElement: () => stub() },
    performance: { now: () => 0 },
    requestAnimationFrame(fn) { frame = fn; return 1; },
    location: { pathname: '/widgets/multi-ring/', search, hash, replace(u) { replaced = u; } },
  };
  try {
    vm.createContext(sandbox);
    vm.runInContext(src, sandbox);
    frame(1e6); // past duration → loop branch → location.replace()
  } catch (e) { return null; }
  return replaced;
}
const ML = 'widgets/multi-ring/index.html';
const mlLoop = inlineScripts(html[ML]).find((s) => s.includes("p.get('loop')")) || '';
const mlResolver = inlineScripts(blocks[ML] || '')[0] || '';
const LOOP_CASES = [
  { hash: '#theme=dark', osDark: false, want: 'dark' },
  { hash: '#mode=light', osDark: true, want: 'light' },
  { hash: '#dark=1', osDark: false, want: 'dark' },
];
const loopFails = [];
for (const c of LOOP_CASES) {
  const u = loopReloadUrl(mlLoop, { search: '?loop=1&n=6', hash: c.hash });
  const pu = u ? new URL(u, 'https://local.test/') : null;
  if (!pu || pu.hash !== c.hash || pu.searchParams.get('loop') !== '1') { loopFails.push(`${c.hash}: reload URL lost hash or loop (got ${u})`); continue; }
  const r = runResolver(mlResolver, { search: pu.search, hash: pu.hash, osDark: c.osDark });
  if (r.theme !== c.want || r.mode === 'auto') loopFails.push(`${c.hash}: after reload theme=${r.theme} mode=${r.mode}, want ${c.want} locked`);
}
check('multi-ring loop reload keeps hash locks (#theme=dark, #mode=light, #dark=1) on either OS appearance', loopFails.length === 0, loopFails.join('\n      '));

// ---- summary ------------------------------------------------------------------
const failed = results.filter((ok) => !ok).length;
console.log(`\nverify-theme: ${results.length - failed}/${results.length} checks passed`);
process.exitCode = failed ? 1 : 0;
JS
