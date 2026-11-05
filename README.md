# tcr-notion-widgets

Public static gallery for Notion `/embed` load tests.

**Site (inline grid):** https://davidsanchezg.github.io/tcr-notion-widgets/

The root `index.html` iframes all five widgets so Notion shows them without clicks.

## Rule

No secrets or TCR metrics in this repo. Pass numbers via URL query params.

## Individual widgets

- `widgets/ring-test/?value=72&label=Open&color=%232383e2`
- `widgets/bars-test/?values=28,55,70,42,88,61`
- `widgets/gauge-test/?value=64&label=Capacity`
- `widgets/multi-ring/?n=6&values=40,55,70,35,82,60`
- `widgets/controls-test/?toggles=1,0,1&active=2&meter=58`

Pages source: `main` / root.

## Dark / light theme

Every page follows the host OS appearance by default (`prefers-color-scheme`). Switching the Mac or TV between Light and Dark recolors the widgets live; no embed URL change is needed.

Explicit overrides (query or `#hash`):

- `?theme=light` or `?theme=dark` force a palette and lock it.
- `?theme=auto` or `?theme=system` follow the OS (same as omitting the param).
- Aliases: `?mode=light|dark|auto|system`, and `?dark=1|0` (also `true|false`).

Notion does not send a theme param to `/embed` iframes, so widgets use the OS appearance instead. That is what makes a Notion page on a Dark Mode TV or desktop adapt automatically. The resolver runs synchronously in `<head>`, so there is no white flash on a dark OS.

The index gallery header has `auto` / `light` / `dark` links. A forced theme on the index is passed through to all five preview iframes; `auto` (or no param) leaves them following the OS.

Light palette (`#ffffff` bg, `#f7f6f3` card, `#e9e9e7` line, `#ecebea` track, `#37352f` ink, `#787774` muted) and dark palette (`#191919` bg, `#202020` card, `#373737` line, `#2f2f2f` track, `#e6e6e6` ink, `#9b9b9b` muted) are defined once per page as CSS custom properties. Semantic accents are the same in both palettes.

Trusted parent messages: a `message` listener accepts only `https://*.notion.so` and `https://*.notion.site` origins, with payload `{theme:'dark'|'light'}` or `{darkMode:boolean}`. It is ignored when the URL locks light or dark.

Verify the contract (needs `node`, no npm deps):

```sh
scripts/verify-theme.sh
```

## TCR Control Room glance

`widgets/tcr-glance/?cards=0&needs=1&active=7&states=En%20curso,Planeado&stateVals=6,1&seats=Cryptor,unknown&seatVals=4,3`

Params only. Normally no theme param is needed; the glance follows the OS. Use `&theme=light` or `&theme=dark` only to force a palette. Bump Control Room embed `?v=` after each Pages deploy, as today.
