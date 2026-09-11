# crit

Producer side of the shared critical-value store that `exuber` (and,
planned, `pyexuber`) read from at runtime. The client is
`exuber/R/crit-bucket.R`; this directory holds everything that puts data
behind it.

```
simulate-crit.R   Monte Carlo per (lag, n) -> out/lag<L>/n<N>.bin.xz   (resumable, local only)
upload-crit.R     aws s3 sync out/ -> s3://<bucket>/crit/               (needs bucket creds)
exuber-fn.ts      Railway function "exuber-fn": read-only proxy, GET /crit2/<lag>/<n>
```

Deployed at https://exuber.up.railway.app (alias https://exubercrit.kvasilopoulos.com).
Railway project `exuber`, bucket `exuber-storage`. Bounds enforced by the
proxy: lag 0–4, n 6–5000.

## Coverage (2026-09-11)

| lag | n         | status                              |
|-----|-----------|-------------------------------------|
| 0   | 6–600     | bundled in `exuber::radf_crit`, not in the bucket |
| 0   | 601–2000  | live                                |
| 0   | 2001–5000 | not simulated                       |
| 1–4 | any       | not simulated                       |

Anything not covered makes `radf()` (without a user-supplied `cv`) error
with "haven't been simulated yet".

## Workflow

```sh
# 1. simulate in bounded chunks (cost ~ n^2.9; check simulate-crit.log)
Rscript simulate-crit.R 1 1 6 300         # lag 1, n 6:300
Rscript simulate-crit.R 1 4 6 2000        # lag 1:4, n 6:2000
# 2. upload (AWS_ACCESS_KEY_ID/SECRET from `railway bucket credentials -b exuber-storage`)
Rscript upload-crit.R
# 3. only if exuber-fn.ts changed
railway functions push -p exuber-fn.ts
# 4. verify
curl -sI https://exuber.up.railway.app/crit2/1/100 | head -1
```

Binary layout (little-endian): `int32 x4: n, minw, lag, nrows` then
`float64 x3` each for adf/sadf/gsadf (90/95/99%), then `float64 x(nrows*3)`
bsadf row-major. `badf_cv` isn't stored (constant asymptotic tiling).
