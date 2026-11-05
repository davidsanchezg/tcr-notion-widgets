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

## TCR Control Room glance

`widgets/tcr-glance/?cards=0&needs=1&active=7&states=En%20curso,Planeado&stateVals=6,1&seats=Cryptor,unknown&seatVals=4,3`

Params only — bump Control Room embed `?v=` after each deploy.
