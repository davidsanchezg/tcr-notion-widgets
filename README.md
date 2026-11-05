# tcr-notion-widgets

Public static gallery for Notion `/embed` load tests.

**Site:** https://davidsanchezg.github.io/tcr-notion-widgets/

## Rule

No secrets or TCR metrics in this repo. Widgets are presentational. Pass numbers via URL query params when embedding.

## Widget URLs

- `.../widgets/ring-test/?value=72&label=Open&color=%232383e2`
- `.../widgets/bars-test/?values=28,55,70,42,88,61`
- `.../widgets/gauge-test/?value=64&label=Capacity`
- `.../widgets/multi-ring/?n=6&values=40,55,70,35,82,60`
- `.../widgets/controls-test/?toggles=1,0,1&active=2&meter=58`

## Layout

```
widgets/<id>/index.html
```

Pages source: `main` / root.
